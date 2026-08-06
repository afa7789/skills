# Solidity 29-Check Checklist — Detailed Entries

One section per check. Format: **What** / **Why it bites** / **Vulnerable pattern** / **Fix** / **Detection**.

---

## S01 — Division Before Multiplication

**What:** Integer division in Solidity truncates toward zero. Doing the division before the multiplication on small numerators yields zero.

**Why it bites:** Off-by-rounding-of-zero bugs. Calculations like `principal / 3333 * 10000` collapse to 0 whenever `principal < 3333`.

**Vulnerable:**
```solidity
interest = principal / 3333 * 10000;   // 0 for small principal
```

**Fix:** Multiply first, then divide. Order of operations preserves precision.
```solidity
interest = principal * 10000 / 3333;
```

**Detection:** Slither (`divide-before-multiply`).

---

## S02 — Check-Effects-Interaction (Reentrancy)

**What:** External calls before state updates let the callee re-enter and observe stale state.

**Why it bites:** The classic reentrancy drain. Funds, balances, or allowances can be repeatedly withdrawn before the bookkeeping updates.

**Vulnerable:**
```solidity
function withdraw(uint256 amount) external {
    require(balances[msg.sender] >= amount);
    (bool ok,) = msg.sender.call{value: amount}("");
    balances[msg.sender] -= amount;   // too late
}
```

**Fix:** Checks → Effects → Interactions. Update state, then call out.
```solidity
function withdraw(uint256 amount) external {
    require(balances[msg.sender] >= amount);
    balances[msg.sender] -= amount;   // effect first
    (bool ok,) = msg.sender.call{value: amount}("");
    require(ok);
}
```

**Detection:** Slither (`reentrancy-eth`, `reentrancy-no-eth`).

---

## S03 — `transfer()` / `send()` Gas Stuffing

**What:** `transfer` and `send` forward only 2300 gas, which is insufficient for many recipients.

**Why it bites:** Contracts that expect to receive ETH and run logic (multi-sig wallets, recipients with fallback hooks) silently revert.

**Vulnerable:**
```solidity
payable(receiver).transfer(amount);   // 2300 gas only
```

**Fix:** Use `call` and check the return value.
```solidity
(bool ok,) = receiver.call{value: amount}("");
require(ok, "transfer failed");
```

**Detection:** Slither (`low-level-calls`, `unchecked-transfer`).

---

## S04 — `tx.origin` for Authentication

**What:** `tx.origin` is the original EOA of the transaction chain, not the direct caller.

**Why it bites:** A malicious intermediate contract can act on behalf of the user because `tx.origin == user`.

**Vulnerable:**
```solidity
require(tx.origin == owner);          // bypassable via intermediate
```

**Fix:** Always `msg.sender`.
```solidity
require(msg.sender == owner);
```

**Detection:** **Manual only.** Slither does NOT flag `tx.origin`. Grep `tx.origin` in the diff.

---

## S05 — Non-`safeTransfer` ERC-20

**What:** Some ERC-20s revert, some return false, some return nothing on failure.

**Why it bites:** Silent stuck funds or undetected failed transfers.

**Vulnerable:**
```solidity
IERC20(token).transfer(to, amount);   // may return false silently
```

**Fix:** OpenZeppelin's `SafeERC20` wrapper.
```solidity
using SafeERC20 for IERC20;
token.safeTransfer(to, amount);
```

**Detection:** Manual + `grep` for direct `.transfer(` / `.transferFrom(` on `IERC20`.

---

## S06 — `SafeMath` on Solidity ≥ 0.8.0

**What:** Built-in overflow/underflow checks exist from 0.8.0 onward.

**Why it bites:** Redundant library adds bytecode, gas cost, and clutter without safety benefit.

**Vulnerable:**
```solidity
using SafeMath for uint256;
a.add(b);    // unnecessary on 0.8.x
```

**Fix:** Drop `SafeMath`. Native `+` / `-` / `*` revert on overflow automatically.
```solidity
a + b;       // reverts on overflow in 0.8.0+
```

**Detection:** Manual. Check pragma vs `import "@openzeppelin/.../SafeMath.sol"`.

---

## S07 — Missing Access Control

**What:** State-changing functions callable by anyone.

**Why it bites:** Price manipulation, ownership theft, parameter overrides.

**Vulnerable:**
```solidity
function setPrice(uint256 price_) public { price = price_; }
```

**Fix:** Use `onlyOwner` or role-based access.
```solidity
function setPrice(uint256 price_) external onlyOwner { price = price_; }
```

**Detection:** Manual. Read every external/public non-view function and verify a modifier or inline `require`.

---

## S08 — Expensive Ops in Unbounded Loops

**What:** Storage writes, external calls, or memory-heavy work inside loops whose length is user-controlled.

**Why it bites:** Gas exceeds block limit → transaction always reverts → DoS.

**Vulnerable:**
```solidity
for (uint i; i < users.length; ++i) {
    token.transfer(users[i], rewards[i]);   // O(n) external calls
}
```

**Fix:** Pull pattern (each user claims) or pagination.
```solidity
function claim() external { /* one user at a time */ }
```

**Detection:** Manual. Audit every `for` / `while` loop's bound source and body.

---

## S09 — Missing Input Validation

**What:** Functions that don't validate zero-address, zero-amount, or out-of-range inputs.

**Why it bites:** Locked funds (zero address as recipient), arithmetic surprises, off-by-one.

**Vulnerable:**
```solidity
function transfer(address _to, uint256 _v) public { /* no checks */ }
```

**Fix:** `require` / `revert` every input at the top.
```solidity
require(_to != address(0), "zero to");
require(_v > 0, "zero amount");
```

**Detection:** Manual. Inspect every function parameter.

---

## S10 — Incomplete Business Logic

**What:** The function runs but the bookkeeping doesn't reflect the intended invariant.

**Why it bites:** Common pattern: a `mint` that doesn't decrement an allowance, or a `deposit` that overwrites instead of accumulating.

**Vulnerable:**
```solidity
function mint(address to, uint256 amount) external {
    require(amount <= amountAllowedToMint[msg.sender]);
    _mint(to, amount);
    // forgot: amountAllowedToMint[msg.sender] -= amount;
}
```

**Fix:** Trace invariants. For each mutation, every counter, allowance, or balance that should change must change.
```solidity
    _mint(to, amount);
    amountAllowedToMint[msg.sender] -= amount;
```

**Detection:** Manual. Map state reads → state writes for each function; every read with a `require` must have a matching write.

---

## S11 — Unpinned Pragma

**What:** `pragma solidity ^0.8.0;` for deployable code.

**Why it bites:** Future compiler versions may introduce subtle behavior changes or bugs.

**Fix:** Pin the exact tested version.
```solidity
pragma solidity 0.8.26;
```

(Use floating pragma only in libraries.)

**Detection:** Manual. Grep `pragma solidity \^`.

---

## S12 — Inconsistent Style / NatSpec

**What:** Code that doesn't follow Solidity style (function ordering, formatting, NatSpec).

**Why it bites:** Slows review, increases bug rate, breaks tooling assumptions.

**Fix:** Run `forge fmt` (Foundry) or `prettier-plugin-solidity`. Add `@title`, `@author`, `@notice`, `@param`, `@return`.

**Detection:** `forge fmt --check`, `npx prettier --check '**/*.sol'`.

---

## S13 — Missing or Mis-Indexed Events

**What:** State-changing functions with no events, or events with un-indexed address parameters.

**Why it bites:** Off-chain indexers can't track state changes; debugging is impossible; subgraphs break.

**Fix:** Emit events for every state change; `indexed` on address and id parameters.
```solidity
event PriceUpdated(address indexed setter, uint256 oldPrice, uint256 newPrice);
```

**Detection:** Manual. Compare state writes to `emit` statements in each function.

---

## S14 — Missing Unit Tests

**What:** No `test/` directory, no Foundry/Hardhat test file, or coverage on critical paths is zero.

**Why it bites:** Smart contracts are immutable post-deployment. Bug surface must be covered by tests before merge.

**Fix:** Foundry or Hardhat tests covering happy path, revert paths, and edge cases for every state-changing function. Aim > 80% branch coverage.

**Detection:** CI gate. `forge coverage` / `hardhat coverage`.

---

## S15 — Rounding in Wrong Direction

**What:** Integer division truncates toward zero. If the *user* is paying, truncating means they pay *less* than they should.

**Why it bites:** Protocol value leak. Small per-tx but compounds across many users.

**Fix:** When the user pays, round up.
```solidity
uint256 fee = (amount * feeBps + 10_000 - 1) / 10_000;   // ceil
```

When the protocol pays, round down (default truncation is fine).

**Detection:** Manual. Check every division where the result represents a payment or share.

---

## S16 — No Formatter

**What:** Inconsistent indentation, mixed quotes, line length variance.

**Fix:** `forge fmt` (Foundry) or `prettier --write '**/*.sol'` (Hardhat). Run in CI.

**Detection:** `forge fmt --check`, `prettier --check`.

---

## S17 — `_msgSender()` Without Meta-Tx Support

**What:** OpenZeppelin contracts that inherit `Context` override `_msgSender()` for meta-transactions. Using it on a non-meta-tx contract is dead abstraction.

**Why it bites:** Confuses readers, slightly bloats bytecode.

**Fix:** Use `msg.sender` directly unless the contract actually supports meta-tx (EIP-2771).

**Detection:** Manual. Check if the contract inherits `ERC2771Context` or similar.

---

## S18 — Secrets Committed to Git

**What:** `.env`, private keys, RPC URLs, deployer mnemonics, API tokens in source.

**Why it bites:** Immediate drain if the repo is public or compromised.

**Fix:** `.gitignore` for `.env`, `hardhat.config.ts` keys loaded from env. Use `gitleaks` or `git-secrets` in CI.

**Detection:** `gitleaks detect`, `git log -p | grep -iE 'private|mnemonic|secret'`.

---

## S19 — No Frontrunning / Slippage Guards

**What:** Swap, mint, withdraw, or claim functions that don't accept a `minAmountOut` or `maxPrice`.

**Why it bites:** Sandwich attacks drain value; signed-but-pending transactions can be replayed at worse prices.

**Fix:** Always require a user-specified limit.
```solidity
function swap(uint amountIn, uint minAmountOut, ...) external {
    require(amountOut >= minAmountOut, "slippage");
}
```

**Detection:** Manual. Audit every external function that takes a price/amount without a limit parameter.

---

## S20 — Overwrite Instead of Accumulate

**What:** Using `=` instead of `+=` / `-=` for state that should aggregate across multiple calls.

**Why it bites:** Lost funds, lost state, wrong accounting.

**Vulnerable:**
```solidity
function deposit() external payable { balances[msg.sender] = msg.value; }
```

**Fix:**
```solidity
function deposit() external payable { balances[msg.sender] += msg.value; }
```

**Detection:** Manual. Every assignment to a balance, allowance, or counter should be `+=` unless explicitly intended to reset.

---

## S21 — Price Oracle Manipulation

**What:** Using a low-liquidity DEX spot price, a single-source TWAP, or no staleness check.

**Why it bites:** Flash loans can pump/dump spot within a single transaction. Protocol reads a manipulated price and issues under-collateralized loans or executes unfair swaps.

**Fix:** Chainlink or a robust TWAP with sufficient window. Always check `updatedAt` / staleness.
```solidity
(, int256 price,, uint256 updatedAt,) = feed.latestRoundData();
require(block.timestamp - updatedAt < MAX_STALENESS, "stale");
```

**Detection:** Manual. Identify every price read; trace its source; assess manipulability.

---

## S22 — Flash Loan Amplification

**What:** Even a contract without an obvious flash-loan exposure can be exploited via flash-loan-funded manipulation of *its* dependencies.

**Why it bites:** Turns a "minor" economic flaw into a major exploit.

**Fix:** Make every price-dependent invariant robust to large single-block capital movements. Use oracles that don't depend on the contract's own liquidity.

**Detection:** Manual. For each oracle, ask: "Could a flash loan move this price by ≥ X% within one transaction?"

---

## S23 — Insecure Randomness

**What:** Using `block.timestamp`, `block.prevrandao`, `blockhash`, or a combination as randomness.

**Why it bites:** Validators/miners can influence or withhold blocks to bias the outcome.

**Vulnerable:**
```solidity
uint256 winner = uint256(blockhash(block.number - 1)) % players.length;
```

**Fix:** Chainlink VRF or a commit-reveal scheme.
```solidity
// Chainlink VRF
uint256 reqId = vrfCoordinator.requestRandomWords(...);
```

**Detection:** Manual. Grep for `block.timestamp`, `block.prevrandao`, `blockhash`, `block.difficulty` used in outcome-determinative logic.

---

## S24 — DoS via Gas Limit on Unbounded Loops

**What:** Iterating over a dynamically-grown array inside a single transaction.

**Why it bites:** The function works for 100 users and breaks at 10,000. Funds locked.

**Fix:** Pull pattern, pagination, or mapping-by-address instead of array iteration.
```solidity
mapping(address => uint256) private balances;
// each user withdraws themselves
```

**Detection:** Manual. Identify loops over `array`, `users`, `depositors`, etc. with no upper bound.

---

## S25 — Unchecked Low-Level External Calls

**What:** Using `call`, `delegatecall`, `staticcall`, or `send` without checking the success bool.

**Why it bites:** Failed calls return `false` instead of reverting. Code continues in an inconsistent state.

**Vulnerable:**
```solidity
(bool ok,) = target.call{value: amount}("");
balances[target] -= amount;   // ran even if call failed
```

**Fix:** Check the bool.
```solidity
(bool ok,) = target.call{value: amount}("");
require(ok, "Transfer failed");
balances[target] -= amount;
```

**Detection:** Slither (`unchecked-lowlevel`).

---

## S26 — `delegatecall` Storage Collision

**What:** Storage layout drift between proxy and implementation, or between two implementations switched via delegatecall.

**Why it bites:** Critical state variables (ownership, balances) get overwritten by a different contract's slot.

**Fix:** Use OpenZeppelin's upgradeable contracts (storage gaps, `UnstructuredStorage`) or guarantee identical layout. Never reorder state variables across upgrades.

**Detection:** Slither (`storage-array`, `incorrect-inheritance`, manual storage-layout review).

---

## S27 — Critical Logic on `block.timestamp`

**What:** Using `block.timestamp` for sub-second precision, randomness, or winner determination.

**Why it bites:** Validators can shift timestamp by a few seconds. Acceptable for coarse windows (e.g. 30-day lockups), exploitable for second-level decisions.

**Fix:** Use block numbers for fine granularity (each block has a known target interval), or Chainlink VRF for randomness.

**Detection:** Manual. Flag every `block.timestamp` use and check the precision requirement.

---

## S28 — Signature Replay

**What:** Signed messages without nonce, chainId, or contract address.

**Why it bites:** A signature can be replayed on another chain, in another contract, or after the user's intent expired.

**Fix:** EIP-712 structured signing with `nonce`, `chainId`, and `verifyingContract`.
```solidity
bytes32 structHash = keccak256(abi.encode(
    _TOKEN_TYPEHASH, owner, spender, value,
    nonces[owner]++,    // ← nonce
    chainId,            // ← chainId
    address(this)       // ← contract address
));
```

**Detection:** Manual. Inspect every `ecrecover` / signature use; verify domain separator includes chainId and contract address.

---

## S29 — Forced Ether

**What:** Assuming `address(this).balance == sum_of_legitimate_deposits`.

**Why it bites:** `selfdestruct(target)` forces ETH into any contract. `coinbase` rewards and `block.coinbase` (pre-merge) too. Logic that depends on balance can be broken by unrelated incoming ETH.

**Fix:** Track deposits in an internal variable, not via `this.balance`.
```solidity
uint256 internal _totalDeposited;
function deposit() external payable { _totalDeposited += msg.value; }
```

**Detection:** Manual. Flag every `address(this).balance` read; require an internal counter cross-check.
