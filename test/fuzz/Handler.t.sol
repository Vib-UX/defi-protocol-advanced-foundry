// Handler is going to narrow down the fuzzing scope to function calls

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    address[] public userDepositedCollateral;
    MockV3Aggregator public ethUsdPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        engine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        // Mint & Approve engine to spend
        vm.startPrank(msg.sender);
        ERC20Mock(collateral).mint(msg.sender, amountCollateral);
        ERC20Mock(collateral).approve(address(engine), amountCollateral);

        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        userDepositedCollateral.push(msg.sender);
    }

    function mintDsc(uint256 amount, uint256 seedUser) public {
        if (userDepositedCollateral.length == 0) {
            return;
        }
        address sender = userDepositedCollateral[seedUser % userDepositedCollateral.length];
        // We would only want users to mint dsc based on the collateral they have provided
        (uint256 totalDscMinted, uint256 totalCollateralInUsd) = engine.getAccountInformation(sender);
        int256 maxDscToMint = (int256(totalCollateralInUsd) / 2) - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount <= 0) {
            return;
        }

        vm.startPrank(sender);
        engine.mintDsc(amount);
        vm.stopPrank();
    }

    // THIS BREAKS OUR INVARIANT TEST SUITE!!!
    function updatePriceFeed(uint96 updatedPrice) public {
        int256 newPrice = int256(uint256(updatedPrice));
        ethUsdPriceFeed.updateAnswer(newPrice);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        vm.startPrank(msg.sender);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        engine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // Helper functions
    function _getCollateralFromSeed(uint256 seed) private view returns (ERC20Mock) {
        if (seed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
