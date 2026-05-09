// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import {EulerBadDebtTrap, CollectOutput, MarketSnapshot} from "../src/EulerBadDebtTrap.sol";

contract EulerBadDebtTrapTest is Test {
    EulerBadDebtTrap trap;

    function setUp() public {
        trap = new EulerBadDebtTrap();
    }

    function _healthyMarket() internal pure returns (MarketSnapshot memory) {
        return MarketSnapshot({totalAssets: 1000 ether, totalLiabilities: 900 ether});
    }

    function _makeOutput(MarketSnapshot memory dai) internal pure returns (CollectOutput memory) {
        return CollectOutput({
            dai: dai,
            usdc: _healthyMarket(),
            wbtc: _healthyMarket(),
            steth: _healthyMarket()
        });
    }

    // Test 1: Normal healthy protocol state — trap should NOT fire
    function test_HealthyProtocol() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(_makeOutput(_healthyMarket()));
        (bool respond, ) = trap.shouldRespond(data);
        assertFalse(respond, "Trap should NOT fire when protocol is healthy");
    }

    // Test 2: Euler-style bad debt forming — trap SHOULD fire
    function test_EulerStyleBadDebt() public {
        MarketSnapshot memory exploited = MarketSnapshot({
            totalAssets: 800 ether,
            totalLiabilities: 1000 ether
        });
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(_makeOutput(exploited));
        (bool respond, ) = trap.shouldRespond(data);
        assertTrue(respond, "Trap SHOULD fire when bad debt is forming");
    }

    // Test 3: Small divergence below threshold — trap should NOT fire
    function test_SmallDivergenceBelowThreshold() public {
        MarketSnapshot memory minor = MarketSnapshot({
            totalAssets: 1000 ether,
            totalLiabilities: 1020 ether
        });
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(_makeOutput(minor));
        (bool respond, ) = trap.shouldRespond(data);
        assertFalse(respond, "Trap should NOT fire for minor divergence");
    }

    // Test 4: Zero assets with positive liabilities — MOST severe bad debt
    function test_ZeroAssetsPositiveLiabilities_ShouldFire() public {
        MarketSnapshot memory bad = MarketSnapshot({
            totalAssets: 0,
            totalLiabilities: 1000 ether
        });
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(_makeOutput(bad));
        (bool respond, ) = trap.shouldRespond(data);
        assertTrue(respond, "Trap SHOULD fire when assets are zero but liabilities exist");
    }

    // Test 5: Exactly 5% divergence — trap SHOULD fire
    function test_ExactlyAtThreshold_ShouldFire() public {
        MarketSnapshot memory atThreshold = MarketSnapshot({
            totalAssets: 1000 ether,
            totalLiabilities: 1050 ether
        });
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(_makeOutput(atThreshold));
        (bool respond, ) = trap.shouldRespond(data);
        assertTrue(respond, "Trap SHOULD fire at exactly 5% divergence");
    }

    // Test 6: Just below 5% — trap should NOT fire
    function test_JustBelowThreshold_ShouldNotFire() public {
        MarketSnapshot memory justBelow = MarketSnapshot({
            totalAssets: 1000 ether,
            totalLiabilities: 1049 ether
        });
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(_makeOutput(justBelow));
        (bool respond, ) = trap.shouldRespond(data);
        assertFalse(respond, "Trap should NOT fire just below 5% threshold");
    }
}
