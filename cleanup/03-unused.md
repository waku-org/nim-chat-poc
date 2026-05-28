# Cleanup 03 — Unused code (post-squash re-pass, 2026-05-28)

The prior 03-unused.md in this file reflected a pre-squash session whose
SHAs (`a3826a65`, `0b2a5398`, `286cce8`) no longer exist on the current
branches. Those removals (`confirmMembershipLeafIndex`,
`RegisterMemberFunc` + slot wiring) are nonetheless absorbed into the
squashed feature commits — `rg` for those symbols returns 0 hits
anywhere in the in-scope trees. This pass re-audits the post-squash
state.

## Research notes

Ran `nim check --hints:on --warnings:on` on every in-scope nwaku file
plus the outer chat sources. Filtered hints/warnings to in-scope files
only (upstream-file warnings ignored). Cross-checked candidate removals
with `rg` across all five repos.

### True positives

| Symbol / Import | File | Verdict |
|---|---|---|
| `proc hexToBytes32LE` | `vendor/nwaku/waku/waku_mix/logos_core_client.nim:310` | **UNUSED** — zero callers anywhere. Sole consumer (LE path) was replaced by `hexToBytes32` + caller-side reversal during the migration. |
| `import std/algorithm` | same file | **UNUSED** — `reverse` only referenced by the dead `hexToBytes32LE`. |
| `import std/sequtils` | `vendor/nwaku/waku/waku_mix/protocol.nim:3` | **UNUSED** — no `mapIt`/`filterIt`/`toSeq` left in module. |
| `import waku_peer_store` | `vendor/nwaku/waku/waku_mix/protocol.nim:21` | **UNUSED** — `WakuPeerStore` not referenced. |
| `import ../waku_core/topics/sharding` | `vendor/nwaku/waku/node/waku_mix_coordination.nim:10` | **UNUSED** — `RelayShard`/`ShardId` not referenced. |
| Duplicate `kademliaDiscoveryConf.with*` block | `vendor/nwaku/tools/confutils/cli_args.nim:1192-1193` | **DEAD-CODE BUG** — identical 2-line block appears earlier (lines 1168-1169). Both run on every `toWakuConf` call; second one is purely redundant. Introduced by our squash. |

### False positives investigated and rejected

- `hexToBytes32LE`-style — none others.
- `import std/sequtils` in `waku_kademlia.nim` flagged by `nim check`, but `mapIt` is actually used at line 126; build fails without it. **Reverted.**
- `extractMixPubKey` in `waku_kademlia.nim` flagged unused but invoked from same file in async closure context (`mixPubKey = extractMixPubKey(service)`). Hint is wrong.
- `req` in `gifter/client.nim queryMembershipStatus` flagged unused but its `.encode()` is awaited in `connection.writeLP(req.encode().buffer)`. Hint is wrong.
- Candidates from task brief that turned out to be **live and load-bearing**:
  - `tools/confutils/cli_args.nim` — used by `wakunode2`, `liblogosdelivery`, `chat2mix`, and several tests. Only the duplicate-line dead block was cut.
  - `apps/chat2mix/*` — still wired via `Makefile` (`chat2mix:` target), `waku.nimble` (`task chat2mix`), and downstream `vendor/logos-lez-rln/build_all.sh` (`make chat2mix`). Replacing it with the chat-module + logoscore stack is a larger refactor and out of scope for an unused-code pass.
  - `simulations/mixnet/*` — older bare-mix sim, referenced by `README` only; not invoked by `simulations/mix_lez_chat/run_simulation.sh`. Removing would orphan `apps/chat2mix` too. Deferred along with chat2mix.
  - `tests/waku_rln_relay/test_rln_gifter.nim` — included in `tests/waku_rln_relay/test_all.nim`. **Live.**
- Rust: `cargo build` on `lez-rln/` workspace produced zero unused warnings.
- C++: chat-module and delivery-module sources are minimal; no obviously dead exports surfaced.

## Critical assessment

The squash already absorbed the prior session's bigger removals
(`confirmMembershipLeafIndex`, `RegisterMemberFunc`). What remained
was a handful of stale imports and one defensive dup that snuck through
during the gifter wiring. All five surviving items are mechanical and
safe — none touch FFI exports or cross-repo symbols.

## Applied

In `vendor/nwaku` (mirrored to both `logos-delivery` checkouts):

- `waku/waku_mix/logos_core_client.nim`: remove `proc hexToBytes32LE` (9 lines) + drop `algorithm` from std import.
- `waku/waku_mix/protocol.nim`: drop `sequtils` from std import, drop `waku_peer_store` import.
- `waku/node/waku_mix_coordination.nim`: drop `../waku_core/topics/sharding` import.
- `tools/confutils/cli_args.nim`: remove the duplicate `kademliaDiscoveryConf.withEnabled / withBootstrapNodes` pair at end of `toWakuConf`.

Net: −15 lines per repo × 3 mirrors. Builds clean: `liblogoschat` ✓, `liblogosdelivery` ✓.

### Commit SHAs

- `vendor/nwaku` (feat/sim-rln-gifter-auth): `1353d42d`
- `vendor/logos-lez-rln/logos-delivery` (feat/sim-rln-gifter-auth-debug, loose): `574cd9a7`
- `vendor/logos-lez-rln/logos-delivery-module/vendor/logos-delivery` (feat/sim-rln-gifter-auth-debug, canonical): `227dd67f`
- outer logos-chat / lez-rln / delivery-module / chat-module / mix-rln plugin: no source changes this pass.

## Deferred

- **`apps/chat2mix/` + `simulations/mixnet/`** — superseded by the chat-module + logoscore stack used in `simulations/mix_lez_chat/`, but still wired into Make targets and the lez-rln `build_all.sh`. Removal is a multi-repo refactor (Makefile, waku.nimble, build scripts), not an unused-code edit. Worth a dedicated pass.
- **`liblogos_rln_module_api.h` triplicate** — flagged by agent 02 as a build-infra issue; same triplication still present but not under "unused code".
- Several `XDeclaredButNotUsed` hints inside `async` procs (`req`, `extractMixPubKey`) are nim-check false positives caused by closure transformation. Left as-is.

## Sim result

(filled in after the run completes below)
