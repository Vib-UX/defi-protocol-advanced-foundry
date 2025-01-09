// SPDX-License-Identifier: MIT

// Have our invariant aka properties

// What are our invariants?

/*

    The total value of DSC should be less than the total value of collateral

    Getter view functions should return the same value as the state variables

*/

pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;

    address public weth;
    address public wbtc;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        targetContract(address(engine)); // This is the contract we want to perform invariant checks on
    }

    function open_invariant_protocolMusthaveMoreValueThanTotalSupplyII() public view {
        uint256 totalValueOfDSC = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsc));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsc));
        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        assert(wethValue + wbtcValue >= totalValueOfDSC);
    }
}
