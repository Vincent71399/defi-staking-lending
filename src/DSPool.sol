// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DSCoin } from "./DSCoin.sol";
import { OracleLib } from "./libraries/OracleLib.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


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

    ///////////////////
    // Events
    ///////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);
    event DSCMinted(address indexed user, uint256 indexed amount);
    event DSCBurned(address indexed user, uint256 indexed amount);

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
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress){
        if(tokenAddresses.length == 0 || priceFeedAddresses.length == 0){
            revert DSPool__TokenAddressesAndPriceFeedAddressesNeedToBeGreaterThanZero();
        }
        if(tokenAddresses.length != priceFeedAddresses.length){
            revert DSPool__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }

        s_collateralTokens = tokenAddresses;
        for(uint i = 0; i < tokenAddresses.length; i++){
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
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public
        nonReentrant
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        // Transfer in the collateral
        IERC20 tokenCollateral = IERC20(tokenCollateralAddress);
        bool success = tokenCollateral.transferFrom(msg.sender, address(this), amountCollateral);
        if(!success){
            revert DSPool__TokenTransferFailed();
        }
    }

    function redeemCollateralAndBurnDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public nonReentrant isAllowedToken(tokenCollateralAddress) moreThanZero(amountCollateral) {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        _revertIfHealthFactorIsBroken(msg.sender);
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);
        IERC20 tokenCollateral = IERC20(tokenCollateralAddress);
        bool success = tokenCollateral.transfer(msg.sender, amountCollateral);
        if(!success){
            revert DSPool__TokenTransferFailed();
        }
    }

    function mintDSC(uint256 amountDscToMint) public moreThanZero(amountDscToMint) {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        i_dsc.mint(msg.sender, amountDscToMint);
    }

    function burnDSC(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) {
        if(i_dsc.balanceOf(msg.sender) < amountDscToBurn){
            revert DSPool__BurnAmountExceedsBalance();
        }
        s_DSCMinted[msg.sender] -= amountDscToBurn;
        i_dsc.burnFrom(msg.sender, amountDscToBurn);
    }



    ///////////////////
    // Private Functions
    ///////////////////
    function _calculateUserTotalCollateralValue(address user) public view returns(uint256 totalUserCollateralValueInUsd){
        totalUserCollateralValueInUsd = 0;
        address[] memory collateralTokens = s_collateralTokens;
        // Loop through each collateral token
        for(uint i = 0; i < collateralTokens.length; i++){
            address token = collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            if(amount > 0){
                // Get the price of the token
                address priceFeedAddress = s_priceFeeds[token];
                (, int256 price,,,,uint8 decimal) = priceFeedAddress.getPrice();
                uint256 adjustedPrice = uint256(price);
                uint256 valueInUsd = (amount * adjustedPrice) / 10 ** decimal;
                totalUserCollateralValueInUsd += valueInUsd;
            }
        }
    }

    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = _calculateUserTotalCollateralValue(user);
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    )
        internal
        pure
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
        if(_healthFactor(user) < MIN_HEALTH_FACTOR){
            revert DSPool__HealthFactorTooLow();
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    // External & Public View & Pure Functions
    ////////////////////////////////////////////////////////////////////////////
    function getUserTotalCollateralValueInUSD(address user) external view returns (uint256) {
        return _calculateUserTotalCollateralValue(user);
    }

    function getUserCollateralDeposited(address user, address token) external isAllowedToken(token) view returns (uint256) {
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

    function getUserDebt(address user) public view returns (uint256) {
        if(isLiquidatable(user)){
            return s_DSCMinted[user] - getMaxDSCUserCanMint(user);
        }else{
            return 0;
        }
    }
}
