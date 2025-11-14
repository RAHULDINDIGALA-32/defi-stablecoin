// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Decentralized Stable Coin
 * @author Rahul Dindigala
 * @notice A decentralized stable coin backed by crypto assets.
 * Relative Stability: Pegged to USD
 * Minting: Algorithmic
 * Collateral: Exogenous (ETH and BTC)
 *
 * @dev This is the contract meant to be governed by DSCEngine. This Contract is just the ERC20 implementation of our stablecoin system.
 */

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    /* Errors */
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__InvalidReceiver(address receiver);

    /* Functions */
    constructor() ERC20("Decentralized Stable Coin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__InvalidReceiver(_to);
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
