// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DSCoin} from "./DSCoin.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DSPool is ReentrancyGuard {
    using OracleLib for address;
    ///////////////////
    // Errors
    ///////////////////

    error DSPool__TokenAddressesAndPriceFeedAddressesNeedToBeGreaterThanZero();
    error DSPool__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DSPool__NeedsMoreThanZero();
    error DSPool__TokenNotAllowed(address token);
    error DSPool__TokenTransferFailed();
    error DSPool__HealthFactorTooLow();
    error DSPool__BurnAmountExceedsBalance();
    error DSPool__UserNotLiquidatable();
    error DSPool__DebtToCoverExceedsCollateralValue();
    error DSPool__HealthFactorNotImproved();

    ///////////////////
    // Events
    ///////////////////
    event CollateralDeposited(address indexed user, address token, uint256 amount);
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);
    event DSCMinted(address indexed user, uint256 amount);
    event DSCBurned(address indexed user, uint256 amount);

    ///////////////////
    // State Variables
    ///////////////////
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant DSC_PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 1e18 = 1.0

    address[] private s_collateralTokens;
    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_DSCMinted;
    DSCoin private immutable i_dsc;

    ///////////////////
    // Constructor
    ///////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length == 0 || priceFeedAddresses.length == 0) {
            revert DSPool__TokenAddressesAndPriceFeedAddressesNeedToBeGreaterThanZero();
        }
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSPool__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }

        s_collateralTokens = tokenAddresses;
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        i_dsc = DSCoin(dscAddress);
    }

    ///////////////////
    // Modifiers
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSPool__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSPool__TokenNotAllowed(token);
        }
        _;
    }

    ///////////////////
    // Public Functions
    ///////////////////
    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToMint: The amount of DSC you want to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        nonReentrant
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        // Transfer in the collateral
        IERC20 tokenCollateral = IERC20(tokenCollateralAddress);
        bool success = tokenCollateral.transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSPool__TokenTransferFailed();
        }
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're withdrawing
     * @param amountCollateral: The amount of collateral you're withdrawing
     * @param amountDscToBurn: The amount of DSC you want to burn
     * @notice This function will withdraw your collateral and burn DSC in one transaction
     */
    function redeemCollateralAndBurnDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(amountCollateral)
    {
        _burnDSC(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have DSC minted, you will not be able to redeem until you burn your DSC
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(amountCollateral)
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintDSC(uint256 amountDscToMint) public moreThanZero(amountDscToMint) {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        i_dsc.mint(msg.sender, amountDscToMint);
    }

    function burnDSC(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) {
        _burnDSC(amountDscToBurn, msg.sender, msg.sender);
    }

    /* if user A need to liquidate, user A must already have sufficient DSC to cover the debt of user B
     * user A calls the liquidate function and specifies the collateral, user B, and the amount of debt to cover
     * user A will burn their DSC and receive the equivalent amount of collateral from user B, plus a bonus
     * user B's health factor must be below the minimum health factor
     * user A cannot liquidate more than the debt of user B
     * user A receives a liquidation bonus, which is a percentage of the collateral they receive
     * user B receives a liquidation penalty, which is a percentage of the collateral they lose
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external
        isAllowedToken(collateral)
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if(startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSPool__UserNotLiquidatable();
        }

        // liquidator can only cover as much debt as the user has
        uint256 totalDscMintedByUser = s_DSCMinted[user];
        if(debtToCover > totalDscMintedByUser) {
            debtToCover = totalDscMintedByUser;
        }

        // get equivalent amount of collateral needed to cover debt + bonus
        uint256 collateralEquivalent = _calculateCollateralAmountFromValue(collateral, debtToCover);
        uint256 bonusCollateral = (collateralEquivalent * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = collateralEquivalent + bonusCollateral;

        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDSC(debtToCover, user,msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        // In some scenarios, the user can be liquidated but their health factor does not improve, like if they have very little collateral, or the price of the collateral has dropped significantly
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSPool__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////
    // Private Functions
    ///////////////////
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) public
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        IERC20 tokenCollateral = IERC20(tokenCollateralAddress);
        bool success = tokenCollateral.transfer(to, amountCollateral);
        if (!success) {
            revert DSPool__TokenTransferFailed();
        }
    }

    function _burnDSC(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) public moreThanZero(amountDscToBurn) {
        if (i_dsc.balanceOf(dscFrom) < amountDscToBurn) {
            revert DSPool__BurnAmountExceedsBalance();
        }
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        i_dsc.burnFrom(dscFrom, amountDscToBurn);
    }

    function _calculateUserTotalCollateralValue(address user)
        public
        view
        returns (uint256 totalUserCollateralValueInDsc)
    {
        totalUserCollateralValueInDsc = 0;
        address[] memory collateralTokens = s_collateralTokens;
        // Loop through each collateral token
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount > 0) {
                // Get the price of the token
                address priceFeedAddress = s_priceFeeds[token];
                uint256 tokenDecimal = ERC20(token).decimals();
                (, int256 price,,,, uint8 priceFeedDecimal) = priceFeedAddress.getPrice();
                uint256 adjustedPrice = uint256(price);
                uint256 valueInUsd = (amount * adjustedPrice * (10 ** i_dsc.decimals())) / 10 ** (tokenDecimal + priceFeedDecimal);
                totalUserCollateralValueInDsc += valueInUsd;
            }
        }
    }

//    function _calculateCollateralValueFromToken(address token, uint256 amount)
//        private
//        view
//        returns (uint256)
//    {
//        address priceFeedAddress = s_priceFeeds[token];
//        (, int256 price,,,, uint8 decimal) = priceFeedAddress.getPrice();
//        uint256 adjustedPrice = uint256(price);
//        return (amount * adjustedPrice) / 10 ** decimal;
//    }

    function _calculateCollateralAmountFromValue(address token, uint256 valueInUsd)
        private
        view
        returns (uint256)
    {
        address priceFeedAddress = s_priceFeeds[token];
        (, int256 price,,,, uint8 decimal) = priceFeedAddress.getPrice();
        uint256 adjustedPrice = uint256(price);
        return (valueInUsd * 10 ** decimal) / adjustedPrice;
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = _calculateUserTotalCollateralValue(user);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        view
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        // collateralAdjustedForThreshold should be a percentage of the collateral value in USD, if LIQUIDATION_THRESHOLD is 50, it is 50%
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * DSC_PRECISION) / totalDscMinted;
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        if (_healthFactor(user) < MIN_HEALTH_FACTOR) {
            revert DSPool__HealthFactorTooLow();
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    // External & Public View & Pure Functions
    ////////////////////////////////////////////////////////////////////////////
    function getUserTotalCollateralValueInUSD(address user) external view returns (uint256) {
        return _calculateUserTotalCollateralValue(user) / (10 ** i_dsc.decimals());
    }

    function getUserCollateralDeposited(address user, address token)
        external
        view
        isAllowedToken(token)
        returns (uint256)
    {
        return s_collateralDeposited[user][token];
    }

    function getMaxDSCUserCanMint(address user) public view returns (uint256) {
        uint256 collateralValueInUsd = _calculateUserTotalCollateralValue(user);
        return (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function isLiquidatable(address user) public view returns (bool) {
        return _healthFactor(user) < MIN_HEALTH_FACTOR;
    }

    function getUserDebt(address user) external view returns (uint256) {
        if(isLiquidatable(user)){
            return s_DSCMinted[user];
        }else{
            return 0;
        }
    }

}
