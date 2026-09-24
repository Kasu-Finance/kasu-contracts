# Kasu × Movement (native MoveVM) — module breakdown

Scope of work if Kasu deploys natively on Movement (Move VM), as an alternative to the Canopy bridge-to-Base path. See `Kasu Move.drawio` for the diagram this accompanies.

## Architectural keystone

Kasu KYBs the partner vault off-chain and the vault address is the only entry in the Move AllowList. This collapses identity to one counterparty — no per-end-user KYC, no signature gating, no Compilot equivalent on Move, no Kasu app integration.

## Modules

### Partner Vault — external, Move package
Partner-owned Move contract that holds end-user deposits and forwards them into Kasu via the deposit/withdrawal entry-fn calls; also maintains the per-end-user ledger needed to split same-epoch dNFT merges and auto-submits withdrawal requests before unlock. **Effort: 1–2 months + security audit, all on the partner's side.**

### kasu-contracts-move — new module, MoveVM
Full rewrite of the lending pool, tranche, clearing, and fixed-term-deposit semantics onto Move's resource model (`fungible_asset`, `Object`, custom loss resource), with multi-step clearing made safe under Block-STM via a `ClearingCoordinator` resource that enforces idempotent, ordered steps. Storage layouts must be designed for Move package compatibility from day one (immutable public structs, explicit migration entry-fns) since Move's upgrade rules are stricter than Solidity proxies. **Effort: several months total rewrite, plus audit on top.**

### kasu-sdk-move — new package, TypeScript
Movement TS SDK transport for reads and writes, with Move module ABI codegen for type-safe entry-fn calls. Public API shape kept deliberately close to the EVM `kasu-sdk` so consumers can port between chains with minimal diff. **Effort: weeks-to-months.**

### kasu-indexer-move — new module, TypeScript
Port the existing `schema.graphql` data model and ingest Movement's tx stream (indexer-grpc or REST poll), serving the same GraphQL/REST surface that EVM consumers rely on today. Must handle Movement-specific reorg + finality semantics and backfill cleanly. **Effort: month+.**

### clearing operator — FE module extending kasu-clearing
Coordinator-aware step sequencing with idempotent retries, a mandatory `/simulate` dry-run before any signing, and Movement-native multisig support (Aptos `multisig_account` style rather than Safe). **Effort: month+.**

### kasu-agreements — extension of existing service
Add Movement chain identity to the existing chain-aware routing — no new flows, no new infrastructure. **Effort: month+.**

## Bottom line

`kasu-contracts-move` is the dominant cost; the rest are tractable ports and extensions of existing modules. This path is materially heavier than the Canopy bridge-to-Base path (which requires zero Kasu code) and should only be pursued if a native Movement presence is strategically required.
