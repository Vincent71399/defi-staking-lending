// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OracleLib } from "./libraries/OracleLib.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract DSPool {
    ///////////////////
    // Errors
    ///////////////////
    error DSPool__TokenAddressesAndPriceFeedAddressesNeedToBeGreaterThanZero();
    error DSPool__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();

    ///////////////////
    // State Variables
    ///////////////////
    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    IERC20 private immutable i_dsc;


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

        for(uint i = 0; i < tokenAddresses.length; i++){
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        i_dsc = IERC20(dscAddress);
    }

    ///////////////////
    // Functions
    ///////////////////
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public {

    }


}
