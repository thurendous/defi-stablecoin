// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";

/**
 * @title DSCEngine
 * @author @0x0000000000000000000000000000000000000000
 * Collateral: Exogenous
 * Minting (Stability Mechanism): Decentralized (Algorithmic)
 * Value (Relative Stability): Anchored (Pegged to USD)
 * Collateral Type: Crypto
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * This stablecoin has properties: 
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 * 
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC. 
 * 
 * Our system should be always overcollateralized, meaning at no point should the value of the collateral be less than the value of the DSC minted.
 * 
 * 
 * @notice This contract is the core of the DSC System. It handles all the logic for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 **/
contract DSCEngine is ReentrancyGuard {
    /////////////////////////////
    ////// Errors & Events //////
    /////////////////////////////
    error DSCEngine__TokenAddressesAndPriceFeedsLengthsMustBeTheSame();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__NotEnoughCollateral();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TransferFailed();
    error DSCEngine__CollateralValueMustBeGreaterThanZero();

    // events
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);


    //////////////////////////////
    ////// State Variables ///////
    //////////////////////////////

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address token => bool isAllowed) private s_allowedTokens;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    // immutable variables are set in the constructor and cannot be changed
    address private immutable i_dsc;


    ////////////////////////
    ////// Modifiers ///////
    ////////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_allowedTokens[tokenAddress] == false) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    ////////////////////////
    ////// Constructor /////
    ////////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeeds, address dscTokenAddress) {
        if (tokenAddresses.length != priceFeeds.length) revert DSCEngine__TokenAddressesAndPriceFeedsLengthsMustBeTheSame();

        i_dsc = dscTokenAddress;
        // ETH/USD, BTC/USD, etc
        for (uint256 i = 0; i < tokenAddresses.length; ++i) {
            s_allowedTokens[tokenAddresses[i]] = true;
            s_priceFeeds[tokenAddresses[i]] = priceFeeds[i];
        }
    }
    
    ///////////////////////////////
    ////// External Functions /////
    ///////////////////////////////
    /// @notice Deposit Collateral for DSC
    /// @param tokenCollateralAddress The address of the token being deposited
    /// @param amountCollateral The amount of the token being deposited
    /// @dev The amount of collateral deposited should be greater than 0
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external isAllowedToken(tokenCollateralAddress) moreThanZero(amountCollateral) nonReentrant {
        // 1. Get the amount of collateral they deposited
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        // emit the event when updating the state variable
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert DSCEngine__TransferFailed();
    }
    
    function depositCollateralAndMintDSC() public {}

    function redeemCollateralForDSC() public {}

    function redeemCollateral() public {}

    /// @notice Mint DSC by depositing collateral
    /// @notice follows CEI rules
    /// @param amountDscToMint The amount of DSC to mint
    /// @dev The amount of DSC to mint should be greater than 0
    /// @notice they must have more collateral than the minimum threshold
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        // 1. Get the amount of collateral they deposited
        // 2. Convert the collateral to USD
        // 3. Get the amount of DSC they want to mint
        // 4. Check if the health factor is ok
        // 5. If the health factor is ok, mint the DSC
        // 6. Add the DSC to their balance
    }

    function burnDsc() public {}

    function liquidate() public {}

    function getHealthFactor() external view returns (uint256) {}
}
