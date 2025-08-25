// Handler test is going to narrow down the fuzzing condition spaces.

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Test, console } from "forge-std/Test.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";

contract HandlerTest is Test {
    ERC20Mock public weth;
    ERC20Mock public wbtc;
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function setUp() external {
        // don't call redeem collateral unless there is collateral to redeem
    }

    function testFuzz_RevertIfTokenIsNotAllowed(address token) public {
        // Arrange
        // Act
        // Assert
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        vm.startPrank(sender);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        if (maxDscToMint <= 0) {
            return;
        }
        amount = bound(amount, 1, uint256(maxDscToMint));
        dsce.mintDsc(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function depositCollateral(uint256 collateralAmount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralAmount);
        uint256 amountCollateral = bound(collateralAmount, 1, MAX_DEPOSIT_SIZE);
        collateral.mint(msg.sender, amountCollateral);
        vm.startPrank(msg.sender);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // double push
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(msg.sender, address(collateral));
        uint256 amountToRedeem = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountToRedeem == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        dsce.redeemCollateral(address(collateral), amountToRedeem); // TODO: add health factor check
        vm.stopPrank();
    }

    function _getCollateralFromSeed(uint256 collateralSeed) public view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
