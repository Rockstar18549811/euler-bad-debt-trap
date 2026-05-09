// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Trap} from "drosera-contracts/Trap.sol";

// Minimal interface to read Euler's eToken data
interface IEulerEToken {
    function totalSupply() external view returns (uint256);
    function totalSupplyUnderlying() external view returns (uint256);
}

// Minimal interface to read Euler's dToken data
interface IEulerDToken {
    function totalSupply() external view returns (uint256);
}

struct CollectOutput {
    uint256 totalAssets;
    uint256 totalLiabilities;
}

contract EulerBadDebtTrap is Trap {

    // Euler Finance eDAI and dDAI token addresses (Ethereum mainnet)
    address public constant EDAI = 0xe025E3ca2bE02316033184551D4d3Aa22024D9DC;
    address public constant DDAI = 0x6085BC95573b59b5f12966B8f5e6db1A06B504e7;

    // Threshold: if liabilities exceed assets by more than 5%, flag it
    uint256 public constant THRESHOLD_BPS = 500; // 5% in basis points

    constructor() {}

    function collect() external override view returns (bytes memory) {
        uint256 assets = IEulerEToken(EDAI).totalSupplyUnderlying();
        uint256 liabilities = IEulerDToken(DDAI).totalSupply();

        return abi.encode(CollectOutput({
            totalAssets: assets,
            totalLiabilities: liabilities
        }));
    }

    function shouldRespond(
        bytes[] calldata data
    ) external override pure returns (bool, bytes memory) {
        if (data.length == 0) {
            return (false, bytes(""));
        }

        // Always check most recent sample first (data[0])
        CollectOutput memory current = abi.decode(data[0], (CollectOutput));

        // Most severe case: zero assets with positive liabilities
        if (current.totalAssets == 0) {
            if (current.totalLiabilities > 0) {
                return (true, abi.encode(current.totalAssets, current.totalLiabilities));
            }
            return (false, bytes(""));
        }

        // Check if current state shows bad debt divergence
        if (current.totalLiabilities > current.totalAssets) {
            uint256 divergence = current.totalLiabilities - current.totalAssets;
            uint256 divergenceBps = (divergence * 10000) / current.totalAssets;

            if (divergenceBps >= THRESHOLD_BPS) {
                // Confirm with previous sample if available
                if (data.length > 1) {
                    CollectOutput memory previous = abi.decode(data[1], (CollectOutput));
                    // Only fire if divergence is worsening or already bad
                    if (previous.totalLiabilities >= previous.totalAssets) {
                        return (true, abi.encode(current.totalAssets, current.totalLiabilities));
                    }
                }
                // Fire even without confirmation — current state is bad enough
                return (true, abi.encode(current.totalAssets, current.totalLiabilities));
            }
        }

        return (false, bytes(""));
    }
}
