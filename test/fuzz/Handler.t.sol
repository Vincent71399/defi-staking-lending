// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {DSCoin} from "../../src/DSCoin.sol";
import {DSPool} from "../../src/DSPool.sol";
import {MockToken} from "../mocks/MockToken.sol";

contract Handler is Test {
    DSPool public dsPool;
    DSCoin public dsc;

    uint256 public immutable TOKEN_LENGTH;
    address[] public tokens;

    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSPool _dsPool, DSCoin _dsc) {
        dsPool = _dsPool;
        dsc = _dsc;

        tokens = dsPool.getCollateralTokens();
        TOKEN_LENGTH = tokens.length;
    }

    // FUNCTIONS TO INTERACT WITH

    ////////////
    // DSPool //
    ////////////
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        MockToken collateral = _getCollateralFromSeed(collateralSeed);
        collateral.mint(address(this), amountCollateral);
        collateral.approve(address(dsPool), amountCollateral);
        dsPool.depositCollateral(address(collateral), amountCollateral);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        MockToken collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxRedeemable = dsPool.getMaxRedeemableCollateral(address(this), address(collateral));
        vm.assume(maxRedeemable > 0);
        amountCollateral = bound(amountCollateral, 1, maxRedeemable);
        dsPool.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDSC(uint256 amountDsc) public {
        uint256 maxDSC = dsPool.getMaxDSCUserCanMint(address(this));
        uint256 mintedDSC = dsc.balanceOf(address(this));
        vm.assume(maxDSC > mintedDSC);
        amountDsc = bound(amountDsc, 1, maxDSC - mintedDSC);
        dsPool.mintDSC(amountDsc);
    }

    function burnDSC(uint256 amountDsc) public {
        uint256 mintedDSC = dsc.balanceOf(address(this));
        vm.assume(mintedDSC > 0);
        amountDsc = bound(amountDsc, 1, mintedDSC);
        dsc.approve(address(dsPool), amountDsc);
        dsPool.burnDSC(amountDsc);
    }

    function liquidate(uint256 collateralSeed, address userToBeLiquidated, uint256 debtToCover) public {
        vm.assume(dsPool.isLiquidatable(userToBeLiquidated) == true);
        debtToCover = bound(debtToCover, 1, MAX_DEPOSIT_SIZE);
        MockToken collateral = _getCollateralFromSeed(collateralSeed);
        dsc.approve(address(dsPool), debtToCover);
        dsPool.liquidate(address(collateral), userToBeLiquidated, debtToCover);
    }

    /////////////////////////////
    // DecentralizedStableCoin //
    /////////////////////////////

    /////////////////////////////
    // Aggregator //
    /////////////////////////////

    /// Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (MockToken) {
        uint256 tokenIndex = collateralSeed % TOKEN_LENGTH;
        return MockToken(tokens[tokenIndex]);
    }
}
