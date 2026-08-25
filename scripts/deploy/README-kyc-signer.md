# KasuKycSigner — deploy and rotation runbook

Moves the KYC signature gate off Compilot's `NexeraIDSignerManager` and onto Kasu's own
`KasuKycSigner`, one chain at a time.

`KasuAllowList` verifies KYC signatures with OpenZeppelin's `SignatureChecker.isValidSignatureNow`,
which takes the ERC-1271 branch when the configured signer is a contract. `KasuKycSigner` sits in
that slot and answers `isValidSignature` against the address derived from the AWS KMS signing key.
Rotating the key later is then one `setSigningKey` call per chain, with the allow list untouched.

`KasuKycSigner` is **not** behind a proxy — it holds one address of state and rotation is a plain
setter. If the contract itself ever needed replacing, `setNexeraIDSigner` gets pointed at a newly
deployed one.

## Scripts

| Script | Sends transactions? | What it does |
| --- | --- | --- |
| `deployKycSigner.ts` | Yes — one deploy tx | Deploys `KasuKycSigner(controller, signingKey)`, reads back `signingKey()`, smoke-checks `isValidSignature`, prints constructor args |
| `rotateKycSigner.ts` | **No** | Live-reads `txAuthDataSignerAddress()`, validates the target, writes the rotate + rollback Safe batches |

Both resolve every on-chain address from `.openzeppelin/<network>-addresses.json` by network name.
Neither reads `scripts/_config/chains.ts`.

## Per-network reference

| Network | Chain ID | RPC env var | `KasuController` | `KasuAllowList` | Explorer |
| --- | --- | --- | --- | --- | --- |
| `base` | 8453 | `BASE_RPC_URL` | `0xb0D7Eb2D5036fB85A231D0E243a5b723BA5D2868` | `0x807A7e119EBf0282420b5Ca0e0056c0525cBf8BB` | Etherscan V2 (Basescan) |
| `xdc` | 50 | `XDC_RPC_URL` | `0xe81D1C0E031da0E357928ED19aA1EbF6A2f5C904` | `0x32c1Ff5FbBe6D28503ddc46E5001C0D13d6E9B2A` | Etherscan V2 (`chainid=50`, XDCScan) |
| `xdc-usdc` | 50 | `XDC_RPC_URL` | `0xe76eE99fC85531857B9011C1D4223C7D1B591D60` | `0xaf911547FD38686a88fc26B2A722F870426bCD6D` | Etherscan V2 (`chainid=50`, XDCScan) |
| `plume` | 98866 | `PLUME_RPC_URL` | `0x7923837dC93d897E12696e0F4FD50b51FBacf693` | `0xef956C2193e032609da84bEc5E5251B28939b6B9` | Blockscout (`explorer.plume.org`) |

Signing key address (all four chains, KMS-derived, public half only):
`0xe99a7ec33cef5b09db5e7af9a9b0a648660244f6`. It is the default baked into `deployKycSigner.ts`;
`KYC_SIGNER_KEY_ADDRESS` overrides it.

Executing Safe — the holder of `ROLE_KASU_ADMIN` (`0x00`, i.e. `DEFAULT_ADMIN_ROLE`) on that chain's
`KasuController`: Base `0xC3128d734563E0d034d3ea177129657408C09D35`, XDC (both deployments)
`0x1E9ed74140DA7B81a1612AA5df33F98Eb5Ea0B4D`, Plume `0x344BA98De46750e0B7CcEa8c3922Db8A70391189`.
Confirm with a live read rather than trusting this table — pass `KASU_ADMIN_SAFE=0x...` to
`rotateKycSigner.ts` and it will check `hasRole` for you.

**XDC RPC:** use `https://rpc.primenumbers.xyz/`. Never `https://rpc.xdc.org` — it is unreliable for
forking and archive reads. Older docs and the `xdc` / `xdc-usdc` defaults in `hardhat.config.ts` still
name the old endpoint, so set `XDC_RPC_URL` explicitly on every XDC command below.

**`xdc` and `xdc-usdc` share `XDC_RPC_URL`.** A fork override set for one applies to the other, so
run the two deployments one at a time and re-export between them.

## Ordering constraint — read before touching anything

Rotation is **instant per chain**. The moment `setNexeraIDSigner` lands, every signature minted
against the old signer stops verifying, and every signature minted against the new one starts.
There is no dual-accept window.

So the sequence across the stack is:

1. **All frontends move to the backend signer service first.** Every app that requests KYC
   signatures (kasu-ui, fe-next, mobile) must already be calling the Kasu backend signer rather than
   Compilot's API, on every chain, deployed to production. A frontend still on the Compilot path when
   the rotation lands cannot deposit.
2. **Only then rotate**, chain by chain.

The reverse order — rotate first, migrate frontends after — takes the deposit gate down for the gap.

### The drained-signature window

Signatures carry a `blockExpiration`; `BaseTxAuthDataVerifier` reverts `BlockExpired` once
`block.number >= blockExpiration`. The backend mints with roughly a **300-block / ~10-minute**
horizon, whichever is longer on that chain's block time.

Around the rotation, that window is the blast radius: a user who fetched a signature just before
execution and submits just after will have it rejected (surfacing as `InvalidSignature`). Nothing is
lost — they retry and get a fresh signature — but:

- **Pause signature minting** for ~10 minutes / 300 blocks before executing, or execute in a low-traffic
  window, so the in-flight set is drained.
- Expect a small burst of failed KYC verifications in Sentry either side of the rotation; that is the
  window, not a regression.
- The same applies to a rollback.

## 1. Anvil dry-run (required)

Per the repo deployment workflow, every deploy dry-runs against an Anvil fork first. Fork the real
chain, point the hardhat network's RPC env var at the fork, and run the script unchanged.

```bash
# XDC AUDD
anvil --fork-url https://rpc.primenumbers.xyz/ --chain-id 50 --port 8546
XDC_RPC_URL=http://127.0.0.1:8546 \
  npx hardhat --network xdc run scripts/deploy/deployKycSigner.ts

# XDC USDC (same RPC var — restart/re-export, do not run concurrently with the above)
anvil --fork-url https://rpc.primenumbers.xyz/ --chain-id 50 --port 8546
XDC_RPC_URL=http://127.0.0.1:8546 \
  npx hardhat --network xdc-usdc run scripts/deploy/deployKycSigner.ts

# Base
anvil --fork-url https://mainnet.base.org --chain-id 8453 --port 8546
BASE_RPC_URL=http://127.0.0.1:8546 \
  npx hardhat --network base run scripts/deploy/deployKycSigner.ts

# Plume
anvil --fork-url https://rpc.plume.org --chain-id 98866 --port 8546
PLUME_RPC_URL=http://127.0.0.1:8546 \
  npx hardhat --network plume run scripts/deploy/deployKycSigner.ts
```

Keep `--chain-id` matching the real chain. `rotateKycSigner.ts` compares the RPC's chain ID against
`hardhat.config.ts` and warns loudly when they diverge, because a batch carrying the wrong chain ID
will not execute in the Safe.

Never run the dry-run with `DEPLOY_WRITE_ADDRESSES=true` — it would record a fork-only address into
the shared addresses file.

The dry-run passes when the script prints a deployed address, `signingKey() -> ... OK`, and
`isValidSignature(dummy) -> 0x00000000 OK`.

## 2. Deploy

```bash
# Base / Plume
npx hardhat --network <base|plume> run scripts/deploy/deployKycSigner.ts

# XDC — set the RPC explicitly, the config default is the bad endpoint
XDC_RPC_URL=https://rpc.primenumbers.xyz/ \
  npx hardhat --network <xdc|xdc-usdc> run scripts/deploy/deployKycSigner.ts
```

Needs `DEPLOYER_KEY` in `scripts/_env/.<network>.env`. The script refuses to run when the network
has no `KasuController` entry in its addresses file, or when that controller has no bytecode on the
chain behind the RPC.

Deploying changes nothing on its own — the allow list keeps verifying against Compilot until step 5.

Record the address. The `.openzeppelin/*-addresses.json` files are shared state, so the write is
opt-in:

```bash
DEPLOY_WRITE_ADDRESSES=true \
  npx hardhat --network <network> run scripts/deploy/deployKycSigner.ts
```

Without it the script prints the JSON fragment to paste under `"KasuKycSigner"` by hand. Commit that
change — `rotateKycSigner.ts` and every later operator read it from there.

## 3. Verify the source

The deploy script prints the exact command. Constructor args are `(kasuController_, signingKey_)`,
in that order — the controller for that network, then `0xe99a7ec33cef5b09db5e7af9a9b0a648660244f6`.

```bash
# Base / XDC / XDC USDC — Etherscan V2 multichain, single ETHERSCAN_API_KEY
ETHERSCAN_API_KEY=... npx hardhat verify --network <base|xdc|xdc-usdc> \
  <kycSignerAddress> <controllerAddress> 0xe99a7ec33cef5b09db5e7af9a9b0a648660244f6

# Plume — Blockscout, key not required
npx hardhat verify --network plume \
  <kycSignerAddress> <controllerAddress> 0xe99a7ec33cef5b09db5e7af9a9b0a648660244f6
```

On XDC, hardhat-verify 2.x submits successfully then fails the status check with
`Missing chainid parameter`. That is a known false negative — confirm directly:

```bash
curl -s "https://api.etherscan.io/v2/api?chainid=50&module=contract&action=getsourcecode&address=<ADDRESS>&apikey=<KEY>" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); r=d['result'][0]; print(r.get('ContractName','NOT VERIFIED') if d['status']=='1' and r.get('ContractName') else 'NOT VERIFIED')"
```

For Plume, check `https://explorer.plume.org/address/<ADDRESS>` shows the contract as verified.

If the name is reported ambiguous, add `--contract src/core/KasuKycSigner.sol:KasuKycSigner`.

## 4. Smoke the deployed contract

Read it directly on the explorer or with `cast`:

- `signingKey()` returns `0xe99a7ec33cef5b09db5e7af9a9b0a648660244f6`.
- `isValidSignature(<any digest>, <65-byte garbage>)` returns `0x00000000` — not a revert.
- The deploy transaction emitted `SigningKeyRotated(address(0), 0xe99a…44f6)`.

The positive ERC-1271 path cannot be exercised from a script — the private key lives in KMS. It is
covered by `test/unit/core/KasuKycSignerTest.sol`, which drives it through the real
`KasuAllowList.verifyUserKyc` path, and confirmed for real by the post-rotation deposit in step 6.

## 5. Generate and execute the Safe batch

```bash
KASU_ADMIN_SAFE=<kasu multisig> \
  npx hardhat --network <base|plume> run scripts/deploy/rotateKycSigner.ts

# XDC — again, set the RPC explicitly
XDC_RPC_URL=https://rpc.primenumbers.xyz/ KASU_ADMIN_SAFE=<kasu multisig> \
  npx hardhat --network <xdc|xdc-usdc> run scripts/deploy/rotateKycSigner.ts
```

Sends nothing. It prints the current on-chain signer, the target, the raw calldata, and writes two
files to `scripts/deploy/safe-batches/`:

- `<network>-kyc-signer-rotate.json` — `setNexeraIDSigner(<kycSigner>)`
- `<network>-kyc-signer-rollback.json` — `setNexeraIDSigner(<previous signer>)`

The rollback target defaults to whatever the allow list points at right now, so it restores the exact
pre-rotation state. Once the rotation has been applied it falls back to Compilot's
`0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0`. Override with `ROLLBACK_SIGNER_ADDRESS`.

Then, per chain:

1. Confirm the frontend precondition above still holds.
2. Upload `<network>-kyc-signer-rotate.json` to <https://app.safe.global> → Transaction Builder, from
   the Safe holding `ROLE_KASU_ADMIN`.
3. Check the decoded transaction against the calldata the script printed — one call, `to` = the allow
   list proxy, `setNexeraIDSigner`, `signer_` = the `KasuKycSigner` address.
4. Quiet the signature minting, wait out the ~10-minute / 300-block window, execute.

Do one chain at a time and complete step 6 before starting the next.

## 6. Post-rotation verification

Immediately after execution:

- `KasuAllowList.txAuthDataSignerAddress()` returns the `KasuKycSigner` address. Re-running
  `rotateKycSigner.ts` will print this and flag the batch as a no-op — the cheapest confirmation.
- `KasuKycSigner.signingKey()` still returns `0xe99a7ec33cef5b09db5e7af9a9b0a648660244f6`.
- **A real KYC'd deposit goes through end to end on that chain.** This is the only check that proves
  the ERC-1271 branch is live against the real KMS key; everything before it is a proxy for it.
- Watch Sentry and `#kasu-alerts` for KYC verification failures for the next 15 minutes. A short
  burst either side of execution is the drained-signature window; a sustained stream is a real
  failure — roll back.

## Rollback

`<network>-kyc-signer-rollback.json`, same Safe, same Transaction Builder. It is a single
`setNexeraIDSigner` call, so recovery is one transaction and takes effect immediately.

Rolling back has the same instant-cutover property in reverse: signatures minted against
`KasuKycSigner` stop verifying the moment it lands, so the frontends have to go back to the Compilot
path in the same window. If the rollback is because the frontends were never fully migrated, that is
already where they are.

Rolling back one chain does not affect the others — each deployment carries its own allow list.
