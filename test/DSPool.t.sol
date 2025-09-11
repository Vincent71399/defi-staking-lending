// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DSPool } from "../src/DSPool.sol";
import { DSCoin } from "../src/DSCoin.sol";
import { OracleLib } from "../src/libraries/OracleLib.sol";
import { HelperConfig } from "../script/HelperConfig.s.sol";
import { MockToken } from "./mocks/MockToken.sol";
import { MockV3Aggregator } from "./mocks/MockV3Aggregator.sol";


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

    address internal owner = makeAddr("owner");
    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");

    function setUp() public {
        helperConfig = new HelperConfig();
        address[] memory priceFeeds = helperConfig.getPriceFeeds();
        ethUsdPriceFeed = priceFeeds[0];
        btcUsdPriceFeed = priceFeeds[1];
        linkUsdPriceFeed = priceFeeds[2];

        address[] memory tokens = helperConfig.getTokens();
        weth = tokens[0];
        wbtc = tokens[1];
        link = tokens[2];

        vm.startPrank(owner);
        dsc = new DSCoin();
        dsPool = new DSPool(helperConfig.getTokens(), priceFeeds, address(dsc));
        dsc.transferOwnership(address(dsPool));
        vm.stopPrank();

        _initCollateral(user1);
        _initCollateral(user2);
    }

    function _initCollateral(address user) private {
        address[] memory tokens = helperConfig.getTokens();
        for(uint i = 0; i < tokens.length; i++){
            MockToken token = MockToken(tokens[i]);
            uint256 amount = 10 ** token.decimals();
            token.mint(user, amount);
        }
    }

    modifier depositAllCollateral(address user) {
        address[] memory tokens = helperConfig.getTokens();
        for(uint i = 0; i < tokens.length; i++){
            vm.startPrank(user);
            uint256 amount = IERC20(tokens[i]).balanceOf(user1);
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

    function testDeposit() public depositAllCollateral(user1) {
        uint256 totalValue = dsPool._calculateUserTotalCollateralValue(user1);
        console.log("Total Collateral Value of User1 in USD: ", totalValue);
        assert(totalValue > 0);
        uint256 maxDSC = dsPool.getMaxDSCUserCanMint(user1);
        console.log("Max DSC User1 can mint: ", maxDSC);
    }

    function testMint(uint256 mintAmount) public depositAllCollateral(user1) {
        uint256 maxDSC = dsPool.getMaxDSCUserCanMint(user1);
        mintAmount = bound(mintAmount, 1, maxDSC);
        vm.prank(user1);
        dsPool.mintDSC(mintAmount);

        uint256 dscBalance = dsc.balanceOf(user1);
        console.log("DSC Balance of User1: ", dscBalance);
        assert(dscBalance == mintAmount);
    }

    function testMintExceedMaxLimit() public depositAllCollateral(user1) {
        uint256 maxDSC = dsPool.getMaxDSCUserCanMint(user1);
        vm.prank(user1);
        vm.expectRevert(DSPool.DSPool__HealthFactorTooLow.selector);
        dsPool.mintDSC(maxDSC + 1);
    }

    function testMintZero() public depositAllCollateral(user1) {
        vm.prank(user1);
        vm.expectRevert(DSPool.DSPool__NeedsMoreThanZero.selector);
        dsPool.mintDSC(0);
    }

    function testBurn(uint256 burnAmount) public depositAllCollateral(user1) mintMaxDSC(user1) {
        uint256 maxDSC = dsc.balanceOf(user1);
        vm.startPrank(user1);
        // burn
        burnAmount = bound(burnAmount, 1, maxDSC);
        dsc.approve(address(dsPool), burnAmount);
        dsPool.burnDSC(burnAmount);
        uint256 dscBalance = dsc.balanceOf(user1);
        console.log("DSC Balance of User1: ", dscBalance);
        assert(dscBalance == maxDSC - burnAmount);
        vm.stopPrank();
    }

    function testBurnExceedBalance() public depositAllCollateral(user1) mintMaxDSC(user1) {
        uint256 burnAmount = dsc.balanceOf(user1) + 1;
        vm.startPrank(user1);
        dsc.approve(address(dsPool), burnAmount);
        vm.expectRevert(DSPool.DSPool__BurnAmountExceedsBalance.selector);
        dsPool.burnDSC(burnAmount);
        vm.stopPrank();
    }

    function testBurnZero() public depositAllCollateral(user1) mintMaxDSC(user1) {
        vm.startPrank(user1);
        vm.expectRevert(DSPool.DSPool__NeedsMoreThanZero.selector);
        dsPool.burnDSC(0);
        vm.stopPrank();
    }

    function testDepositMintInOneStep() public {
        uint256 amountToDeposit = 1 ether;
        uint256 amountDSCMint = uint256(ethUsdPriceFeed.getSimplePrice());
        vm.startPrank(user1);
        IERC20(weth).approve(address(dsPool), amountToDeposit);
        dsPool.depositCollateralAndMintDSC(weth, amountToDeposit, amountDSCMint);
        vm.stopPrank();

        uint256 dscBalance = dsc.balanceOf(user1);
        console.log("DSC Balance of User1: ", dscBalance);
        assert(dscBalance == amountDSCMint);
    }

    // test price drop and liquidation
    function testPriceDrop() public depositOneEth(user1) {
        uint256 initValue = dsPool._calculateUserTotalCollateralValue(user1);
        console.log("Total Collateral Value of User1 in USD: ", initValue);
        int256 currentETHPrice = ethUsdPriceFeed.getSimplePrice();
        console.log("Current ETH Price: ", currentETHPrice);
        currentETHPrice = currentETHPrice * 80 / 100;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(currentETHPrice);
        uint256 newValue = dsPool._calculateUserTotalCollateralValue(user1);
        console.log("Total Collateral Value of User1 in USD: ", newValue);
        assertApproxEqAbs(newValue, initValue * 80 / 100, 2);
    }


}