
>  **Security Research Repository** - This repository contains a proof of concept for a critical vulnerability in the USDeSilo smart contract. For responsible disclosure purposes only.

##  Vulnerability Summary

The `USDeSilo` contract contains a **critical vulnerability** that leads to permanent loss of user funds due to unchecked ERC20 `transfer()` return values. When the USDe token is paused or transfer-restricted, withdrawal transactions silently fail without reverting, causing permanent accounting desynchronization.

**Severity**: 🔴 **CRITICAL**  
**Impact**: Complete loss of user funds  
**Status**: Reported to Immunefi

---

##  Table of Contents

- [Vulnerability Details](#vulnerability-details)
- [Impact](#impact)
- [Proof of Concept](#proof-of-concept)
- [Setup Instructions](#setup-instructions)
- [Running the Tests](#running-the-tests)

---

##  Vulnerability Details

### Root Cause

**File**: `src/USDeSilo_7fc7/contracts/USDeSilo.sol`  
**Function**: `withdraw(address to, uint256 amount)`  
**Line**: 28

```solidity
function withdraw(address to, uint256 amount) external onlyStakingVault {
    _USDE.transfer(to, amount); // ❌ No return value check
}
```

### The Problem

1. ERC20 `transfer()` returns `bool` (true/false)
2. Many tokens (USDT, pausable tokens) return `false` instead of reverting on failure
3. Contract never checks this return value
4. Failed transfers complete "successfully" without reverting
5. Results in permanent loss of user funds

### Attack Flow

```
User Balance: 10,000 tokens in vault
Token State: PAUSED

User withdraws → Vault updates balance to 0 ✅
              → Silo.withdraw() called
              → transfer() returns false ❌
              → Transaction succeeds ✅
              
Final State:
- User vault balance: 0 ✅
- User received: 0 tokens ❌  
- Tokens stuck: 10,000 ❌
- Recovery: IMPOSSIBLE ❌
```

---

## Impact

### Financial Loss Scenario

<img width="787" height="534" alt="Screenshot_20251022_084735" src="https://github.com/user-attachments/assets/849887a5-183e-4c49-b4cc-6df54572bdf4" />


### Who is Affected?

- ✅ **ALL users** who attempt withdrawal during token pause
- ✅ **ALL users** if Silo address is blacklisted
- ✅ **Permanent and irreversible** - no recovery mechanism exists

---

## Proof of Concept

This repository contains three comprehensive test cases:

### Test Cases

1. **`test_ExploitDemonstration()`**
   - Demonstrates core vulnerability with single user
   - Shows complete fund loss during pause

2. **`test_MultipleUsersImpact()`**
   - Shows impact on multiple users
   - Alice loses funds, Bob withdraws after unpause

3. **`test_NormalOperation()`**
   - Confirms system works when token not paused
   - Baseline comparison

### Repository Structure

```
.
├── src/
│   ├── USDeSilo.sol                    # Vulnerable contract
│   └── interfaces/
│       └── IUSDeSiloDefinitions.sol    # Interface
├── test/
│   └── USDeSiloPoC.t.sol              # Proof of Concept tests
├── foundry.toml                        # Foundry configuration
└── README.md                           # This file
```

---

##  Setup Instructions

### Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- Git

### Installation

```bash
# Clone the repository
git clone https://github.com/SaadiMalik1/Ethena


```

---

##  Running the Tests

### Run All Tests

```bash
forge test --match-contract USDeSiloVulnerabilityTest -vvvv
```

### Run Specific Test

```bash
# Exploit demonstration
forge test --match-test test_ExploitDemonstration -vvvv

# Multiple users impact
forge test --match-test test_MultipleUsersImpact -vvvv

# Normal operation
forge test --match-test test_NormalOperation -vvvv
```

----

