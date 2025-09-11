// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";


contract DSCoin is ERC20Burnable, Ownable {
    constructor() Ownable(msg.sender) ERC20("DecentralizedStakingCoin", "DSC") {}

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }
}
