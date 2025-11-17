// SPDX-License-Identifier: SEE LICENSE IN LICENSE

/*
1. what are our Invariants ?
     a. The total supply of DSC should be less than the total value of collateral
     b. Getter view functions should never revert (evergreen invariant)
*/

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        targetContract(address(dscEngine));
    }

    function invariant_protocolMusthaveMoreValueThanTheTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposit = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposit = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposit);
        uint256 wbtcValue = dscEngine.getUsdValue(weth, totalWbtcDeposit);

        console.log("weth value:", wethValue);
        console.log("wbtcvalue:", wbtcValue);
        console.log("total Supply:", totalSupply);
        assert((wethValue + wbtcValue) >= totalSupply);
    }
}

