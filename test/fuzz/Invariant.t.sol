// what are the invariants of the contract?

// 1. Total Supply Invariant: The total supply of DSCoin should always be less than the total value of collateral locked in the system.

// 2. Getter functions should not revert: All public and external view functions should not revert under any circumstances.

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DSCoin} from "../../src/DSCoin.sol";
import {DSPool} from "../../src/DSPool.sol";
import {DeployDSPool} from "../../script/DeployDSPool.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    using OracleLib for address;

    DSPool internal dsPool;
    DSCoin internal dsc;
    HelperConfig internal helperConfig;

    Handler internal handler;

    function setUp() public {
        DeployDSPool deployDSPool = new DeployDSPool();
        (dsPool, dsc, helperConfig) = deployDSPool.run();

        handler = new Handler(dsPool, dsc);

        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupplyDollars() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalCollateralValueInDsc = 0;
        for (uint256 i = 0; i < helperConfig.getTokens().length; i++) {
            address token = helperConfig.getTokens()[i];
            uint256 balance = IERC20(token).balanceOf(address(dsPool));
            totalCollateralValueInDsc += dsPool.getCollateralValueInDscFromAmount(token, balance);
        }
        assertGe(totalCollateralValueInDsc, totalSupply);
    }
}
