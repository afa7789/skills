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

---

## S30 — Unprotected / Accidental `selfdestruct`

**What:** `selfdestruct(addr)` (or its alias `suicide`) removes the contract code from the blockchain and sends the entire remaining Ether balance to `addr`. Pre-Cancun (EIP-6780) it fully deletes code and storage. Post-Cancun it still sends ETH but no longer destroys code unless called in the same transaction as creation.

**Why it bites:** Three failure modes:
1. **Unprotected auth** — `function kill() external { selfdestruct(owner); }` with no access control lets anyone destroy the contract, rendering it permanently unusable, and drain its ETH to the target address.
2. **Wrong target** — sending ETH to a contract address that is not a safe receiver (e.g. a token, a contract with hooks that revert on `receive()`) makes the `selfdestruct` revert, and the contract can never be killed.
3. **Forced ETH from `selfdestruct` is the upstream cause of S29** — any contract whose `selfdestruct` is callable will be drained.

**Vulnerable:**
```solidity
function kill() external {                       // no auth — anyone can call
    selfdestruct(payable(owner));                // sends entire balance to owner
}
```

Also vulnerable when the function has auth but the target is a contract that reverts on receive:
```solidity
function migrate(address newVault) external onlyOwner {
    selfdestruct(payable(newVault));             // reverts if newVault has revert-on-receive
}
```

**Fix:**
1. Protect sensitive functions with access modifiers like `onlyOwner`. Even after the Dencun upgrade (EIP-6780) altered `selfdestruct` behavior — it now only sends ETH and no longer destroys code or storage unless called in the same transaction as creation — **access control remains vital** because: (a) the ETH transfer still happens, draining the contract, and (b) any function that mutates contract state before a `selfdestruct` call (e.g. marking positions closed) still relies on auth.
2. Lock `selfdestruct` behind a strong auth path (`onlyOwner` + timelock + multisig).
3. Verify the recipient can actually receive ETH (a contract with no `receive()`/`fallback()` or with a reverting one will cause the entire transaction to revert — including the selfdestruct itself, leaving the contract alive but with its state mutated).
4. Prefer migration patterns over `selfdestruct` when possible: pause the contract, snapshot balances, transfer assets, leave code in place for user inspection.
5. If the contract uses `selfdestruct` for emergency ETH recovery, accept that on Cancun-and-later chains this only works in the *same transaction* as creation — for any normal contract, the function should be removed entirely.

```solidity
function emergencyKill() external onlyOwner {
    require(!frozen, "timelock not elapsed");
    selfdestruct(payable(recoveryVault));         // recoveryVault must be EOA or have working receive
}
```

**Detection:** Slither detects unprotected `selfdestruct` (`suicidal`). Manual review must also check (a) recipient's ability to receive ETH and (b) whether `selfdestruct` is even still appropriate post-Cancun.

---

## S31 — Default Function Visibility

**What:** In Solidity versions before 0.7.0 (notably 0.6.x), functions without an explicit visibility specifier defaulted to `public`. Since 0.7.0, the compiler emits a warning, and 0.8.x makes the warning stricter — but legacy code, copy-paste from old guides, or pre-0.7 contracts still appear in the wild.

**Why it bites:** A function the developer intended as `internal` or `private` is silently callable by anyone externally. Sensitive logic — admin paths, accounting helpers, configuration mutators — becomes a public attack surface.

**Vulnerable (legacy pragma):**
```solidity
pragma solidity ^0.6.0;

function setRewardRate(uint256 r) {           // implicitly public in 0.6.x
    rewardRate = r;
}
```

**Fix:**
1. Pin to a Solidity version ≥ 0.7.0 (preferably 0.8.x) — the compiler will then warn or error on missing visibility.
2. Explicitly declare the most restrictive visibility that still allows the function to do its job: `private` > `internal` > `external` > `public`.
3. Use `external` (cheaper than `public`) for functions only ever called from outside the contract.

```solidity
function setRewardRate(uint256 r) internal {  // explicit, restrictive
    rewardRate = r;
}
```

**Detection:** Compiler warning (`Warning: No visibility specified`). Also check the pragma — if it's `^0.6.0` or `0.5.x`, assume every unspecified function in the codebase needs auditing.

---

## S32 — Off-by-One and Loop-Bound Errors

**What:** Classic index-arithmetic mistakes — `<` vs `<=`, starting a loop at 0 vs 1, off-by-one on array lengths, missing edge elements on the final iteration.

**Why it bites:** In Solidity, the last user in a payout array can silently miss their distribution; a lock-up period ends one block early; a state transition fires one too few or one too many times. Because contracts are immutable post-deployment, the bug persists.

**Vulnerable:**
```solidity
function distributeAll(address[] calldata recipients) external {
    for (uint256 i = 0; i <= recipients.length; ++i) {  // <= skips length, then OOB read
        payable(recipients[i]).transfer(share);
    }
}
```

Also vulnerable:
```solidity
function unlockTime() public view returns (uint256) {
    return depositTime + 30 days - 1;     // one second short
}
```

**Fix:**
1. Use `<` (strict less-than) for array iteration, not `<=`. The standard idiom is `for (uint256 i; i < arr.length; ++i)`.
2. Test every loop with `length == 0`, `length == 1`, and `length == N` where N is the maximum realistic size.
3. Foundry/Hardhat fuzz tests catch most off-by-one automatically — write `invariant_*` or `fuzz_*` properties.
4. For time arithmetic, never subtract 1 to "be inclusive" — use `>=` checks instead of `>` when comparing.

```solidity
function distributeAll(address[] calldata recipients) external {
    uint256 n = recipients.length;
    for (uint256 i = 0; i < n; ++i) {        // strict <
        payable(recipients[i]).transfer(share);
    }
}
```

**Detection:** Manual + Foundry/Hardhat fuzz tests. Slither does not flag off-by-one. Always run a fuzz test on any function that loops over user-controlled arrays.

---

## S33 — Centralization / Missing Pause Mechanism

**What:** A single EOA owner has unrestricted power to upgrade, drain, or modify the contract, with no timelock, no multisig, and no emergency pause.

**Why it bites:** If the owner key is compromised, the attacker gains total control. If a bug is discovered post-deployment, there's no way to halt the contract while a fix is prepared — funds are drained before governance can react.

**Vulnerable:**
```solidity
contract Vault is Ownable {
    function withdrawAll(address to) external onlyOwner {
        payable(to).transfer(address(this).balance);  // single key, no pause
    }
}
```

**Fix:**
1. Put admin keys behind a **multisig** (Gnosis Safe is the standard). For protocol-level admin, threshold ≥ 3-of-5 is typical.
2. Inherit OpenZeppelin's `Pausable` and wrap critical functions in `whenNotPaused`:
```solidity
import "@openzeppelin/contracts@5.0.0/security/Pausable.sol";

contract Vault is Ownable, Pausable {
    function withdrawAll(address to) external onlyOwner whenNotPaused {
        payable(to).transfer(address(this).balance);
    }
}
```
3. For sensitive parameter changes, use a **timelock** (`@openzeppelin/contracts/governance/TimelockController`) so the community can observe and exit before the change executes.
4. Document the admin path in NatSpec so users know who controls their funds.

**Detection:** Manual. Audit every `onlyOwner` function for the absence of a pause modifier and check the deployment config (`foundry.toml`, deployment scripts) for whether the owner is a multisig.

> **Escalation:** if the contract handles > $1M TVL or is upgradeable, treat single-key ownership without pause as **Critical** (see `reference/severity-matrix.md`).

---

## S34 — Precision Loss in Fixed-Point Math

**What:** Solidity has no floating-point types. Calculations on fractions require integer math with a scale factor (typically `1e18`). Dividing early, using too small a scale, or ordering multiplications and divisions incorrectly accumulates rounding error that becomes financial loss.

**Why it bites:** Two failure modes:
1. **Per-tx error compounds over many users.** A rounding error of 1 wei per payment becomes 1000 ETH over a million users.
2. **Symmetric loss across calls can be drained.** If the protocol rounds down when it should round up (or vice versa), a flash-loan-funded attacker can repeatedly trigger the bug to extract value.

**Vulnerable:**
```solidity
uint256 reward = principal / 3333 * 10000;          // S01 — div before mult
uint256 price = amount * 5 / 1e18;                   // scale too small
uint256 fee = (amount * 3) / 100;                    // 3% but truncates on small amounts
```

**Fix:**
1. Multiply first, divide last. Never `a / b * c` when `a < b` is possible.
2. Use a scale factor large enough that rounding to zero is negligible relative to the smallest unit the system handles. `1e18` is conventional; smaller scales need justification.
3. When the user pays the protocol, **round up** to protect the protocol (see S15).
4. For non-trivial math (e.g. AMM curves, options pricing), use a fixed-point library — OpenZeppelin's `Math.mulDiv` (which also detects overflow) or a battle-tested curve math library.

```solidity
using Math for uint256;

uint256 reward = principal.mulDiv(10000, 3333, Math.Rounding.Ceil);
uint256 fee    = amount.mulDiv(3, 100, Math.Rounding.Up);    // user pays → ceil
```

**Detection:** Manual + targeted unit tests with edge values (0, 1, scale, scale-1). Slither has limited coverage; this is mainly a test-discipline issue.

---

## S35 — Variable Shadowing

**What:** A local variable, parameter, or `for`-loop counter reuses the name of a state variable, a parent contract's variable, or a Solidity builtin. The local binding shadows the outer one within its scope.

**Why it bites:** The developer believes they are updating the contract state when they are only writing to a temporary local. The state never changes; subsequent reads return the old value. This bug is hard to spot in code review because the wrong assignment *looks* correct.

**Vulnerable:**
```solidity
contract Vault {
    uint256 public totalDeposited;       // state

    function deposit(uint256 amount) external payable {
        uint256 totalDeposited = msg.value;   // local — shadows state
        // totalDeposited += msg.value;       // forgot to update state
        emit Deposited(totalDeposited);        // emits local, not state
    }
}
```

**Fix:**
1. Adopt a naming convention that prevents the collision. OpenZeppelin's style guide uses leading-underscore for parameters: `function deposit(uint256 _amount)`. State variables stay unprefixed. Locals should not collide with either.
2. Heed compiler warnings. Modern Solidity emits `Warning: This declaration shadows an existing declaration` for state, builtin, and parent-contract shadowing — never silence them.
3. Avoid shadowing builtins (`_value`, `_block`, etc.) — it reads as defensive but actually hides bugs.
4. In `for` loops over arrays, prefer `uint256 i;` over naming the index after a state variable.

```solidity
contract Vault {
    uint256 public totalDeposited;

    function deposit(uint256 _amount) external payable {
        totalDeposited += _amount;     // updates state — no local in the way
        emit Deposited(_amount);
    }
}
```

**Detection:** Compiler warnings (`shadowing-state`, `shadowing-builtin`, `shadowing-local`). Slither also detects these. Treat every shadowing warning as a finding — even if the current code is "correct", the next refactor is the one that breaks.
