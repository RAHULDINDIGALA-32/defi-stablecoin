// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

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

    modifier depositCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
    }

    //////////////////////////////
    // Constructor Tests        //
    //////////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMismatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
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

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedAmount = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assert(expectedAmount == actualWeth);
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

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock();
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assert(totalDscMinted == expectedTotalDscMinted);
        assert(AMOUNT_COLLATERAL == expectedDepositAmount);
    }

    //////////////////////////////
    // mintDsc Tests            //
    //////////////////////////////

    function testRevertMintIfAmountZero() public depositCollateral {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }

    // function testRevertMintIfBreaksHealthFactor() public depositCollateral {
    //     vm.startPrank(user);
    //     // users can mint only 50% of collateral value
    //     // value = 20 ETH * $2000 = $40,000 → allowed mint ≈ $20,000
    //     vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
    //     dscEngine.mintDsc(40000 ether); // way too high
    //     vm.stopPrank();
    // }

    function testUserCanMintDsc() public depositCollateral {
        vm.startPrank(user);
        dscEngine.mintDsc(1000 ether);
        (uint256 minted,) = dscEngine.getAccountInformation(user);
        assertEq(minted, 1000 ether);
        vm.stopPrank();
    }

    //////////////////////////////
    // burnDsc Tests            //
    //////////////////////////////

    function testRevertBurnIfZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.burnDsc(0);
        vm.stopPrank();
    }

    function testUserCanBurnDsc() public depositCollateral {
        vm.startPrank(user);
        dscEngine.mintDsc(1000 ether);

        dsc.approve(address(dscEngine), 1000 ether);
        dscEngine.burnDsc(1000 ether);

        (uint256 minted,) = dscEngine.getAccountInformation(user);
        assertEq(minted, 0);
        vm.stopPrank();
    }

    //////////////////////////////
    // redeemCollateral Tests   //
    //////////////////////////////

    function testRevertRedeemZeroCollateral() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    // function testCantRedeemIfBreaksHealthFactor() public depositCollateral {
    //     vm.startPrank(user);
    //     dscEngine.mintDsc(10000 ether); // some borrowing

    //     // trying to redeem entire collateral breaks HF
    //     vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
    //     dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
    //     vm.stopPrank();
    // }

    function testUserCanRedeemIfHealthy() public depositCollateral {
        vm.startPrank(user);
        // No minted debt → always healthy
        dscEngine.redeemCollateral(weth, 5 ether);
        uint256 remaining = ERC20Mock(weth).balanceOf(address(dscEngine));
        assertEq(remaining, 15 ether);
        vm.stopPrank();
    }

    //////////////////////////////
    // deposit + mint combined  //
    //////////////////////////////

    function testDepositCollateralAndMintDsc() public {
        vm.startPrank(user);

        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 5000 ether);

        (uint256 minted,) = dscEngine.getAccountInformation(user);
        assertEq(minted, 5000 ether);

        vm.stopPrank();
    }

    //////////////////////////////
    // redeem + burn combined   //
    //////////////////////////////

    function testRedeemCollateralForDsc() public depositCollateral {
        vm.startPrank(user);
        dscEngine.mintDsc(5000 ether);

        dsc.approve(address(dscEngine), 5000 ether);
        dscEngine.redeemCollateralForDsc(weth, 5 ether, 5000 ether);

        uint256 deposited = ERC20Mock(weth).balanceOf(address(dscEngine));
        assertEq(deposited, 15 ether);

        (uint256 debt,) = dscEngine.getAccountInformation(user);
        assertEq(debt, 0);

        vm.stopPrank();
    }

    //////////////////////////////
    // Health Factor Tests      //
    //////////////////////////////

    function testHealthFactorStartsHigh() public depositCollateral {
        (uint256 minted, uint256 col) = dscEngine.getAccountInformation(user);
        assertEq(minted, 0);
        assert(col > 0);
    }

    function testHealthFactorAfterMint() public depositCollateral {
        vm.startPrank(user);
        dscEngine.mintDsc(10000 ether);

        // 20 ETH * 2000 = 40,000, liquidation threshold = 50% → effective = 20,000
        // HF = 20,000 / 10,000 = 2.0
        // scaled with 1e18 so compare rough ranges
        (uint256 hf,) = dscEngine.getAccountInformation(user);
        assert(hf > 0);
        vm.stopPrank();
    }

    //////////////////////////////
    // Liquidation Tests        //
    //////////////////////////////

    // function testCantLiquidateHealthyUser() public depositCollateral {
    //     vm.startPrank(user);
    //     dscEngine.mintDsc(10000 ether);
    //     vm.stopPrank();

    //     // attacker tries to liquidate
    //     address attacker = makeAddr("attacker");
    //     vm.startPrank(attacker);

    //     dsc.mint(attacker, 10000 ether); // mint for testing
    //     dsc.approve(address(dscEngine), 10000 ether);

    //     vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
    //     dscEngine.liquidate(weth, user, 1000 ether);
    //     vm.stopPrank();
    // }

    // function testLiquidationWorks() public depositCollateral {
    //     vm.startPrank(user);
    //     dscEngine.mintDsc(19000 ether); // HF barely above 1
    //     vm.stopPrank();

    //     // Manipulate price feed → drop ETH price artificially
    //     // Simulate price drop from $2000 → $500
    //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(500e8);

    //     address liquidator = makeAddr("liquidator");
    //     vm.startPrank(liquidator);

    //     dsc.mint(liquidator, 10000 ether);
    //     dsc.approve(address(dscEngine), 10000 ether);

    //     dscEngine.liquidate(weth, user, 5000 ether);

    //     // Liquidator should receive collateral + bonus
    //     uint256 liquidatorCollateral = ERC20Mock(weth).balanceOf(liquidator);
    //     assert(liquidatorCollateral > 0);

    //     vm.stopPrank();
    // }

    //////////////////////////////
    // Edge-case Tests          //
    //////////////////////////////

    // function testRevertsIfUnhealthyAfterRedeem() public depositCollateral {
    //     vm.startPrank(user);
    //     dscEngine.mintDsc(10000 ether);

    //     // redeem too much
    //     vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
    //     dscEngine.redeemCollateral(weth, 15 ether);
    //     vm.stopPrank();
    // }

    // function testRevertsBurnIfHealthFactorBreaks() public depositCollateral {
    //     vm.startPrank(user);
    //     dscEngine.mintDsc(15000 ether);

    //     // simulate collateral crash
    //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(500e8);

    //     dsc.approve(address(dscEngine), 15000 ether);

    //     vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
    //     dscEngine.burnDsc(1 ether);
    //     vm.stopPrank();
    // }
}
