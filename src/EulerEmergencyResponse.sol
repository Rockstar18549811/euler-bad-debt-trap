// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface IProtocol {
    function pauseMarket(address market) external;
}

contract EulerEmergencyResponse {

    address public immutable authorizedCaller;
    address public immutable protocol;

    bool public paused;
    uint256 public lastTotalAssets;
    uint256 public lastTotalLiabilities;

    event BadDebtDetected(uint256 totalAssets, uint256 totalLiabilities, uint256 timestamp);
    event MarketPaused(uint256 totalAssets, uint256 totalLiabilities, uint256 timestamp);

    modifier onlyDrosera() {
        require(msg.sender == authorizedCaller, "Not authorized: only Drosera can call this");
        _;
    }

    constructor(address _authorizedCaller) {
        require(_authorizedCaller != address(0), "Invalid authorized caller");
        authorizedCaller = _authorizedCaller;
        protocol = address(0); // set to real Euler address in production
    }

    // This is the function the trap calls when bad debt is detected
    // Matches the response_function in drosera.toml:
    // "pauseBadDebtMarket(uint256,uint256)"
    function pauseBadDebtMarket(
        uint256 totalAssets,
        uint256 totalLiabilities
    ) external onlyDrosera {
        paused = true;
        lastTotalAssets = totalAssets;
        lastTotalLiabilities = totalLiabilities;

        emit BadDebtDetected(totalAssets, totalLiabilities, block.timestamp);
        emit MarketPaused(totalAssets, totalLiabilities, block.timestamp);
    }

    // View function to check if market is paused
    function isMarketPaused() external view returns (bool) {
        return paused;
    }

    // View function to check last recorded bad debt state
    function getLastBadDebtState() external view returns (
        uint256 assets,
        uint256 liabilities
    ) {
        return (lastTotalAssets, lastTotalLiabilities);
    }
}
