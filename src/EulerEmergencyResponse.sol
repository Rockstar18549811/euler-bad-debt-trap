// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEulerPauseTarget {
    function emergencyPause() external;
    function paused() external view returns (bool);
}

contract EulerEmergencyResponse {
    enum IncidentType {
        None,
        BadDebt,
        ReadFailure,
        BadDebtWorsening
    }

    enum MarketId {
        DAI,
        USDC,
        WBTC,
        STETH
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

    address public immutable DROSERA_CALLER;
    address public owner;

    uint256 public immutable COOLDOWN_BLOCKS;
    uint256 public lastResponseBlock;

    mapping(address => bool) public approvedPauseTargets;
    mapping(bytes32 => bool) public handledIncidents;

    event OwnerUpdated(address indexed oldOwner, address indexed newOwner);
    event PauseTargetUpdated(address indexed target, bool approved);

    event EulerBadDebtContained(
        bytes32 indexed incidentId,
        MarketId indexed marketId,
        address indexed pauseTarget,
        IncidentType incidentType,
        uint256 totalAssets,
        uint256 totalLiabilities,
        uint256 divergenceBps,
        uint256 blockNumber
    );

    error OnlyOwner();
    error OnlyDrosera();
    error CooldownActive();
    error InvalidIncident();
    error PauseTargetNotApproved();
    error PauseFailed();
    error PauseDidNotTakeEffect();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlyDrosera() {
        if (msg.sender != DROSERA_CALLER) revert OnlyDrosera();
        _;
    }

    constructor(
        address droseraCaller_,
        address owner_,
        uint256 cooldownBlocks_
    ) {
        require(droseraCaller_ != address(0), "zero drosera caller");
        require(owner_ != address(0), "zero owner");

        DROSERA_CALLER = droseraCaller_;
        owner = owner_;
        COOLDOWN_BLOCKS = cooldownBlocks_;
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero owner");
        emit OwnerUpdated(owner, newOwner);
        owner = newOwner;
    }

    function setPauseTarget(address target, bool approved) external onlyOwner {
        require(target != address(0), "zero target");
        approvedPauseTargets[target] = approved;
        emit PauseTargetUpdated(target, approved);
    }

    function handleIncident(bytes calldata rawIncident) external onlyDrosera {
        if (
            lastResponseBlock != 0 &&
            block.number < lastResponseBlock + COOLDOWN_BLOCKS
        ) {
            revert CooldownActive();
        }

        Incident memory incident = abi.decode(rawIncident, (Incident));
        bytes32 incidentId = keccak256(rawIncident);

        if (handledIncidents[incidentId]) return;

        if (incident.incidentType == IncidentType.None) revert InvalidIncident();
        if (incident.pauseTarget == address(0)) revert InvalidIncident();
        if (!approvedPauseTargets[incident.pauseTarget]) revert PauseTargetNotApproved();

        handledIncidents[incidentId] = true;
        lastResponseBlock = block.number;

        try IEulerPauseTarget(incident.pauseTarget).emergencyPause() {
        } catch {
            revert PauseFailed();
        }

        if (!IEulerPauseTarget(incident.pauseTarget).paused()) {
            revert PauseDidNotTakeEffect();
        }

        emit EulerBadDebtContained(
            incidentId,
            incident.marketId,
            incident.pauseTarget,
            incident.incidentType,
            incident.totalAssets,
            incident.totalLiabilities,
            incident.divergenceBps,
            incident.blockNumber
        );
    }
}
