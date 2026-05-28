# Mode A — per-signer nonce collision in the gifter's wallet submission path

**Status:** Open. Root cause identified and reproduced locally on 2026-05-27. Fix sits in the LEZ wallet (`lssa/wallet/`), not in the gifter, not in the chat sender, not in the on-chain `Register` handler.

**Captured evidence:**
- Local reproduction (this session): `/tmp/sim_state_local_NONCE_REPRO/` — full end-to-end repro with `sequencer.log` containing 4 `"Nonce mismatch"` rejections.
- Testnet failures: `/tmp/sim_state_testnet_postfix/`, `/tmp/sim_state_cleanwallet/`.

## TL;DR

When the gifter fires several `register_member` calls within a single sequencer block window, **all of them fetch the same chain-side nonce N**, sign with N, and submit. The first commits and the signer's nonce advances to N+1; the remaining 2–4 fail `validate_on_state` with `"Nonce mismatch"` and are silently dropped at the sequencer (logged but not returned to the caller). The wallet has no per-signer nonce serialization, the mempool has no dedup, and `get_transaction(tx_hash)` cannot distinguish "rejected" from "still pending."

Consequence: `tree_main.next_index` advances by ~1 per block window instead of by the number of submissions. Every requester's `register_member` keeps reading the same stale `next_index` (because the chain genuinely hasn't moved past it) and keeps returning the same optimistic `leaf_index`. Each client's gifter-status watcher polls `is_member_registered`, which keeps returning `false` (the chain never wrote their PDA). The chat-sender's 180 s confirmation deadline expires, it publishes against the optimistic-but-incorrect leaf, the rln crate computes a proof root from `(pathElements_for_someone_else, our_creds)`, and self-verify rejects with `rootInOurWindow=false`.

The duplicate `leaf=6` / `leaf=178` readings in earlier captures are **symptoms** of zero registrations committing, not evidence of a gifter slot-allocator defect. The on-chain Register handler reads `tree_main.next_index` from live state and serializes correctly when txns commit — confirmed by sequencer-core re-execution model (`sequencer/core/src/lib.rs:243-254`).

## Reproduction (local, deterministic)

The local sim's default config (`vendor/logos-lez-rln/lssa/sequencer/service/configs/debug/sequencer_config.json`: `max_num_tx_in_block=20`, `block_create_timeout="15s"`) **masks** the bug because all concurrent registrations pack into a single block — they get distinct nonces from `get_accounts_nonces` between blocks and each commits at the right slot.

To expose the race, widen the block window past the natural registration cadence:

```jsonc
"max_num_tx_in_block": 1,        // force one tx per block
"block_create_timeout": "90s"    // longer than the ~25-30s gap between mix-node registrations
```

Then:

```bash
SIM_NETWORK=local ./simulations/mix_lez_chat/run_simulation.sh --fresh
grep -E "Nonce mismatch" simulations/mix_lez_chat/.sim_state/sequencer.log
```

This is a diagnostic-only change. **Do not commit it.**

## Evidence

### 1. Local reproduction (this session, 2026-05-27 17:48 UTC)

`sequencer.log`:
```
[17:51:00 ERROR sequencer_core] Transaction with hash 6b69eb67… failed execution check with error: InvalidInput("Nonce mismatch"), skipping it
[17:51:00 ERROR sequencer_core] Transaction with hash 17d209c5… failed execution check with error: InvalidInput("Nonce mismatch"), skipping it
[17:51:00 ERROR sequencer_core] Transaction with hash c33c7543… failed execution check with error: InvalidInput("Nonce mismatch"), skipping it
[17:52:30 ERROR sequencer_core] Transaction with hash 12e9bcc7… failed execution check with error: InvalidInput("Nonce mismatch"), skipping it
```

`node0.log` (gifter) — leaf returned per request:
```
11:48:11  Gifter self-registered                       leafIndex=0
11:48:33  RLN gifter registration succeeded            leafIndex=0  requestId=cd6dd33…
11:48:57  RLN gifter registration succeeded            leafIndex=0  requestId=40b442b…
11:49:22  RLN gifter registration succeeded            leafIndex=0  requestId=0740625…
11:50:20  RLN gifter registration succeeded            leafIndex=1  requestId=ea051b2…  ← block window rolled
11:50:54  RLN gifter registration succeeded            leafIndex=1  requestId=cf37418…
```

Four requesters got `leaf=0`, then the next block let exactly one tx commit (advancing to leaf=1), and the next two requesters again collided on leaf=1. End-to-end the chat sender's failure was the canonical Mode A:

`chat_sender.log`:
```
11:50:54  RLN membership granted                       leafIndex=1
11:54:05  WRN Membership confirmation did not arrive within deadline
11:54:25  ERR Self-verify of generated proof errored
              err="Verification error: Expected one of the provided roots"
              proofRoot=28c9607887077a3c…  rootInOurWindow=false
11:54:40  ERR Failed to publish via mix
              err="…mix send failed: Failed to generate spam protection proof…"
```

Tally: 1 FAILED, 14 passed. Identical signature to the testnet captures.

### 2. Pre-clean-wallet testnet failure (`/tmp/sim_state_testnet_postfix/`)

Five requesters all got `leafIndex=178`; 6 unrelated `KeyNotFoundError` lines in node0 from a stale `~/.logos-lez-rln/payment_account_*.txt` (separate environmental bug — sidecar staleness, see "Environmental footguns" below). Even when that was fixed, the slot-collision pattern persisted.

### 3. Post-clean-wallet testnet failure (`/tmp/sim_state_cleanwallet/`)

Five requesters all got `leafIndex=6`; zero `KeyNotFoundError`; same `Self-verify ... rootInOurWindow=false` self-verify rejection on the chat sender; same 180 s confirmation timeout.

## Code path

### Wallet — refetches nonce every call, no cache

`vendor/logos-lez-rln/lssa/wallet/src/lib.rs:294-326` — `send_public_transaction`:

```rust
// line 301-304
let nonces = self.sequencer_client.get_accounts_nonces(vec![signer]).await?;
let signer_nonce = nonces.get(&signer).copied().unwrap_or(0);
```

Nonce is fetched fresh from the sequencer on every call. No local cache, no auto-increment, no awareness of in-flight submissions.

### Mempool — no per-signer dedup

`vendor/logos-lez-rln/lssa/mempool/src/lib.rs:1-61` — plain async queue. `send_transaction` does a stateless signature check (line 67), then pushes into the FIFO buffer. Two txns from the same signer with the same nonce both accepted into the mempool.

### Sequencer — silent drop with logged-only feedback

`vendor/logos-lez-rln/lssa/nssa/src/validated_state_diff.rs:73-78` (public tx) and `:340-344` (privacy-preserving) — `validate_on_state` enforces `current_nonce == *nonce`; mismatch returns `Err(InvalidInput("Nonce mismatch"))`.

`vendor/logos-lez-rln/lssa/sequencer/core/src/lib.rs:243-254` — on validation error during block building, sequencer logs `"Transaction with hash {tx_hash} failed execution check with error: ..., skipping it"` and silently continues to the next mempool entry. The rejected tx is consumed from the mempool; **no notification flows back to the submitter.**

### Status polling — cannot distinguish dropped from pending

`vendor/logos-lez-rln/lssa/wallet/src/poller.rs:33-64` — `get_transaction(tx_hash)` returns `Ok(tx)` only if the tx is found in a committed block. Otherwise after polling timeout: `bail!("Transaction not found")`. A nonce-rejected tx and a still-pending tx are indistinguishable from the client's perspective.

### Gifter — submit-and-return-optimistic

`vendor/logos-lez-rln/logos-rln-module/src/logos_rln_module.cpp:316-486` — `register_member`:

1. Read `tree_main` (line 367-371).
2. `rln_ffi_register_plan` → `plan.next_leaf_index` (line 376-388). This is `tree_main.next_index` at read time.
3. Build instruction (line 425-437). The instruction itself carries only `tree_id, id_commitment, rate_limit, subtree_id` — **no `leaf_index`**; the on-chain handler derives it from live state.
4. Submit via wallet — fire-and-forget (line 462-469).
5. Return `plan.next_leaf_index` to caller, with `pending: true`.

The in-line comment at line 471-484 is candid that `plan.next_leaf_index` is "a pre-submit snapshot — it can be wrong if our tx loses a race." What that comment did not anticipate is that the more common failure mode is the tx not committing at all (silent nonce drop), not the tx committing at a different slot.

### Note on the on-chain side (where there is **not** a bug)

The Register handler reads `tree_main.next_index` from live state and assigns a leaf at execution time. The sequencer re-executes each public tx serially against the current state (`sequencer/core/src/lib.rs:243-254`). When two registrations commit sequentially, they get distinct leaves automatically — no program-level CAS is needed.

There is a narrow latent correctness hole at subtree boundaries: `plan.subtree_account_id` is part of the tx's account list and is derived from the planned leaf, so if a registration is retried after the chain has crossed a subtree boundary, the account list points at the wrong subtree account and the tx will fail. This is a separate, lower-priority concern from the nonce bug — flagged here for follow-up but **not** the cause of the current Mode A failures.

## Why the existing mitigations don't close it

| Layer | Mitigation | Why it's insufficient |
|---|---|---|
| Chat sender — Phase 1 cushion | Wait `2 × pollInterval` after `markMembershipConfirmed()` | If `is_member_registered` never returns true (because the tx was nonce-dropped, never committed), the 180 s deadline expires and sender publishes anyway. |
| Chat sender — Phase 2 root-stability gate | Wait until `proofRoot()` is in rootTracker for `stableMs` | Tracks `cachedProof.root` for our optimistic `membershipIndex`. If that index belongs to someone else's commitment (or to no one — slot empty), `cachedProof` is still set to *some* root and Phase 2 passes. |
| Watcher background poll | Poll `is_member_registered` every 30 s, fire `onConfirmed` | Useless when the chain never wrote our PDA because our submitting tx was nonce-dropped. |
| `register_member` idempotency precheck | Skip resubmit if PDA already populated | Only handles **re-registration**, not first registration. |
| `Self-verify` in `spam_protection.generateProof` | Reject the proof locally when `rootInOurWindow=false` | Catches the symptom (we shipped this earlier in the session and it correctly fails fast). Doesn't recover the send. |
| Visibility fixes shipped this session | Surface `mix send failed` in chat sender logs | Turns a silent 14/15 into a visible 14/15. Doesn't change the failure rate. |

All these mitigations assumed a benign "leaf was reassigned" race that the watcher would clean up. The actual mechanism is "the tx never committed in the first place," which renders each mitigation a no-op.

## Recommended fixes — in priority order, in the right layer

### A. Wallet-side per-signer nonce serialization (smallest correct fix)

`vendor/logos-lez-rln/lssa/wallet/src/lib.rs:294-326` — replace the bare `get_accounts_nonces` refetch with:

1. Maintain a per-signer `nextNonce: Map<Signer, u64>` in wallet state.
2. On `send_public_transaction`: `let nonce = max(chain_nonce_for_signer, nextNonce[signer]); nextNonce[signer] = nonce + 1`.
3. After tx confirmation (success or failure): reconcile `nextNonce[signer]` against the chain's authoritative nonce — on rejection, decrement and let the caller retry; on commit, advance only if needed.

Trade-off: wallet becomes stateful. On restart it can rebuild `nextNonce` from chain by re-fetching once per signer. Lost in-flight txns become rejections that the caller has to retry — which requires (B).

### B. Surface tx-status distinguishably

`vendor/logos-lez-rln/lssa/wallet/src/poller.rs` + an additive sequencer RPC: have `get_transaction(tx_hash)` return one of `{committed(block), pending, rejected(reason)}`. The sequencer already logs the rejection reason at `sequencer/core/src/lib.rs:243-254` — that information just needs to flow back instead of being log-only. Without this, even a wallet that knows it should retry has no signal to act on.

### C. Gifter retry on nonce rejection (after A+B land)

Once the wallet can detect a rejected submission, the gifter's `register_member` can re-submit transparently: refetch the chain nonce, rebuild the instruction (the `plan.next_leaf_index` will have advanced), and retry. Wraps the existing fire-and-forget into a confirm-or-retry loop. Keeps the client-side optimistic flow simple.

### Strike-through: gifter-side optimistic counter

An earlier draft of this doc proposed a gifter in-process `Map<id_commitment, leaf_index>` counter to hand out distinct optimistic leaves. **This was wrong.** It would print nicer-looking leaf numbers while the underlying tx submissions continue to silently drop. The chain wouldn't advance any faster, `is_member_registered` would still return `false`, and Mode A would persist. The fix has to address the actual submission failure, not the cosmetic returned value.

## Environmental footguns hit during this investigation

Documented for the next session — not related to the nonce bug but cost a couple of failed runs to diagnose:

1. **Stale `~/.logos-lez-rln/payment_account_<TREE_ID>.txt`** caused `KeyNotFoundError` on every gifter `send_public_transaction` against testnet. The sim's `seed_copy` (`simulations/mix_lez_chat/run_simulation.sh:226-247`) has a `[ -f "$dst" ] && return 0` guard, so once a stale sidecar is cached it never gets refreshed. Workaround: `rm ~/.logos-lez-rln/payment_account_*.txt ~/.logos-lez-rln/supply_holding_*.txt vendor/logos-lez-rln/testnet/storage.json vendor/logos-lez-rln/testnet/wallet_config.json` before re-running. Cleaner fix: change the guard to refresh when the shipped source is newer than the cached destination.

2. **Stale dylib path mismatch** between loose `vendor/logos-lez-rln/logos-delivery/build/` and canonical submodule path `vendor/logos-lez-rln/logos-delivery-module/vendor/logos-delivery/build/`. Documented in `cleanup/FRESH_CLONE_RESULTS.md`'s caveat section.

## Open questions / follow-ups

1. **Confirm against hosted testnet.** The local repro mechanism is identical to what we'd see on testnet (same wallet + sequencer code path). But because we cannot reach the hosted testnet's sequencer logs, we can't directly observe the `"Nonce mismatch"` lines there. One way to close the loop: add a temporary log line in the gifter's `register_member` that records the tx_hash returned by `send_public_transaction`, then add a follow-up `get_transaction(tx_hash)` poll right after submission to detect commit-vs-not. If testnet runs show that none of the gifter's tx_hashes ever appear committed, the nonce hypothesis is corroborated.

2. **Subtree-boundary retry-time hole.** Mentioned above — the planned `subtree_account_id` is leaf-dependent. A retry after the tree has grown past a subtree boundary will submit a tx whose account list points at the wrong subtree. Independent of the nonce bug, but worth catching before the LEZ user count grows past the first few subtree boundaries.

3. **Per-signer mempool ordering.** Even after wallet-side nonce serialization, two `register_member` calls submitting from the same signer back-to-back may land in the mempool in arbitrary order if the wallet doesn't preserve submission order. The sequencer drains mempool FIFO, so out-of-order arrivals with sequentially-advanced nonces would all fail validation. A wallet fix needs to either (a) preserve order on submission or (b) batch into a single transaction.

## What this session shipped

The following commits are independent of the nonce bug — they make Mode A *visible* instead of silent, which is what enabled this investigation. Worth keeping regardless of how/when the wallet fix lands:

- `692a467` `fix(chat): surface sendBytes errors instead of swallowing via discard`
- `d36cee09` `fix(lightpush): surface mix-dialer write failures as Result error` (in `vendor/nwaku`)
- `a555e5f` `chore: bump nwaku to surface mix-dialer write failures`
- `49dbb22` `fix(chat): timeout mix lightpush so vanished-reply hangs surface as Err`

Without these, the local repro would have hung or silently passed 14/15 with no explanatory error line, and the testnet captures would not have surfaced the `Self-verify ... rootInOurWindow=false` pattern that pointed us at the right layer.
