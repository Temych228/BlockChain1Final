// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EURToken
 * @dev Test ERC20 token representing Euro token (mintable by owner).
 */
contract EURToken is ERC20, Ownable {
    constructor(uint256 _initialSupply)
        ERC20("Euro Token", "EURT")
        Ownable(msg.sender)
    {
        _mint(msg.sender, _initialSupply * 10 ** decimals());
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
