// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;
    address wbtc;
    uint256 public constant AMOUNT_COLLATERAL = 20 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 20 ether;
    address public user = makeAddr("user");

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
    }

    //////////////////////////////
    // Price Tests              //
    //////////////////////////////
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000 ETH = 30,000e18
        uint256 expectedAmount = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        assert(expectedAmount == actualUsd);
    }

    //////////////////////////////
    // depositCollateral Tests  //
    //////////////////////////////
    function testRevertIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}
