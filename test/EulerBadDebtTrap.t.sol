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
}
