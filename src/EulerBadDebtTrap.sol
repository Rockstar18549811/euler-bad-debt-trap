// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

interface IEulerETokenLike {
    function totalSupplyUnderlying() external view returns (uint256);
}

interface IEulerDTokenLike {
    function totalSupply() external view returns (uint256);
}

contract EulerBadDebtTrap is ITrap {
    uint8 public constant SCHEMA_VERSION = 1;
    uint256 public constant BPS = 10_000;
    uint256 public constant BAD_DEBT_THRESHOLD_BPS = 500;
    uint256 public constant REQUIRED_SAMPLES = 3;

    enum MarketId {
        DAI,
        USDC,
        WBTC,
        STETH
    }

    enum IncidentType {
        None,
        BadDebt,
        ReadFailure,
        BadDebtWorsening
    }

    struct MarketConfig {
        address eToken;
        address dToken;
        address pauseTarget;
    }

    struct MarketSnapshot {
        MarketId marketId;
        address eToken;
        address dToken;
        address pauseTarget;
        uint256 totalAssets;
        uint256 totalLiabilities;
        bool assetReadOk;
        bool liabilityReadOk;
    }

    struct CollectOutput {
        uint8 schemaVersion;
        uint256 blockNumber;
        MarketSnapshot dai;
        MarketSnapshot usdc;
        MarketSnapshot wbtc;
        MarketSnapshot steth;
    }

    struct Incident {
        IncidentType incidentType;
        MarketId marketId;
        address eToken;
        address dToken;
        address pauseTarget;
        uint256 totalAssets;
        uint256 totalLiabilities;
        uint256 divergenceBps;
        uint256 previousDivergenceBps;
        uint256 blockNumber;
    }

    address public constant E_DAI = 0x1111111111111111111111111111111111111001;
    address public constant D_DAI = 0x1111111111111111111111111111111111111002;
    address public constant P_DAI = 0x1111111111111111111111111111111111111003;

    address public constant E_USDC = 0x1111111111111111111111111111111111112001;
    address public constant D_USDC = 0x1111111111111111111111111111111111112002;
    address public constant P_USDC = 0x1111111111111111111111111111111111112003;

    address public constant E_WBTC = 0x1111111111111111111111111111111111113001;
    address public constant D_WBTC = 0x1111111111111111111111111111111111113002;
    address public constant P_WBTC = 0x1111111111111111111111111111111111113003;

    address public constant E_STETH = 0x1111111111111111111111111111111111114001;
    address public constant D_STETH = 0x1111111111111111111111111111111111114002;
    address public constant P_STETH = 0x1111111111111111111111111111111111114003;

    uint256 public constant MARKET_SNAPSHOT_WORDS = 8;
    uint256 public constant COLLECT_OUTPUT_WORDS = 2 + (4 * MARKET_SNAPSHOT_WORDS);
    uint256 public constant COLLECT_OUTPUT_SIZE = COLLECT_OUTPUT_WORDS * 32;

    function collect() external view override returns (bytes memory) {
        return abi.encode(
            CollectOutput({
                schemaVersion: SCHEMA_VERSION,
                blockNumber: block.number,
                dai: _snapshot(MarketId.DAI, E_DAI, D_DAI, P_DAI),
                usdc: _snapshot(MarketId.USDC, E_USDC, D_USDC, P_USDC),
                wbtc: _snapshot(MarketId.WBTC, E_WBTC, D_WBTC, P_WBTC),
                steth: _snapshot(MarketId.STETH, E_STETH, D_STETH, P_STETH)
            })
        );
    }

    function shouldRespond(
        bytes[] calldata data
    ) external pure override returns (bool, bytes memory) {
        if (data.length != REQUIRED_SAMPLES) return (false, bytes(""));
        if (!_validEncodedSamples(data)) return (false, bytes(""));

        CollectOutput memory current = abi.decode(data[0], (CollectOutput));
        CollectOutput memory previous = abi.decode(data[1], (CollectOutput));
        CollectOutput memory oldest = abi.decode(data[data.length - 1], (CollectOutput));

        if (!_validWindow(current, previous, oldest)) return (false, bytes(""));

        (bool fire, Incident memory incident) = _evaluateMarket(current.dai, previous.dai, current.blockNumber);
        if (fire) return (true, abi.encode(incident));

        (fire, incident) = _evaluateMarket(current.usdc, previous.usdc, current.blockNumber);
        if (fire) return (true, abi.encode(incident));

        (fire, incident) = _evaluateMarket(current.wbtc, previous.wbtc, current.blockNumber);
        if (fire) return (true, abi.encode(incident));

        (fire, incident) = _evaluateMarket(current.steth, previous.steth, current.blockNumber);
        if (fire) return (true, abi.encode(incident));

        return (false, bytes(""));
    }

    function _snapshot(
        MarketId marketId,
        address eToken,
        address dToken,
        address pauseTarget
    ) internal view returns (MarketSnapshot memory snap) {
        snap.marketId = marketId;
        snap.eToken = eToken;
        snap.dToken = dToken;
        snap.pauseTarget = pauseTarget;

        if (eToken.code.length > 0) {
            try IEulerETokenLike(eToken).totalSupplyUnderlying() returns (uint256 assets) {
                snap.totalAssets = assets;
                snap.assetReadOk = true;
            } catch {
                snap.assetReadOk = false;
            }
        }

        if (dToken.code.length > 0) {
            try IEulerDTokenLike(dToken).totalSupply() returns (uint256 liabilities) {
                snap.totalLiabilities = liabilities;
                snap.liabilityReadOk = true;
            } catch {
                snap.liabilityReadOk = false;
            }
        }
    }

    function _evaluateMarket(
        MarketSnapshot memory current,
        MarketSnapshot memory previous,
        uint256 blockNumber
    ) internal pure returns (bool, Incident memory incident) {
        uint256 currentDivergence = _divergenceBps(current.totalAssets, current.totalLiabilities);
        uint256 previousDivergence = _divergenceBps(previous.totalAssets, previous.totalLiabilities);

        incident = Incident({
            incidentType: IncidentType.None,
            marketId: current.marketId,
            eToken: current.eToken,
            dToken: current.dToken,
            pauseTarget: current.pauseTarget,
            totalAssets: current.totalAssets,
            totalLiabilities: current.totalLiabilities,
            divergenceBps: currentDivergence,
            previousDivergenceBps: previousDivergence,
            blockNumber: blockNumber
        });

        if (!current.assetReadOk || !current.liabilityReadOk) {
            incident.incidentType = IncidentType.ReadFailure;
            return (true, incident);
        }

        if (currentDivergence >= BAD_DEBT_THRESHOLD_BPS) {
            incident.incidentType = currentDivergence > previousDivergence
                ? IncidentType.BadDebtWorsening
                : IncidentType.BadDebt;
            return (true, incident);
        }

        return (false, incident);
    }

    function _divergenceBps(
        uint256 assets,
        uint256 liabilities
    ) internal pure returns (uint256) {
        if (liabilities <= assets) return 0;
        if (assets == 0) return type(uint256).max;
        uint256 gap = liabilities - assets;
        return (gap * BPS) / assets;
    }

    function _validEncodedSamples(bytes[] calldata data) internal pure returns (bool) {
        for (uint256 i = 0; i < data.length; i++) {
            if (data[i].length != COLLECT_OUTPUT_SIZE) return false;
        }
        return true;
    }

    function _validWindow(
        CollectOutput memory current,
        CollectOutput memory previous,
        CollectOutput memory oldest
    ) internal pure returns (bool) {
        if (current.schemaVersion != SCHEMA_VERSION) return false;
        if (previous.schemaVersion != SCHEMA_VERSION) return false;
        if (oldest.schemaVersion != SCHEMA_VERSION) return false;
        if (current.blockNumber != previous.blockNumber + 1) return false;
        if (previous.blockNumber != oldest.blockNumber + 1) return false;
        return true;
    }

    function decodeIncident(bytes calldata data) external pure returns (Incident memory) {
        return abi.decode(data, (Incident));
    }
}
