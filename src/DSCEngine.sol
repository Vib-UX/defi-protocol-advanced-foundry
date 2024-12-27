// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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

* Our DSC system should alwalys be "overcollateralized". At no point, should the value of all 
* collateral be less than the value of all DSC tokens in circulation.
*
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
*
*/
contract DSCEngine {
    ///////////////////
    //   Functions   //
    ///////////////////

    ///////////////////////////
    //   External Functions  //
    ///////////////////////////
    function depositCollaterAndMintDsc() external {}

    function depositCollateral() external {}

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    function burnDsc() external {}

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

    function liquidate() external {}

    function getHealthFactor() external view {}
}
