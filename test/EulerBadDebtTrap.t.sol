// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {EulerBadDebtTrap} from "../src/EulerBadDebtTrap.sol";
import {EulerEmergencyResponse} from "../src/EulerEmergencyResponse.sol";
import {MockEulerEToken, MockEulerDToken, MockEulerPauseTarget, MockEulerExploitSurface} from "../src/MockEulerMarket.sol";

contract EulerBadDebtTrapTest is Test {

    EulerBadDebtTrap trap;
    EulerEmergencyResponse response;

    MockEulerEToken mockEDai;
    MockEulerDToken mockDDai;
    MockEulerPauseTarget mockPDai;
    MockEulerExploitSurface exploitSurface;

    address droseraCaller = address(0xD305E8A);
    address owner = address(0x0000000000000000000000000000000000000001);

    // Helper: build a valid 3-sample data array
    function _makeSamples(
        uint256 assets,
        uint256 liabilities,
        bool assetOk,
        bool liabilityOk
    ) internal view returns (bytes[] memory data) {
        data = new bytes[](3);
        for (uint256 i = 0; i < 3; i++) {
            EulerBadDebtTrap.MarketSnapshot memory snap = EulerBadDebtTrap.MarketSnapshot({
                marketId: EulerBadDebtTrap.MarketId.DAI,
                eToken: address(mockEDai),
                dToken: address(mockDDai),
                pauseTarget: address(mockPDai),
                totalAssets: assets,
                totalLiabilities: liabilities,
                assetReadOk: assetOk,
                liabilityReadOk: liabilityOk
            });

            EulerBadDebtTrap.MarketSnapshot memory healthy = EulerBadDebtTrap.MarketSnapshot({
                marketId: EulerBadDebtTrap.MarketId.USDC,
                eToken: address(0),
                dToken: address(0),
                pauseTarget: address(0),
                totalAssets: 1000 ether,
                totalLiabilities: 900 ether,
                assetReadOk: true,
                liabilityReadOk: true
            });

            EulerBadDebtTrap.CollectOutput memory out = EulerBadDebtTrap.CollectOutput({
                schemaVersion: 1,
                blockNumber: block.number + (2 - i),
                dai: snap,
                usdc: healthy,
                wbtc: healthy,
                steth: healthy
            });
            data[i] = abi.encode(out);
        }
    }

    function setUp() public {
        trap = new EulerBadDebtTrap();
        mockEDai = new MockEulerEToken();
        mockDDai = new MockEulerDToken();
        mockPDai = new MockEulerPauseTarget(address(response));
        exploitSurface = new MockEulerExploitSurface(address(mockEDai), address(mockDDai));
        response = new EulerEmergencyResponse(droseraCaller, owner, 33);
    }

    // ===== TRAP TESTS =====

    function test_HealthyMarketDoesNotTrigger() public {
        bytes[] memory data = _makeSamples(1000 ether, 900 ether, true, true);
        (bool fire,) = trap.shouldRespond(data);
        assertFalse(fire);
    }

    function test_DAIBadDebtTriggers() public {
        bytes[] memory data = _makeSamples(800 ether, 1000 ether, true, true);
        (bool fire,) = trap.shouldRespond(data);
        assertTrue(fire);
    }

    function test_Divergence499BpsDoesNotTrigger() public {
        bytes[] memory data = _makeSamples(1000 ether, 1049 ether, true, true);
        (bool fire,) = trap.shouldRespond(data);
        assertFalse(fire);
    }

    function test_Divergence500BpsTriggers() public {
        bytes[] memory data = _makeSamples(1000 ether, 1050 ether, true, true);
        (bool fire,) = trap.shouldRespond(data);
        assertTrue(fire);
    }

    function test_ZeroAssetsNonzeroLiabilitiesTriggers() public {
        bytes[] memory data = _makeSamples(0, 1000 ether, true, true);
        (bool fire,) = trap.shouldRespond(data);
        assertTrue(fire);
    }

    function test_ReadFailureTriggers() public {
        bytes[] memory data = _makeSamples(0, 0, false, false);
        (bool fire,) = trap.shouldRespond(data);
        assertTrue(fire);
    }

    function test_WrongSampleCountRejected() public {
        bytes[] memory data = new bytes[](2);
        data[0] = new bytes(trap.COLLECT_OUTPUT_SIZE());
        data[1] = new bytes(trap.COLLECT_OUTPUT_SIZE());
        (bool fire,) = trap.shouldRespond(data);
        assertFalse(fire);
    }

    function test_MalformedShortBytesDoNotRevert() public {
        bytes[] memory data = new bytes[](3);
        data[0] = new bytes(10);
        data[1] = new bytes(10);
        data[2] = new bytes(10);
        (bool fire,) = trap.shouldRespond(data);
        assertFalse(fire);
    }

    function test_MalformedLongBytesDoNotRevert() public {
        bytes[] memory data = new bytes[](3);
        data[0] = new bytes(1000);
        data[1] = new bytes(1000);
        data[2] = new bytes(1000);
        (bool fire,) = trap.shouldRespond(data);
        assertFalse(fire);
    }

    // ===== RESPONSE TESTS =====

    function test_WrongCallerRejected() public {
        vm.prank(address(0xBad));
        vm.expectRevert(EulerEmergencyResponse.OnlyDrosera.selector);
        response.handleIncident(bytes(""));
    }

    function test_OwnerCanApprovePauseTarget() public {
        vm.prank(owner);
        response.setPauseTarget(address(mockPDai), true);
        assertTrue(response.approvedPauseTargets(address(mockPDai)));
    }

    function test_NonOwnerCannotApprovePauseTarget() public {
        vm.prank(address(0xBad));
        vm.expectRevert(EulerEmergencyResponse.OnlyOwner.selector);
        response.setPauseTarget(address(mockPDai), true);
    }

    function test_UnapprovedTargetRejected() public {
        EulerEmergencyResponse.Incident memory incident = EulerEmergencyResponse.Incident({
            incidentType: EulerEmergencyResponse.IncidentType.BadDebt,
            marketId: EulerEmergencyResponse.MarketId.DAI,
            eToken: address(mockEDai),
            dToken: address(mockDDai),
            pauseTarget: address(mockPDai),
            totalAssets: 800 ether,
            totalLiabilities: 1000 ether,
            divergenceBps: 2500,
            previousDivergenceBps: 0,
            blockNumber: block.number
        });

        vm.prank(droseraCaller);
        vm.expectRevert(EulerEmergencyResponse.PauseTargetNotApproved.selector);
        response.handleIncident(abi.encode(incident));
    }

    function test_ApprovedTargetPauses() public {
        mockPDai = new MockEulerPauseTarget(address(response));
        vm.prank(owner);
        response.setPauseTarget(address(mockPDai), true);

        EulerEmergencyResponse.Incident memory incident = EulerEmergencyResponse.Incident({
            incidentType: EulerEmergencyResponse.IncidentType.BadDebt,
            marketId: EulerEmergencyResponse.MarketId.DAI,
            eToken: address(mockEDai),
            dToken: address(mockDDai),
            pauseTarget: address(mockPDai),
            totalAssets: 800 ether,
            totalLiabilities: 1000 ether,
            divergenceBps: 2500,
            previousDivergenceBps: 0,
            blockNumber: block.number
        });

        vm.prank(droseraCaller);
        response.handleIncident(abi.encode(incident));
        assertTrue(mockPDai.paused());
    }

    function test_CooldownWorks() public {
        mockPDai = new MockEulerPauseTarget(address(response));
        vm.prank(owner);
        response.setPauseTarget(address(mockPDai), true);

        EulerEmergencyResponse.Incident memory incident = EulerEmergencyResponse.Incident({
            incidentType: EulerEmergencyResponse.IncidentType.BadDebt,
            marketId: EulerEmergencyResponse.MarketId.DAI,
            eToken: address(mockEDai),
            dToken: address(mockDDai),
            pauseTarget: address(mockPDai),
            totalAssets: 800 ether,
            totalLiabilities: 1000 ether,
            divergenceBps: 2500,
            previousDivergenceBps: 0,
            blockNumber: block.number
        });

        vm.prank(droseraCaller);
        response.handleIncident(abi.encode(incident));

        vm.prank(droseraCaller);
        vm.expectRevert(EulerEmergencyResponse.CooldownActive.selector);
        response.handleIncident(abi.encode(incident));
    }

    // ===== INTEGRATION TEST =====

    function test_ExploitSurfaceBurnsAssetsWithoutReducingLiabilities() public {
        exploitSurface.healthySetup(1000 ether, 800 ether);
        assertEq(mockEDai.totalSupplyUnderlying(), 1000 ether);
        assertEq(mockDDai.totalSupply(), 800 ether);

        exploitSurface.donateToReservesBug(300 ether);
        assertEq(mockEDai.totalSupplyUnderlying(), 700 ether);
        assertEq(mockDDai.totalSupply(), 800 ether);
    }
}
