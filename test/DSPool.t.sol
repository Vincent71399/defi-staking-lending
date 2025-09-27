// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DSPool} from "../src/DSPool.sol";
import {DSCoin} from "../src/DSCoin.sol";
import {OracleLib} from "../src/libraries/OracleLib.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";
import {MockWickedToken} from "./mocks/MockWickedToken.sol";
import {DeployDSPool} from "../script/DeployDSPool.s.sol";

contract DSPoolTest is Test {
    using OracleLib for address;

    DSPool internal dsPool;
    DSCoin internal dsc;
    HelperConfig internal helperConfig;

    address internal ethUsdPriceFeed;
    address internal btcUsdPriceFeed;
    address internal linkUsdPriceFeed;

    address internal weth;
    address internal wbtc;
    address internal link;
    address internal unsupportedToken;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal jimmy = makeAddr("jimmy");

    function setUp() public {
        DeployDSPool deployDSPool = new DeployDSPool();

        (dsPool, dsc, helperConfig) = deployDSPool.run();
        address[] memory priceFeeds = helperConfig.getPriceFeeds();
        ethUsdPriceFeed = priceFeeds[0];
        btcUsdPriceFeed = priceFeeds[1];
        linkUsdPriceFeed = priceFeeds[2];

        address[] memory tokens = helperConfig.getTokens();
        weth = tokens[0];
        wbtc = tokens[1];
        link = tokens[2];

        unsupportedToken = address(new MockToken("Unsupported Token", "UNSUP"));

        _initCollateral(alice);
        _initCollateral(bob);
        _initCollateral(jimmy);
    }

    function _initCollateral(address user) private {
        address[] memory tokens = helperConfig.getTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            MockToken token = MockToken(tokens[i]);
            // mint 1 token for each collateral
            uint256 amount = 10 ** token.decimals();
            token.mint(user, amount);
        }
        uint256 unsupported_token_amount = 10 ** MockToken(unsupportedToken).decimals();
        MockToken(unsupportedToken).mint(user, unsupported_token_amount);
    }

    modifier depositAllCollateral(address user) {
        address[] memory tokens = helperConfig.getTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            vm.startPrank(user);
            uint256 amount = IERC20(tokens[i]).balanceOf(user);
            IERC20(tokens[i]).approve(address(dsPool), amount);
            dsPool.depositCollateral(tokens[i], amount);
            vm.stopPrank();
        }
        _;
    }

    modifier depositOneEth(address user) {
        vm.startPrank(user);
        uint256 amount = 1 ether;
        IERC20(weth).approve(address(dsPool), amount);
        dsPool.depositCollateral(weth, amount);
        vm.stopPrank();
        _;
    }

    modifier mintMaxDSC(address user) {
        uint256 maxDSC = dsPool.getMaxDSCUserCanMint(user);
        vm.startPrank(user);
        dsPool.mintDSC(maxDSC);
        vm.stopPrank();
        _;
    }

    // constructor test
    function testConstructorZeroLengthToken() public {
        address[] memory tokens = new address[](0);
        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = ethUsdPriceFeed;
        priceFeeds[1] = btcUsdPriceFeed;
        vm.startPrank(owner);
        vm.expectRevert(DSPool.DSPool__TokenAddressesAndPriceFeedAddressesNeedToBeGreaterThanZero.selector);
        new DSPool(tokens, priceFeeds, address(dsc));
        vm.stopPrank();
    }

    function testConstructorZeroLengthPriceFeed() public {
        address[] memory tokens = new address[](2);
        address[] memory priceFeeds = new address[](0);
        tokens[0] = weth;
        tokens[1] = wbtc;
        vm.startPrank(owner);
        vm.expectRevert(DSPool.DSPool__TokenAddressesAndPriceFeedAddressesNeedToBeGreaterThanZero.selector);
        new DSPool(tokens, priceFeeds, address(dsc));
        vm.stopPrank();
    }

    function testConstructorTokenLengthNotMatchPriceFeedLength() public {
        address[] memory tokens = new address[](2);
        address[] memory priceFeeds = new address[](3);
        tokens[0] = weth;
        tokens[1] = wbtc;
        priceFeeds[0] = ethUsdPriceFeed;
        priceFeeds[1] = btcUsdPriceFeed;
        priceFeeds[2] = linkUsdPriceFeed;
        vm.startPrank(owner);
        vm.expectRevert(DSPool.DSPool__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSPool(tokens, priceFeeds, address(dsc));
        vm.stopPrank();
    }

    // function test
    function testDepositUnsupportedToken() public {
        vm.startPrank(alice);
        uint256 amount = IERC20(unsupportedToken).balanceOf(alice);
        IERC20(unsupportedToken).approve(address(dsPool), amount);
        vm.expectPartialRevert(DSPool.DSPool__TokenNotAllowed.selector);
        dsPool.depositCollateral(unsupportedToken, amount);
        vm.stopPrank();
    }

    function testDepositZeroAmountReverts() public {
        vm.startPrank(alice);
        IERC20(weth).approve(address(dsPool), 0);
        vm.expectRevert(DSPool.DSPool__NeedsMoreThanZero.selector);
        dsPool.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testDeposit() public {
        vm.startPrank(alice);
        uint256 amount = IERC20(weth).balanceOf(alice);
        IERC20(weth).approve(address(dsPool), amount);
        vm.expectEmit(true, false, false, true, address(dsPool));
        emit DSPool.CollateralDeposited(alice, weth, amount);
        dsPool.depositCollateral(weth, amount);
        vm.stopPrank();

        uint256 totalValue = dsPool.getUserTotalCollateralValueInUSD(alice);
        console.log("Total Collateral Value of User1 in USD: ", totalValue);
        assert(totalValue > 0);
        uint256 maxDSC = dsPool.getMaxDSCUserCanMint(alice);
        console.log("Max DSC User1 can mint: ", maxDSC);
    }

    function testDepositSingleCollateral() public {
        vm.startPrank(alice);
        uint256 amount = IERC20(weth).balanceOf(alice);
        IERC20(weth).approve(address(dsPool), amount);
        dsPool.depositCollateral(weth, amount);
        assertEq(dsPool.getUserTotalCollateralValueInUSD(alice), ethUsdPriceFeed.getActualPrice());
        vm.stopPrank();

        vm.startPrank(bob);
        amount = IERC20(wbtc).balanceOf(bob);
        IERC20(wbtc).approve(address(dsPool), amount);
        dsPool.depositCollateral(wbtc, amount);
        assertEq(dsPool.getUserTotalCollateralValueInUSD(bob), btcUsdPriceFeed.getActualPrice());
        vm.stopPrank();
    }

    function test_DepositCollateral_TransferFromFail_ReturnFalse() public {
        MockWickedToken wickedToken = new MockWickedToken("Wicked Token", "WICK");
        wickedToken.mint(alice, 1 ether);

        address[] memory tokens = new address[](2);
        address[] memory priceFeeds = new address[](2);
        tokens[0] = address(wickedToken);
        tokens[1] = wbtc;
        priceFeeds[0] = ethUsdPriceFeed;
        priceFeeds[1] = btcUsdPriceFeed;
        vm.startPrank(owner);
        DSPool wickedDsPool = new DSPool(tokens, priceFeeds, address(dsc));
        DSCoin wickedDsc = new DSCoin();
        wickedDsc.transferOwnership(address(wickedDsPool));
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 amount = wickedToken.balanceOf(alice);
        wickedToken.approve(address(wickedDsPool), amount);
        vm.expectRevert(DSPool.DSPool__TokenTransferFailed.selector);
        wickedDsPool.depositCollateral(address(wickedToken), amount);
        vm.stopPrank();
    }

    function testDepositMintInOneStep() public {
        uint256 amountToDeposit = 1 ether;
        uint256 amountDSCMint = uint256(ethUsdPriceFeed.getSimplePrice());
        vm.startPrank(alice);
        IERC20(weth).approve(address(dsPool), amountToDeposit);
        dsPool.depositCollateralAndMintDSC(weth, amountToDeposit, amountDSCMint);
        vm.stopPrank();

        uint256 dscBalance = dsc.balanceOf(alice);
        console.log("DSC Balance of User1: ", dscBalance);
        assert(dscBalance == amountDSCMint);
    }

    function testDepositAndMintSingleTxRevertsIfWouldBreakHF() public {
        // Deposit tiny amount then try mint way too much -> revert on mint (whole tx reverts including deposit)
        uint256 amountToDeposit = 1e9; // very small (assuming 18 decimals)
        uint256 tooMuch = 1e24;
        vm.startPrank(alice);
        IERC20(weth).approve(address(dsPool), amountToDeposit);
        vm.expectRevert(DSPool.DSPool__HealthFactorTooLow.selector);
        dsPool.depositCollateralAndMintDSC(weth, amountToDeposit, tooMuch);
        vm.stopPrank();

        // Ensure no collateral was actually deposited due to revert
        assertEq(dsPool.getUserCollateralDeposited(alice, weth), 0);
    }

    function testMint(uint256 mintAmount) public depositAllCollateral(alice) {
        uint256 maxDSC = dsPool.getMaxDSCUserCanMint(alice);
        mintAmount = bound(mintAmount, 1, maxDSC);
        vm.prank(alice);
        dsPool.mintDSC(mintAmount);

        uint256 dscBalance = dsc.balanceOf(alice);
        assert(dscBalance == mintAmount);
    }

    function testMintWithoutCollateralReverts() public {
        // user1 has minted collateral in setUp via _initCollateral, but hasn't deposited
        uint256 tryMint = 1e18;
        vm.startPrank(alice);
        vm.expectRevert(DSPool.DSPool__HealthFactorTooLow.selector);
        dsPool.mintDSC(tryMint);
        vm.stopPrank();
    }

    function testMintExceedMaxLimit() public depositAllCollateral(alice) {
        uint256 maxDSC = dsPool.getMaxDSCUserCanMint(alice);
        vm.prank(alice);
        vm.expectRevert(DSPool.DSPool__HealthFactorTooLow.selector);
        dsPool.mintDSC(maxDSC + 1);
    }

    function testMintZero() public depositAllCollateral(alice) {
        vm.prank(alice);
        vm.expectRevert(DSPool.DSPool__NeedsMoreThanZero.selector);
        dsPool.mintDSC(0);
    }

    function testBurn(uint256 burnAmount) public depositAllCollateral(alice) mintMaxDSC(alice) {
        uint256 maxDSC = dsc.balanceOf(alice);
        vm.startPrank(alice);
        // burn
        burnAmount = bound(burnAmount, 1, maxDSC);
        dsc.approve(address(dsPool), burnAmount);
        dsPool.burnDSC(burnAmount);
        uint256 dscBalance = dsc.balanceOf(alice);
        assert(dscBalance == maxDSC - burnAmount);
        vm.stopPrank();
    }

    function testBurnIncreasesHealthFactor() public depositOneEth(alice) {
        // Mint 80% of max, then burn half; HF should increase after burn.
        uint256 maxDSC = dsPool.getMaxDSCUserCanMint(alice);
        uint256 mintAmt = (maxDSC * 80) / 100;
        vm.startPrank(alice);
        dsPool.mintDSC(mintAmt);
        uint256 hfBefore = dsPool.getHealthFactor(alice);
        dsc.approve(address(dsPool), mintAmt / 2);
        dsPool.burnDSC(mintAmt / 2);
        uint256 hfAfter = dsPool.getHealthFactor(alice);
        vm.stopPrank();
        assertGt(hfAfter, hfBefore);
    }

    function testBurnExceedBalance() public depositAllCollateral(alice) mintMaxDSC(alice) {
        uint256 burnAmount = dsc.balanceOf(alice) + 1;
        vm.startPrank(alice);
        dsc.approve(address(dsPool), burnAmount);
        vm.expectRevert(DSPool.DSPool__BurnAmountExceedsBalance.selector);
        dsPool.burnDSC(burnAmount);
        vm.stopPrank();
    }

    function testBurnZero() public depositAllCollateral(alice) mintMaxDSC(alice) {
        vm.startPrank(alice);
        vm.expectRevert(DSPool.DSPool__NeedsMoreThanZero.selector);
        dsPool.burnDSC(0);
        vm.stopPrank();
    }

    function testRedeemZeroReverts() public depositOneEth(alice) {
        vm.startPrank(alice);
        vm.expectRevert(DSPool.DSPool__NeedsMoreThanZero.selector);
        dsPool.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeem(uint256 amountToRedeem) public depositOneEth(alice) {
        uint256 initialCollateral = dsPool.getUserCollateralDeposited(alice, weth);
        amountToRedeem = bound(amountToRedeem, 1, initialCollateral);
        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true, address(dsPool));
        emit DSPool.CollateralRedeemed(alice, alice, weth, amountToRedeem);
        dsPool.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();
        uint256 newCollateral = dsPool.getUserCollateralDeposited(alice, weth);
        assert(newCollateral == initialCollateral - amountToRedeem);
    }

    function testRedeemExceedBalance() public depositOneEth(alice) {
        uint256 initialCollateral = dsPool.getUserCollateralDeposited(alice, weth);
        uint256 amountToRedeem = initialCollateral + 1;
        vm.startPrank(alice);
        vm.expectRevert();
        dsPool.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();
    }

    function testRedeemBreaksHealthFactorReverts() public depositOneEth(alice) mintMaxDSC(alice) {
        // With max minted, HF == 1. Redeeming any nonzero collateral will break HF.
        vm.startPrank(alice);
        vm.expectRevert(DSPool.DSPool__HealthFactorTooLow.selector);
        dsPool.redeemCollateral(weth, 1);
        vm.stopPrank();
    }

    function testRedeemBurnDSCInOneStep() public depositOneEth(alice) {
        uint256 initialCollateral = dsPool.getUserCollateralDeposited(alice, weth);
        uint256 dscAmount = dsPool.getMaxDSCUserCanMint(alice);
        vm.startPrank(alice);
        dsPool.mintDSC(dscAmount);
        // redeem all collateral by burning max DSC
        uint256 initialDSCBalance = dsc.balanceOf(alice);
        uint256 initialCollateralBalance = IERC20(weth).balanceOf(alice);
        dsc.approve(address(dsPool), dscAmount);
        dsPool.redeemCollateralAndBurnDSC(weth, initialCollateral, dscAmount);
        uint256 newDSCBalance = dsc.balanceOf(alice);
        uint256 newCollateralBalance = IERC20(weth).balanceOf(alice);
        assert(newDSCBalance == initialDSCBalance - dscAmount);
        assert(newCollateralBalance == initialCollateralBalance + initialCollateral);
        vm.stopPrank();
    }

    function testRedeemCollateralAndBurnDSCPartialKeepsHealthSafe() public depositOneEth(alice) {
        // Mint some DSC, then redeem a portion while burning a portion in same tx.
        uint256 maxDSC = dsPool.getMaxDSCUserCanMint(alice);
        uint256 mintAmt = (maxDSC * 60) / 100;
        vm.startPrank(alice);
        dsPool.mintDSC(mintAmt);

        uint256 initialDSCBal = dsc.balanceOf(alice);
        uint256 initialWethBal = IERC20(weth).balanceOf(alice);
        uint256 deposited = dsPool.getUserCollateralDeposited(alice, weth);

        uint256 redeemAmt = deposited / 2;
        uint256 burnAmt = mintAmt / 2;

        dsc.approve(address(dsPool), burnAmt);
        dsPool.redeemCollateralAndBurnDSC(weth, redeemAmt, burnAmt);

        // Post conditions
        assertEq(dsc.balanceOf(alice), initialDSCBal - burnAmt);
        assertEq(IERC20(weth).balanceOf(alice), initialWethBal + redeemAmt);

        // Health factor should remain >= 1
        assertFalse(dsPool.isLiquidatable(alice));
        vm.stopPrank();
    }

    // test price drop and liquidation
    function testPriceDrop() public depositOneEth(alice) mintMaxDSC(alice) {
        uint256 initValue = dsPool.getUserTotalCollateralValueInUSD(alice);
        console.log("Total Collateral Value of User1 in USD: ", initValue);

        uint256 initHealthFactor = dsPool.getHealthFactor(alice);
        console.log("Init Health Factor of User1: ", initHealthFactor);
        assertFalse(dsPool.isLiquidatable(alice));
        assertEq(dsPool.getUserDebt(alice), 0);
        int256 currentETHPrice = ethUsdPriceFeed.getSimplePrice();
        console.log("Current ETH Price: ", currentETHPrice);
        // drop price by 20%
        currentETHPrice = currentETHPrice * 80 / 100;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(currentETHPrice);
        uint256 newValue = dsPool.getUserTotalCollateralValueInUSD(alice);
        console.log("Total Collateral Value of User1 in USD: ", newValue);
        assertApproxEqAbs(newValue, initValue * 80 / 100, 2);
        uint256 newHealthFactor = dsPool.getHealthFactor(alice);
        console.log("New Health Factor of User1: ", newHealthFactor);
        assertGt(initHealthFactor, newHealthFactor);
        assertTrue(dsPool.isLiquidatable(alice));
        assertGt(dsPool.getUserDebt(alice), 0);
    }

    // test liquidation
    function testLiquidation() public depositOneEth(alice) depositAllCollateral(bob) {
        uint256 user1_init_weth_deposited = dsPool.getUserCollateralDeposited(alice, weth);
        uint256 user2_init_weth = IERC20(weth).balanceOf(bob);

        uint256 dscUser1Mint = dsPool.getMaxDSCUserCanMint(alice);
        vm.prank(alice);
        dsPool.mintDSC(dscUser1Mint);

        int256 currentETHPrice = ethUsdPriceFeed.getSimplePrice();
        // drop price by 20%
        currentETHPrice = currentETHPrice * 80 / 100;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(currentETHPrice);
        assertTrue(dsPool.isLiquidatable(alice));
        uint256 user1Debt = dsPool.getUserDebt(alice);
        assertEq(user1Debt, dscUser1Mint);

        // liquidator is user2, mint enough DSC to cover 50% of user1 debt
        uint256 dscToCover = user1Debt / 2;
        vm.startPrank(bob);
        dsPool.mintDSC(dscToCover);
        dsc.approve(address(dsPool), dscToCover);
        dsPool.liquidate(weth, alice, dscToCover);
        vm.stopPrank();

        uint256 user1_final_weth_deposited = dsPool.getUserCollateralDeposited(alice, weth);
        uint256 user2_final_weth = IERC20(weth).balanceOf(bob);

        uint256 user2_weth_gained = user2_final_weth - user2_init_weth;
        assertGt(user2_weth_gained, 0);
        assertEq(user2_weth_gained, user1_init_weth_deposited - user1_final_weth_deposited);
    }

    function testLiquidateWhenNotLiquidatableReverts() public depositOneEth(alice) depositAllCollateral(bob) {
        // user1 is healthy
        assertFalse(dsPool.isLiquidatable(alice));
        vm.startPrank(bob);
        dsPool.mintDSC(1e18);
        dsc.approve(address(dsPool), 1e18);
        vm.expectRevert(DSPool.DSPool__UserNotLiquidatable.selector);
        dsPool.liquidate(weth, alice, 1e18);
        vm.stopPrank();
    }

    function testLiquidateCoverOverDebt() public depositOneEth(alice) depositAllCollateral(bob) {
        uint256 user1_init_weth_deposited = dsPool.getUserCollateralDeposited(alice, weth);
        uint256 user2_init_weth = IERC20(weth).balanceOf(bob);

        uint256 dscUser1Mint = dsPool.getMaxDSCUserCanMint(alice);
        vm.prank(alice);
        dsPool.mintDSC(dscUser1Mint);

        int256 currentETHPrice = ethUsdPriceFeed.getSimplePrice();
        // drop price by 20%
        currentETHPrice = currentETHPrice * 80 / 100;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(currentETHPrice);
        assertTrue(dsPool.isLiquidatable(alice));
        uint256 user1Debt = dsPool.getUserDebt(alice);
        assertEq(user1Debt, dscUser1Mint);

        // liquidator all user1 debt
        uint256 dscToCover = user1Debt + 1;
        vm.startPrank(bob);
        dsPool.mintDSC(dscToCover);
        dsc.approve(address(dsPool), dscToCover);
        dsPool.liquidate(weth, alice, dscToCover);
        vm.stopPrank();

        uint256 user1_final_weth_deposited = dsPool.getUserCollateralDeposited(alice, weth);
        uint256 user2_final_weth = IERC20(weth).balanceOf(bob);

        uint256 user2_weth_gained = user2_final_weth - user2_init_weth;
        assertGt(user2_weth_gained, 0);
        assertEq(user2_weth_gained, user1_init_weth_deposited - user1_final_weth_deposited);
    }

    function testLiquidateEndingHealthBecomeWorst() public depositOneEth(alice) depositAllCollateral(bob) {
        uint256 dscUser1Mint = dsPool.getMaxDSCUserCanMint(alice);
        vm.prank(alice);
        dsPool.mintDSC(dscUser1Mint);

        int256 currentETHPrice = ethUsdPriceFeed.getSimplePrice();
        // drop price by 50%
        currentETHPrice = currentETHPrice * 50 / 100;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(currentETHPrice);
        assertTrue(dsPool.isLiquidatable(alice));
        uint256 user1Debt = dsPool.getUserDebt(alice);
        assertEq(user1Debt, dscUser1Mint);

        // liquidator is user2, mint enough DSC to cover 50% of user1 debt
        uint256 dscToCover = user1Debt / 2;
        vm.startPrank(bob);
        dsPool.mintDSC(dscToCover);
        dsc.approve(address(dsPool), dscToCover);
        vm.expectRevert(DSPool.DSPool__HealthFactorNotImproved.selector);
        dsPool.liquidate(weth, alice, dscToCover);
        vm.stopPrank();
    }

    // test getters
    function testGettersHealthyUserDebtZero() public depositOneEth(alice) {
        assertFalse(dsPool.isLiquidatable(alice));
        assertEq(dsPool.getUserDebt(alice), 0);
    }

    function testHealthFactorMaxWhenNoDebt() public depositOneEth(alice) {
        // When no debt, internal HF returns type(uint256).max; public getter exposes the computed value.
        uint256 hf = dsPool.getHealthFactor(alice);
        assertEq(hf, type(uint256).max);
    }

    function testGetUserTotalCollateralValueMultiToken() public depositAllCollateral(alice) {
        // 1 unit of each token was minted to user1 in setUp and fully deposited via modifier.
        uint256 expected = uint256(ethUsdPriceFeed.getActualPrice()) + uint256(btcUsdPriceFeed.getActualPrice())
            + uint256(linkUsdPriceFeed.getActualPrice());
        assertApproxEqAbs(dsPool.getUserTotalCollateralValueInUSD(alice), expected, 2);
    }

    function testGetMaxDSCUserCanMintMatchesThreshold() public depositAllCollateral(alice) {
        // LIQUIDATION_THRESHOLD = 50, LIQUIDATION_PRECISION = 100
        uint256 totalUsd = dsPool.getUserTotalCollateralValueInUSD(alice);
        uint256 expectedMax = (totalUsd * 50) / 100;
        assertEq(dsPool.getMaxDSCUserCanMint(alice) / 1e18, expectedMax); // internal uses 18-dec scaled values
            // Explanation:
            // getUserTotalCollateralValueInUSD returns an unscaled USD (already divided by 1e18),
            // while getMax... uses the internal 18-dec value. Multiply back by 1e18 for equality.
    }

    function testGetUserCollateralDepositedUnsupportedTokenReverts() public {
        vm.expectPartialRevert(DSPool.DSPool__TokenNotAllowed.selector);
        dsPool.getUserCollateralDeposited(alice, unsupportedToken);
    }

    // ----------------------------
    // getMaxRedeemableCollateral()
    // ----------------------------

    function testGetMaxRedeemableCollateral_NoDebt_AllRedeemable() public depositOneEth(alice) {
        uint256 deposited = dsPool.getUserCollateralDeposited(alice, weth);
        uint256 maxRedeem = dsPool.getMaxRedeemableCollateral(alice, weth);
        assertEq(maxRedeem, deposited, "when no debt, full balance should be redeemable");

        // Redeeming full amount must succeed and HF stays >= 1 (actually max uint when no debt)
        vm.startPrank(alice);
        dsPool.redeemCollateral(weth, maxRedeem);
        vm.stopPrank();
        assertEq(dsPool.getUserCollateralDeposited(alice, weth), 0);
        assertFalse(dsPool.isLiquidatable(alice));
    }

    function testGetMaxRedeemableCollateral_HFEqualsOne_ReturnsZero() public depositOneEth(alice) mintMaxDSC(alice) {
        // At max mint, HF == 1, so you can't redeem anything safely
        uint256 maxRedeem = dsPool.getMaxRedeemableCollateral(alice, weth);
        assertEq(maxRedeem, 0, "at HF=1, nothing should be redeemable");

        vm.startPrank(alice);
        vm.expectRevert(DSPool.DSPool__HealthFactorTooLow.selector);
        dsPool.redeemCollateral(weth, 1);
        vm.stopPrank();
    }

    function testGetMaxRedeemableCollateral_RedeemExactlyMax_Succeeds() public depositOneEth(alice) {
        // Mint to a safe HF > 1, so some headroom exists
        uint256 maxDSC = dsPool.getMaxDSCUserCanMint(alice);
        uint256 mintAmt = (maxDSC * 60) / 100;
        vm.startPrank(alice);
        dsPool.mintDSC(mintAmt);

        uint256 beforeHF = dsPool.getHealthFactor(alice);
        uint256 maxRedeem = dsPool.getMaxRedeemableCollateral(alice, weth);
        assertGt(maxRedeem, 0, "should have some redeemable headroom");

        // Redeeming exactly the max should NOT break HF
        dsPool.redeemCollateral(weth, maxRedeem);
        uint256 afterHF = dsPool.getHealthFactor(alice);
        vm.stopPrank();

        assertGe(afterHF, 1e18, "HF must remain >= 1 after redeeming max");
        // Typically HF goes down or stays same after redeeming
        assertLe(afterHF, beforeHF);
        assertFalse(dsPool.isLiquidatable(alice));
    }

    function testGetMaxRedeemableCollateral_RedeemMaxPlusOne_Reverts() public depositOneEth(alice) {
        uint256 maxDSC = dsPool.getMaxDSCUserCanMint(alice);
        uint256 mintAmt = (maxDSC * 60) / 100;
        vm.startPrank(alice);
        dsPool.mintDSC(mintAmt);

        uint256 maxRedeem = dsPool.getMaxRedeemableCollateral(alice, weth);
        // If headroom exists, redeeming just 1 wei more should fail due to HF < 1
        vm.expectRevert(DSPool.DSPool__HealthFactorTooLow.selector);
        dsPool.redeemCollateral(weth, maxRedeem + 1);
        vm.stopPrank();
    }

    function testGetMaxRedeemableCollateral_MultiToken_OnlyAffectsChosenToken() public depositAllCollateral(alice) {
        // Mint to ~40% of max so there's room
        uint256 maxDSC = dsPool.getMaxDSCUserCanMint(alice);
        uint256 mintAmt = (maxDSC * 40) / 100;

        vm.startPrank(alice);
        dsPool.mintDSC(mintAmt);

        uint256 wethBefore = dsPool.getUserCollateralDeposited(alice, weth);
        uint256 wbtcBefore = dsPool.getUserCollateralDeposited(alice, wbtc);

        uint256 maxRedeemWeth = dsPool.getMaxRedeemableCollateral(alice, weth);
        assertGt(maxRedeemWeth, 0, "expect some redeemable WETH");

        dsPool.redeemCollateral(weth, maxRedeemWeth);
        vm.stopPrank();

        // Only WETH balance should change
        assertEq(dsPool.getUserCollateralDeposited(alice, weth), wethBefore - maxRedeemWeth);
        assertEq(dsPool.getUserCollateralDeposited(alice, wbtc), wbtcBefore);

        // HF must remain safe
        assertFalse(dsPool.isLiquidatable(alice));
        assertGe(dsPool.getHealthFactor(alice), 1e18);
    }

    function testGetMaxRedeemableCollateral_DecreasesAfterPriceDrop() public depositOneEth(alice) {
        // Create headroom
        uint256 maxDSC = dsPool.getMaxDSCUserCanMint(alice);
        uint256 mintAmt = (maxDSC * 20) / 100;
        vm.startPrank(alice);
        dsPool.mintDSC(mintAmt);
        vm.stopPrank();

        uint256 before = dsPool.getMaxRedeemableCollateral(alice, weth);

        // 20% ETH price drop
        int256 p = ethUsdPriceFeed.getSimplePrice();
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer((p * 80) / 100);

        uint256 afterDrop = dsPool.getMaxRedeemableCollateral(alice, weth);
        assertLe(afterDrop, before, "redeemable should not increase after a price drop");
    }

    function testGetMaxRedeemableCollateral_UnsupportedToken_Reverts() public {
        vm.expectPartialRevert(DSPool.DSPool__TokenNotAllowed.selector);
        dsPool.getMaxRedeemableCollateral(alice, unsupportedToken);
    }

    function testGetMaxRedeemableCollateral_NoDeposit_ReturnsZero() public {
        // bob has minted tokens in setUp but hasn't deposited any collateral
        uint256 maxRedeem = dsPool.getMaxRedeemableCollateral(bob, weth);
        assertEq(maxRedeem, 0);
    }
}
