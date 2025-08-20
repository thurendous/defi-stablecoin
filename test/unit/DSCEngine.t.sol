// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";


contract DSCEngineTest is Test {
    DeployDSC public deployer;
    DSCEngine public dsce;
    HelperConfig public config;
    DecentralizedStableCoin public dsc;
    address weth;
    address wbtc;
    address ethUsdPriceFeed;
    address wbtcUsdPriceFeed;

    address public USER = makeAddr("user");

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 15 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        // activeNetworkConfig returns: (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey)
        (ethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, ) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /////////////////////////
    ////// Price tests //////
    /////////////////////////
    function testGetUsdValue() public view {
        // Arrange
        uint256 wethAmount = 15e18; // 15 ETH

        // Act
        // 15e18 * 2000 usd/ETH = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, wethAmount);
        assertEq(expectedUsd, actualUsd);
    }


    /////////////////////////////////////
    ////// DepositCollateral tests //////
    /////////////////////////////////////

    function testRevertIfCollateralIsZero() public {
        // Arrange
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();

    }

}
