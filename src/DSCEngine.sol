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

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
 *
 */
contract DSCEngine is ReentrancyGuard {
    /////////////////////////////
    ////// Errors & Events //////
    /////////////////////////////
    error DSCEngine__TokenAddressesAndPriceFeedsLengthsMustBeTheSame();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__NotEnoughCollateral();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__CollateralValueMustBeGreaterThanZero();
    error DSCEngine__HealthFactorIsBroken();
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();


    event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);

    //////////////////////////////
    ////// State Variables ///////
    //////////////////////////////
    // immutable variables are set in the constructor and cannot be changed
    DecentralizedStableCoin private immutable I_DSC;

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // this means you need to be 200% collateralized to get a loan
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; // this is for adding the price feed in order to make it 1e18
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidators

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address token => bool isAllowed) private s_allowedTokens;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_DSCMinted;

    address[] private s_collateralTokens;

    // events
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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
            revert DSCEngine__TokenNotAllowed(tokenAddress);
        }
        _;
    }

    ////////////////////////
    ////// Constructor /////
    ////////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeeds, address dscTokenAddress) {
        if (tokenAddresses.length != priceFeeds.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedsLengthsMustBeTheSame();
        }

        I_DSC = DecentralizedStableCoin(dscTokenAddress);

        // ETH/USD, BTC/USD, etc
        for (uint256 i = 0; i < tokenAddresses.length; ++i) {
            s_allowedTokens[tokenAddresses[i]] = true;
            s_priceFeeds[tokenAddresses[i]] = priceFeeds[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
    }

    ///////////////////////////////
    ////// External Functions /////
    ///////////////////////////////
    /// @notice Deposit Collateral and Mint DSC in one transaction
    /// @param tokenCollateralAddress The address of the token being deposited
    /// @param amountCollateral The amount of the token being deposited
    /// @param amountDscToMint The amount of DSC to mint
    /// @dev The amount of collateral deposited should be greater than 0
    /// @dev The amount of DSC to mint should be greater than 0. The health factor should be ok. Or not, it will revert.
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external moreThanZero(amountCollateral) moreThanZero(amountDscToMint) {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /// @notice Deposit Collateral for DSC
    /// @param tokenCollateralAddress The address of the token being deposited
    /// @param amountCollateral The amount of the token being deposited
    /// @dev The amount of collateral deposited should be greater than 0
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(amountCollateral)
        nonReentrant
    {
        // 1. Get the amount of collateral they deposited
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        // emit the event when updating the state variable
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert DSCEngine__TransferFailed();
    }

    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        public
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already checks health factor
    }

    /// in order to redeem collateral:
    // 1. health factor must be over 1 AFTER collateral is pulled
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
    {
        _redeemCollateral(msg.sender, msg.sender,tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @notice Mint DSC by depositing collateral
    /// @notice follows CEI rules
    /// @param amountDscToMint The amount of DSC to mint
    /// @dev The amount of DSC to mint should be greater than 0
    /// @notice they must have more collateral than the minimum threshold
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = I_DSC.mint(msg.sender, amountDscToMint);
        if (!minted) revert DSCEngine__MintFailed();

        // 1. Get the amount of collateral they deposited
        // 2. Convert the collateral to USD
        // 3. Get the amount of DSC they want to mint
        // 4. Check if the health factor is ok
        // 5. If the health factor is ok, mint the DSC
        // 6. Add the DSC to their balance
    }

    function burnDsc(uint256 amountDscToBurn) public {
        s_DSCMinted[msg.sender] -= amountDscToBurn;
        bool success = I_DSC.transferFrom(msg.sender, address(this), amountDscToBurn);
        if (!success) revert DSCEngine__TransferFailed();
        I_DSC.burn(amountDscToBurn);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...However, we put it here for safety
    }

    // #100 ETH backing $50 DSC
    // $20 ETH back $50 DSC <- DSC isn't worth $1!!!
    // if someone is not 200% collateralized, we will pay you to liquidate them

    // $75 backing $50 DSC
    // liquidator take $75 backing and burns off the $50 DSC
    /// @param collateral the erc20 collateral address to liquidate from the user
    /// @param user the user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
    /// @param debtToCover the amount of DSC to burn to improve the health factor of the user
    /// @notice You can partially liquidate a user. 
    /// @notice You will get a liquidation bonus for taking the users funds
    /// @notice A known bug would be if the protocol is 100% or less collateralized, then we wouldn't be able to incentivize the liquidators.
    /// Follows CEI: Checks, Effects, Interactions
    function liquidate(address collateral, address user, uint256 debtToCover) public moreThanZero(debtToCover) { 
        // check the health
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // We want to burn their DSC "debt"
        // And take their collateral
        // Bad User: $140 ETH, $100 DSC
        // debtToCover = $100
        // $100 of DSC == ??? ETH?
        // 0.05 ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // And give them a 10$ bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep the extra amounts into a treasury

        // 0.05 * 0.1 = 0.005 getting 0.055 ETH
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        // We need to burn the DSC debt
        burnDsc(debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor >= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(user);
    }

    function getHealthFactor() external view returns (uint256) { }

    ///////////////////////////////////////////////
    ////// Private & Internal View Functions //////
    ///////////////////////////////////////////////

    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        totalCollateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    /// @notice Return how close to liquidation a user is. If a user is below 1, he can get liquidated.
    /// @param user The address of the user to check the health factor of
    /// @return The health factor of the user. If a user goes below 1, then they can get liquidated.
    function _healthFactor(address user) internal view returns (uint256) {
        // total DSC minted
        // total collateral value
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = getAccountInformation(user);
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold =
            (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken();
        }
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral) internal {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) revert DSCEngine__TransferFailed();
    }

    ///////////////////////////////////////////////
    ////// Public & External View Functions //////
    //////////////////////////////////////////////
    function getAccountCollateralValueInUsd(address user) public view returns (uint256) {
        uint256 totalCollateralValueInUsd;
        for (uint256 i; i < s_collateralTokens.length; ++i) {
            address token = s_collateralTokens[i];
            uint256 tokenAmount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, tokenAmount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 2500 * 1e18 * 1e10 / 1e18
        return (uint256(price) * amount * ADDITIONAL_FEED_PRECISION) / PRECISION;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        // price of ETH (token)
        // $/ETH ETH??
        // $2000 / ETH. $1000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address tokenCollateralAddress) external view returns (uint256) {
        return s_collateralDeposited[user][tokenCollateralAddress];
    }
}
