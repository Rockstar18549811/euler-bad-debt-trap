// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Trap} from "drosera-contracts/Trap.sol";

interface IEulerEToken {
    function totalSupply() external view returns (uint256);
    function totalSupplyUnderlying() external view returns (uint256);
}

interface IEulerDToken {
    function totalSupply() external view returns (uint256);
}

struct MarketSnapshot {
    uint256 totalAssets;
    uint256 totalLiabilities;
}

struct CollectOutput {
    MarketSnapshot dai;
    MarketSnapshot usdc;
    MarketSnapshot wbtc;
    MarketSnapshot steth;
}

contract EulerBadDebtTrap is Trap {

    // Euler Finance v1 — DAI market (Ethereum mainnet, verified)
    address public constant EDAI   = 0xe025E3ca2bE02316033184551D4d3Aa22024D9DC;
    address public constant DDAI   = 0x6085BC95573b59b5f12966B8f5e6db1A06B504e7;

    // Euler Finance v1 — USDC market
    // NOTE: Replace with verified address from euler-interfaces repository
    address public constant EUSDC  = 0x84dceC4b1B3E0EA0C4a20f7f0dB08E2BE8EF5E18;
    address public constant DUSDC  = 0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716;

    // Euler Finance v1 — wBTC market
    // NOTE: Replace with verified address from euler-interfaces repository
    address public constant EWBTC  = 0x48e7e7F7D5f5e3e7e5f5e5e5E5e5E5e5e5e5E501;
    address public constant DWBTC  = 0xe2cA0a7D1AB8c6e4B4Ec0E7a8be2c3d4e5f6a701;

    // Euler Finance v1 — stETH market
    // NOTE: Replace with verified address from euler-interfaces repository
    address public constant ESTETH = 0xbE09aCF7a2257AA7b4fB41F8D3E2B5c4DDa12341;
    address public constant DSTETH = 0xA1B2C3d4E5f6A7b8C9D0E1f2a3B4C5d6e7F8A901;

    // Threshold: 5% divergence triggers the trap
    uint256 public constant THRESHOLD_BPS = 500;

    constructor() {}

    function _getSnapshot(address eToken, address dToken)
        internal view returns (MarketSnapshot memory snap)
    {
        snap.totalAssets = IEulerEToken(eToken).totalSupplyUnderlying();
        snap.totalLiabilities = IEulerDToken(dToken).totalSupply();
    }

    function collect() external override view returns (bytes memory) {
        CollectOutput memory out;
        out.dai   = _getSnapshot(EDAI,   DDAI);
        out.usdc  = _getSnapshot(EUSDC,  DUSDC);
        out.wbtc  = _getSnapshot(EWBTC,  DWBTC);
        out.steth = _getSnapshot(ESTETH, DSTETH);
        return abi.encode(out);
    }

    function _isBadDebt(MarketSnapshot memory m) internal pure returns (bool) {
        if (m.totalAssets == 0) {
            return m.totalLiabilities > 0;
        }
        if (m.totalLiabilities > m.totalAssets) {
            uint256 divergence = m.totalLiabilities - m.totalAssets;
            uint256 divergenceBps = (divergence * 10000) / m.totalAssets;
            return divergenceBps >= THRESHOLD_BPS;
        }
        return false;
    }

    function shouldRespond(
        bytes[] calldata data
    ) external override pure returns (bool, bytes memory) {
        if (data.length == 0) {
            return (false, bytes(""));
        }

        CollectOutput memory current = abi.decode(data[0], (CollectOutput));

        if (_isBadDebt(current.dai)) {
            return (true, abi.encode(current.dai.totalAssets, current.dai.totalLiabilities));
        }
        if (_isBadDebt(current.usdc)) {
            return (true, abi.encode(current.usdc.totalAssets, current.usdc.totalLiabilities));
        }
        if (_isBadDebt(current.wbtc)) {
            return (true, abi.encode(current.wbtc.totalAssets, current.wbtc.totalLiabilities));
        }
        if (_isBadDebt(current.steth)) {
            return (true, abi.encode(current.steth.totalAssets, current.steth.totalLiabilities));
        }

        return (false, bytes(""));
    }
}
