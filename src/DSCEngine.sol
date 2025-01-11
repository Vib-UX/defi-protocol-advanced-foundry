// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Vibhav Sharma
 * @dev This contract implements the minting and burning of the stablecoin
 *
 * The system is designed to be as minimal as possible, and have the tokens maitain a 1 token = 1 USD peg at all time.
 * This is a stablecoin with properties:
 * - Exogenously Collateralized
 * - Algorithmic Stable
 * - Soft peg to USD
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH & WBTC.
 *
 * Our DSC system should alwalys be "overcollateralized". At no point, should the value of all
 * collateral be less than the value of all DSC tokens in circulation.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 *
 */
contract DSCEngine is ReentrancyGuard {
    ///////////
    // Types //
    ///////////

    using OracleLib for AggregatorV3Interface;

    ///////////////////
    //   Errors   //
    ///////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedLengthMismatch();
    error DSCEngine__TokenNotSupported();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /////////////////////
    // State Variables //
    /////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256) private s_DSCMinted;
    address[] private s_collateralTokens;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% Overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    DecentralizedStableCoin private immutable i_dsc;

    //////////////
    //  Events  //
    //////////////
    event CollateralDeposited(address user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    ///////////////////
    //   Modifiers   //
    ///////////////////

    /**
     * @notice Ensures that the input value is greater than zero
     * @param amount The amount to check
     */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine__TokenNotSupported();
        }
        _;
    }

    ///////////////////
    //   Functions   //
    ///////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedsAddress, address dscAddress) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedsAddress.length) {
            revert DSCEngine__TokenAddressAndPriceFeedLengthMismatch();
        }
        // For Example ETH/USD, BTC/USD, MKR/USd etc.
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedsAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////////////
    //   External Functions  //
    ///////////////////////////

    /**
     * @notice Deposits collateral and mints DSC (Decentralized Stable Coin) tokens.
     * @dev This function allows users to deposit a specified amount of collateral and mint DSC tokens in return.
     * @param tokenCollateral The address of the collateral token to be deposited.
     * @param amountCollateral The amount of collateral to be deposited.
     * @param amountDscToMint The amount of DSC tokens to be minted.
     */
    function depositCollaterAndMintDsc(address tokenCollateral, uint256 amountCollateral, uint256 amountDscToMint)
        external
    {
        depositCollateral(tokenCollateral, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice Deposits collateral into the contract
     * @dev This function allows users to deposit a specified amount of collateral
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice Redeems collateral and burns DSC (Decentralized Stable Coin) tokens.
     * @dev This function allows users to redeem a specified amount of collateral and burn DSC tokens in return.
     * @param tokenCollateral The address of the collateral token to be redeemed.
     * @param amountCollateral The amount of collateral to be redeemed.
     * @param amountDscToBurn The amount of DSC tokens to be burned.
     */
    function redeemCollateralForDsc(address tokenCollateral, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        redeemCollateral(tokenCollateral, amountCollateral);
        burnDsc(amountDscToBurn);
    }

    /**
     * @notice Redeems collateral from the contract
     * @dev This function allows users to redeem a specified amount of collateral
     * @param tokenCollateral The address of the collateral token
     * @param amountCollateral The amount of collateral to redeem
     */
    function redeemCollateral(address tokenCollateral, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateral, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Mints DSC (Decentralized Stable Coin) tokens to a specified address.
     * @dev This function allows the creation of new DSC tokens and assigns them to the recipient's address.
     *      Ensure that the caller has the necessary permissions to mint tokens..
     * @param amountDscToMint The number of DSC tokens to be minted.
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        //
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @notice Burns DSC (Decentralized Stable Coin) tokens from a specified address.
     * @dev This function allows the destruction of DSC tokens from the caller's address.
     * @param amountDscToBurn The number of DSC tokens to be burned.
     */
    function burnDsc(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) nonReentrant {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // This is not required but lets keep it for now
    }

    /**
     * @title Numeric Calculation Scenario for DSC Stablecoin Liquidation
     * @notice This documentation provides numeric examples of calculations involved in the liquidation process for the DSC stablecoin when collateral value falls below required levels.
     * @dev Demonstrates calculations using explicit numeric values to illustrate the threshold and liquidation process.
     */

    /**
     * @notice Calculate the total collateral pool value based on the current ETH market price.
     * @param currentEthPrice Example: 80 USD (the current market price of ETH in USD).
     * @param totalEth Example: 1000 ETH (the total amount of ETH deposited as collateral).
     * @return Example: 80,000 USD (calculated as 1000 ETH * 80 USD/ETH).
     * @dev Example Calculation: totalCollateralValue = 1000 ETH * 80 USD/ETH = 80,000 USD
     *      This value is critical for determining if the system is undercollateralized.
     */

    /**
     * @notice Determine if the collateral pool is below the liquidation threshold.
     * @param currentCollateralValue Example: 80,000 USD (the current USD value of the ETH collateral).
     * @param liquidationThreshold Example: 1.5 (the threshold multiplier, typically 150% of DSC issued).
     * @param totalDscIssued Example: 100,000 USD (the total amount of DSC that needs collateral backing).
     * @return Example: true (returns true if the collateral is below the threshold, otherwise false).
     * @dev Example Calculation: requiredCollateral = 100,000 USD * 1.5 = 150,000 USD
     *      Check if 80,000 USD < 150,000 USD to determine if liquidation is triggered.
     */

    /**
     * @notice Calculate the excess or shortfall after liquidating ETH to cover the DSC debt.
     * @param proceedsFromEthSale Example: 40,000 USD (the amount obtained from liquidating ETH collateral).
     * @param dscDebt Example: 50,000 USD (the amount of DSC needing to be covered or redeemed in USD).
     * @return Example: -10,000 USD (the shortfall, calculated as proceeds from sale minus DSC debt).
     * @dev Example Calculation: excessOrShortfall = 40,000 USD - 50,000 USD = -10,000 USD
     *      This figure shows the shortfall that needs to be addressed following liquidation.
     */

    /**
     * @notice Apply any penalties or fees on the proceeds from liquidation.
     *  totalProceeds Example: 40,000 USD (the total amount obtained from the liquidation of ETH).
     *  penaltyRate Example: 0.05 (5% penalty on the liquidation proceeds).
     *  Example: 38,000 USD (the net proceeds after deducting a 5% penalty).
     * @dev Example Calculation: netProceeds = 40,000 USD - (40,000 USD * 0.05) = 38,000 USD
     *      The penalties are deducted to cover administrative costs or as deterrent against risky practices.
     */

    /**
     * @param collateral: The ERC20 token address of the collateral you are using to make the protocol solvent again.
     * This is collateral that you are going to take from the user who is insolvent
     * In return, you have to burn your DSC to pay off their debt, but you dont pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the users debt
     *
     * You can partially liquidate a user
     * You will get 10% LIQUIDATION_BONUS for taking the users funds.
     * This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * A known bug would be if the protocol was only 100% collaterallized, we wouldnt be able to liquidate anyone.
     * For Example, if the price of the collateral plumeted before anyone could be liquidated
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingHealthFactorOfUser = _healthFactor(user);
        if (startingHealthFactorOfUser < MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        /*
        * burn the `DSC` debt being covered by the `liquidator` (not all of a position needs to be liquidated)
        * calculate how much of the passes collateral type equates to the USD value of the debt being covered
        * transfer the calculated amount of the passed collateral type to the `liquidator`
        * updated internal accounting/balances
        */

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralRedeemed = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralRedeemed);
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingHealthFactorOfUser) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //////////////////////////////////////////
    //   Private & Internal View Functions  //
    //////////////////////////////////////////

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDsc(uint256 amountToDscBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountToDscBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountToDscBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountToDscBurn);
    }

    /**
     * @notice Checks if the health factor of a user is below the required threshold and reverts if it is.
     * @dev Health Factor is a concept borrowed from the Aave protocol. It represents the safety of the user's collateral against their borrowed assets.
     *      A health factor below 1 indicates that the user's collateral is at risk of being liquidated.
     * @param user The address of the user whose health factor is being checked.
     *
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthfactor = _healthFactor(user);
        if (userHealthfactor < MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthfactor);
        }
    }

    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can be liquidated.
     */
    function _healthFactor(address user) private view returns (uint256) {
        /**
         * Suppose we have the following values:
         * totalDscMinted = 1000 DSC (representing 1000 DSC tokens)
         * collateralValueInUsd = 2000 USD (representing $2000 worth of collateral)
         *
         * LIQUIDATION_THRESHOLD = 50 (representing 50% or 0.5 when divided by LIQUIDATION_PRECISION)
         * LIQUIDATION_PRECISION = 100
         * PRECISION = 1e18 (used for scaling)
         *
         * Calculation:
         * collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION
         *                                = (2000 * 50) / 100
         *                                = 1000 USD
         *
         * healthFactor = (collateralAdjustedForThreshold * PRECISION) / totalDscMinted
         *              = (1000 * 1e18) / 1000
         *              = 1e18 (which represents a health factor of 1.0)
         */
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        private
        pure
        returns (uint256 healthFactor)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    //////////////////////////////////////////
    //   Public & External View Functions   //
    //////////////////////////////////////////

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValue) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            uint256 usdValue = getUsdValue(token, amount);
            totalCollateralValue += usdValue;
        }
        return totalCollateralValue;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        /**
         * The following performs a mathematical operation that is crucial for the correct functioning of the contract.
         *
         * Suppose we have a variable `price` with a value of 2000 (representing $2000 with 8 decimal places from Chainlink)
         * and a variable `amount` with a value of 1e18 (representing 1 token with 18 decimal places).
         *
         * The operation `(uint256(price * 1e10) * amount) / 1e18` would yield the USD value of the token amount.
         *
         * Example Calculation:
         * price = 2000 * 1e8 (Chainlink price feed with 8 decimals)
         * amount = 1e18 (1 token with 18 decimals)
         *
         * USD value = (2000 * 1e8 * 1e10) / 1e18
         *           = 2000 * 1e18 / 1e18
         *           = 2000 USD
         *
         * This line ensures that the division is handled correctly within the constraints of Solidity's integer arithmetic.
         * It is important to understand this behavior to avoid unexpected results in calculations.
         */
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /**
     * @notice Calculates the amount of tokens equivalent to a given USD amount.
     * @dev Uses Chainlink Aggregator v3 to get the latest price of the token in USD.
     * @param token The address of the token collateral.
     * @param usdAmountInWei The amount of USD in wei.
     * @return The amount of tokens equivalent to the given USD amount.
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInformation(address user) external view returns (uint256, uint256) {
        return _getAccountInformation(user);
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MINIMUM_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
}
