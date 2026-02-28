# 🌾 Yield Farming Core

![Solidity](https://img.shields.io/badge/Solidity-0.8.24-363636?style=flat-square&logo=solidity)
![Coverage](https://img.shields.io/badge/Coverage-100%25-brightgreen?style=flat-square)
![UX](https://img.shields.io/badge/UX-EIP_2612_Permit-blue?style=flat-square)

A yield farming smart contract infrastructure for ERC20 tokens.

This protocol implements specific features to handle edge cases in decentralized finance, including gas minimization, transaction reduction, and non-standard token compatibility.

## 🏗 Architecture & Design Decisions

### 1. 1-Transaction Staking (EIP-2612)
- **Context:** Standard staking requires an `approve` transaction followed by a `stake` transaction.
- **Implementation:** Integrated `IERC20Permit`. Users sign an off-chain message, and the contract executes the approval and the deposit in a single transaction (`stakeWithPermit`).

### 2. Deflationary Token Support (Fee-on-Transfer)
- **Context:** Tokens with transfer taxes result in the contract receiving fewer tokens than the requested amount.
- **Implementation:** The `_stake` function calculates the balance delta before and after the transfer. Only the actual amount received is credited to the user's position, maintaining internal accounting solvency.

### 3. Storage Slot Packing
- **Context:** EVM storage operations (`SSTORE`, `SLOAD`) are the most expensive opcodes.
- **Implementation:** The `Pool` struct is packed. The `token` address (20 bytes), `isActive` boolean (1 byte), and `lastUpdateTime` (8 bytes) share a single 32-byte storage slot. This reduces the total slot requirement from 6 to 4.

### 4. Administrative Guardrails
- **Context:** Centralized control over user funds introduces security risks.
- **Implementation:** Access control is divided into `DEFAULT_ADMIN_ROLE` and `POOL_MANAGER_ROLE`. The `rescueTokens` function explicitly reverts if an administrator attempts to withdraw assets that belong to an active staking pool.

## 🧪 Testing Strategy

The test suite utilizes Foundry, featuring:
- **Fuzzing:** Property-based tests with bounded inputs to validate reward math.
- **Mocking:** Integration of `MockRevertingToken` and `MockTokenPermit` to test failure states and signature recovery.

## 🛠 Tech Stack

* **Language:** Solidity `0.8.24`
* **Standards:** ERC20, EIP-2612
* **Framework:** Foundry

## 📝 Code Snippet: Deflationary Token Handling

```solidity
// Measure exact balance changes to support fee-on-transfer tokens
uint256 balBefore = IERC20(pool.token).balanceOf(address(this));
IERC20(pool.token).safeTransferFrom(account, address(this), amount);
uint256 balAfter = IERC20(pool.token).balanceOf(address(this));

uint256 actualAmountReceived = balAfter - balBefore;
user.amount += actualAmountReceived;
```
