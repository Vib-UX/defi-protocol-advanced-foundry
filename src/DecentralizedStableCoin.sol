// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author Vibhav Sharma
 * @dev This contract implements a decentralized stablecoin
 *
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Soft peg to USD
 *
 * This is the contract meant to be governed by DSCEngine. This contract is just the ERC20 implementation
 * of the stablecoin. The minting and burning of the stablecoin is done by the DSCEngine contract.
 *
 * @notice This contract is part of the DeFi protocol advanced foundry project.
 *
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeGreaterThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance(uint256 balance, uint256 amount);
    error DecentralizedStableCoin__NotZeroAddress(address _address);

    constructor() ERC20("DecentalizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance(balance, _amount);
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress(_to);
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeGreaterThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
