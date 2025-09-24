// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {DSCoin} from "../src/DSCoin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DSCoinTest is Test {
    DSCoin internal dsc;
    address internal owner = makeAddr("owner");
    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");

    function setUp() public {
        vm.startPrank(owner);
        dsc = new DSCoin();
        vm.stopPrank();
    }

    function testMint() public {
        uint256 amount = 1000 ether;
        vm.startPrank(owner);
        dsc.mint(user1, amount);
        vm.stopPrank();
        uint256 user1Balance = dsc.balanceOf(user1);
        console.log("User1 Balance: ", user1Balance);
        assertEq(user1Balance, amount);
    }

    function testMintByNonOwnerFail(address user) public {
        vm.assume(user != owner);
        uint256 amount = 1000 ether;
        vm.startPrank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        dsc.mint(user, amount); // This should fail
        vm.stopPrank();
    }

    function testBurn() public {
        uint256 amount = 1000 ether;
        vm.startPrank(owner);
        dsc.mint(user1, amount);
        vm.stopPrank();

        vm.startPrank(user1);
        dsc.burn(500 ether);
        vm.stopPrank();

        uint256 user1Balance = dsc.balanceOf(user1);
        console.log("User1 Balance after burn: ", user1Balance);
        assertEq(user1Balance, 500 ether);
    }
    
}
