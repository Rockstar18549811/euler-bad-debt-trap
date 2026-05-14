# Euler Bad Debt Trap — Drosera PoC

## Overview
A Drosera Trap that detects Euler-style exploits by monitoring abnormal divergence between eToken asset accounting and dToken liabilities, flagging bad debt formation as soon as protocol solvency begins to break.

## The Euler Finance Attack (March 2023)
On March 13, 2023, Euler Finance lost nearly $200 million in one of DeFi's largest ever exploits.

### How the attack worked:
- Euler Finance uses two token types to track protocol health:
  - **eTokens** — represent collateral (assets the protocol holds)
  - **dTokens** — represent debt (liabilities the protocol owes)
- A healthy protocol always maintains: `assets >= liabilities`
- The attacker exploited a flaw in the `donateToReserves` function which burned eTokens (assets) WITHOUT burning the matching dTokens (liabilities)
- This created an artificial gap — liabilities exceeded assets — forming **bad debt**
- The protocol became insolvent and $197M was drained

## How The Trap Works
The trap monitors two key values every block:
- `totalAssets` — total underlying assets tracked by eDAI
- `totalLiabilities` — total debt tracked by dDAI

If liabilities exceed assets by more than **5%**, the trap fires and signals an emergency response.

```solidity
// Core detection logic
if (output.totalLiabilities > output.totalAssets) {
    uint256 divergence = output.totalLiabilities - output.totalAssets;
    uint256 divergenceBps = (divergence * 10000) / output.totalAssets;
    if (divergenceBps >= THRESHOLD_BPS) {
        return (true, abi.encode(output.totalAssets, output.totalLiabilities));
    }
}
```

## Test Results
Three tests prove the trap works correctly:

| Test | Scenario | Result |
|------|----------|--------|
| `test_HealthyProtocol` | Assets > Liabilities | ✅ Trap does NOT fire |
| `test_EulerStyleBadDebt` | Liabilities exceed assets by 20% | ✅ Trap FIRES |
| `test_SmallDivergenceBelowThreshold` | 2% divergence, below threshold | ✅ Trap does NOT fire |

## Running the Tests
```bash
forge build
forge test -vv
```

## Key Insight

The trap detects the first post-block state where market liabilities materially exceed assets, enabling an automated emergency response in a subsequent on-chain action. While Drosera cannot interrupt an atomic exploit mid-transaction, it can detect the resulting bad debt state immediately after the block is produced and trigger containment before further damage occurs.
This demo is a mock-production-like Euler replay. It models the core accounting failure: collateral/assets decrease while debt/liabilities remain. A true historical replay would require verified Euler market/controller contracts and access to the protocol.

## Drosera's Detection Capability
A Drosera trap monitoring this ratio would detect the anomalous state as soon as it becomes observable on-chain, enabling an automated emergency response in a subsequent action. While Drosera cannot interrupt an atomic exploit mid-transaction, it can detect the resulting bad debt state immediately after the block is produced and trigger containment before further damage occurs.
