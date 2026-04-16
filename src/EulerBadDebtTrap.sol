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
        for (uint256 i = 0; i < data.length; i++) {
            CollectOutput memory output = abi.decode(data[i], (CollectOutput));

            // If liabilities exceed assets, bad debt is forming
            if (output.totalLiabilities > output.totalAssets) {
                uint256 divergence = output.totalLiabilities - output.totalAssets;
                uint256 divergenceBps = (divergence * 10000) / output.totalAssets;

                // Trigger if divergence exceeds our threshold
                if (divergenceBps >= THRESHOLD_BPS) {
                    return (true, abi.encode(output.totalAssets, output.totalLiabilities));
                }
            }
        }
        return (false, bytes(""));
    }
}
