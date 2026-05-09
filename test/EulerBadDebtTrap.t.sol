// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import {EulerBadDebtTrap, CollectOutput} from "../src/EulerBadDebtTrap.sol";

contract EulerBadDebtTrapTest is Test {
    EulerBadDebtTrap trap;

    function setUp() public {
        trap = new EulerBadDebtTrap();
    }

    // Test 1: Normal healthy protocol state — trap should NOT fire
    function test_HealthyProtocol() public {
        // Assets > Liabilities = healthy
        CollectOutput memory normal = CollectOutput({
            totalAssets: 1000 ether,
            totalLiabilities: 900 ether
        });

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(normal);

        (bool respond, ) = trap.shouldRespond(data);
        assertFalse(respond, "Trap should NOT fire when protocol is healthy");
    }

    // Test 2: Euler-style bad debt forming — trap SHOULD fire
    function test_EulerStyleBadDebt() public {
        // Simulating what happened during the Euler attack:
        // eTokens (assets) were donated away, dTokens (liabilities) remained
        // Assets dropped sharply while liabilities stayed the same
        CollectOutput memory exploited = CollectOutput({
            totalAssets: 800 ether,   // assets dropped
            totalLiabilities: 1000 ether  // liabilities unchanged
        });

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(exploited);

        (bool respond, ) = trap.shouldRespond(data);
        assertTrue(respond, "Trap SHOULD fire when bad debt is forming");
    }

    // Test 3: Small divergence below threshold — trap should NOT fire
    function test_SmallDivergenceBelowThreshold() public {
        // Only 2% divergence, below our 5% threshold
        CollectOutput memory minor = CollectOutput({
            totalAssets: 1000 ether,
            totalLiabilities: 1020 ether
        });

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(minor);

        (bool respond, ) = trap.shouldRespond(data);
        assertFalse(respond, "Trap should NOT fire for minor divergence");
    }

    // Test 4: Zero assets with positive liabilities — MOST severe bad debt, trap SHOULD fire
    function test_ZeroAssetsPositiveLiabilities_ShouldFire() public {
        CollectOutput memory bad = CollectOutput({
            totalAssets: 0,
            totalLiabilities: 1000 ether
        });

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(bad);

        (bool respond, ) = trap.shouldRespond(data);
        assertTrue(respond, "Trap SHOULD fire when assets are zero but liabilities exist");
    }

    // Test 5: Exactly 5% divergence — trap SHOULD fire (uses >=)
    function test_ExactlyAtThreshold_ShouldFire() public {
        CollectOutput memory atThreshold = CollectOutput({
            totalAssets: 1000 ether,
            totalLiabilities: 1050 ether // exactly 5%
        });

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(atThreshold);

        (bool respond, ) = trap.shouldRespond(data);
        assertTrue(respond, "Trap SHOULD fire at exactly 5% divergence");
    }

    // Test 6: Just below 5% — trap should NOT fire
    function test_JustBelowThreshold_ShouldNotFire() public {
        CollectOutput memory justBelow = CollectOutput({
            totalAssets: 1000 ether,
            totalLiabilities: 1049 ether // just under 5%
        });

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(justBelow);

        (bool respond, ) = trap.shouldRespond(data);
        assertFalse(respond, "Trap should NOT fire just below 5% threshold");
    }
}
