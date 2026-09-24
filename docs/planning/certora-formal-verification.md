# Certora Formal Verification — Scope & Planning

**Status:** Planning only — nothing installed or run yet.
**Date:** 2026-06-05
**Owner:** Kiril
**Prereq:** Certora personal access key (held; tier assumed **free Basic** until confirmed in practice).

---

## 1. What this is (and isn't)

Certora Prover is real **formal verification**: you write a CVL spec (invariants + rules)
for a contract, and an SMT-backed prover either **proves the property holds for all
inputs/states** or returns a **concrete counterexample**. This is categorically stronger
than our existing layers:

`forge test` (examples) → AI audit skills (heuristic reasoning) → fuzz/invariant tests
(bounded automated) → **Certora (proof of specific invariants)** → human audit firm.

**Honest framing for any claim we make:** Certora proves *the spec*, not "the contract."
Every claim stays scoped — "we formally proved `sum(userActiveShares) == totalSupply`,"
**never** "the contract is verified / proven safe." A contract can satisfy every property
we wrote and still be exploitable via a property we never wrote down.

> The AI audit skills in `.claude/skills/` (feynman, state-inconsistency, nemesis) and
> `skills/SECURITY_AUDIT.md` are **heuristic LLM reviews, not formal verification**. They
> do not produce proofs. They are complementary, not a substitute, and we must not label
> their output as "passed formal verification."

---

## 2. Prerequisite gap (environment)

Measured on this machine 2026-06-05:

| Requirement | Certora needs | Have | Action |
|---|---|---|---|
| Python | 3.9+ | 3.13.7 | ✅ none |
| `certora-cli` | latest | not installed | `pip3 install certora-cli` |
| **Java/JDK** | **21+** | **1.8 (Java 8)** | ❌ **blocker** — `brew install openjdk@21` |
| solc | 0.8.23 (pragma) | 0.7.4, no solc-select | `solc-select` + install/use 0.8.23 |
| `CERTORAKEY` | env var | key held | `export CERTORAKEY=…` (→ `~/.zshenv`) |
| Foundry | — | 1.5.1 | ✅ remappings reused by Certora `.conf` |

The local CLI only **packages + uploads** the job to Certora's cloud prover; it still
won't run on JDK 8. JDK 21 is the one true blocker.

Docs: https://docs.certora.com/en/latest/docs/user-guide/install.html

---

## 3. What drives cost on THIS codebase

The dominant difficulty drivers for an SMT prover are **loops** (each must be unrolled to
a fixed bound — which also caps how general the proof is) and **cross-contract linking**.
Measured across candidate targets:

| Target | LOC (incl. inherited) | Loops | Cross-contract | Difficulty |
|---|---|---|---|---|
| Access-control gating | system-wide, parametric | n/a | none (per-fn) | 🟢 Easy |
| Tranche solvency | ~590 (Tranche + TrancheLoss) | 0 direct, 1 inherited (loss-mint over `_trancheUsers`) | 3 ifaces (LendingPool, Manager, UserManager) + ERC4626 + ERC1155 | 🟡 Moderate |
| Clearing conservation | ~1,800 (Calc+Exec+Pending+Coord) | **23** (12+3+5+3) | 4 contracts, unbounded request/user arrays | 🔴 Hard |

`AcceptedRequestsCalculation.sol` (459 LOC, **12 loops**) is the problem child. Loop-heavy
code yields only a **bounded** proof ("holds for ≤ N requests/clearing") unless the loops
are replaced with summaries (munged harness contracts) — that's where weeks of effort go.

---

## 4. Phased plan

| Phase | Work | Effort (focused) | Output |
|---|---|---|---|
| **0 — Toolchain** | JDK 21, solc-select 0.8.23, `certora-cli`, `.conf` w/ remappings, 5-line "hello world" proof to confirm cloud roundtrip | **1–2 hrs** | Working `certoraRun` |
| **1 — Access-control spike** | One parametric rule over all state-mutating fns: "reverts without correct role" (e.g. only `ROLE_KASU_ADMIN` may call `setRewardCaps`) | **0.5–1 day** | First real proof on real code, ~free |
| **2 — Tranche solvency** | CVL spec: `sum(userActiveShares)==totalSupply`, `convertToAssets(convertToShares(x)) <= x` (rounding in protocol's favor), no share inflation, `userActiveShares` only moves on `deposit()`/`removeUserActiveShares()`. Link/summarize the 3 ifaces. | **2–4 days** | Proof or counterexample on the documented invariant |
| **3 — Clearing conservation** | `sum(accepted) ≤ sum(requested)`, a dNFT is burned ≤ once/clearing, no spill re-enters burn path. Requires munged harnesses for the 23 loops + multi-contract linking. | **1–3 weeks**, likely a **bounded** result | Bounded proof of the dust-spill DoS bug class |

"Focused day" = authoring + review cycles + prover runs. Wall-clock is longer: each prover
run is **minutes-to-hours** and a spec takes **dozens of runs** to converge.

Phase 2 directly pins the `userActiveShares` vs `balanceOf` invariant already documented as
error-prone in `kasu-contracts/CLAUDE.md`. Phase 3 targets the clearing dust-spill DoS bug
class (see auto-memory `project_clearing_dust_spill_dos.md`).

---

## 5. Pricing

Metered unit = **prover wall-clock minutes, summed across all runs in the month** — NOT
per-run, NOT dollars. Timed-out ("unknown") runs still consume minutes.

| Plan | Price | Includes |
|---|---|---|
| **Basic (Free)** | $0 | **2,000 prover-min/month**, write your own rules, Discord support |
| **Premium** | contact sales (not public) | *unlimited* prover, onboarding, 10 seats, Certora writes/reviews specs |
| **Enterprise** | contact sales (not public) | retainer (audit + FV), expert rules, incident response, training |

Escape hatch: the Prover is **open-source** (https://github.com/Certora/CertoraProver) —
self-hosting skips the cloud quota entirely, but is heavyweight to run.

**Budget vs plan:**

| Phase | Est. monthly minutes | Fits free 2,000-min tier? |
|---|---|---|
| 0 — hello world | < 10 | ✅ |
| 1 — access-control | ~30 | ✅ huge headroom |
| 2 — tranche | ~100–300 | ✅ comfortable |
| 3 — clearing (23 loops) | **~500–1,500+** (slow + timeout-prone) | ⚠️ could blow the cap in one heavy month |

**Bottom line:** the free key covers **Phase 0 → 1 → 2 at no cost**. Phase 3 is the only
thing that strains 2,000 min/month; that's when bumping to Premium or self-hosting becomes
the lever.

---

## 6. Recommendation

1. **Don't commit to clearing first.** Run **Phase 0 → Phase 1** as a ~half-day, ~free
   de-risk: proves the toolchain end-to-end against our actual contracts + key.
2. **Phase 2 (tranche)** is the first genuinely valuable, defensible claim — tractable
   (zero loops in the core contract) and pins a known-tricky invariant.
3. **Decide Phase 3 (clearing) deliberately afterward** — it's audit-firm-grade effort,
   may only yield a bounded guarantee, and is the only real quota risk.

**Caveats to carry forward:**
- Claims stay scoped to the proven invariant — never "verified" in the abstract.
- Where loops are unrolled instead of summarized, the proof is "for ≤ N items" — always
  state N.

---

## 7. Sources

- Install: https://docs.certora.com/en/latest/docs/user-guide/install.html
- Pricing: https://www.certora.com/pricing
- Open source: https://www.certora.com/blog/certora-goes-open-source
- Prover (OSS): https://github.com/Certora/CertoraProver
