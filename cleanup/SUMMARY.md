# Cleanup pass summary (post-squash, 2026-05-28)

Eight-agent code-quality sweep over the consolidated LEZ+RLN+mix+gifter+sim work. Scope, methodology, and per-agent reports in this directory (`01-dry.md` through `08-slop.md`). Pre-cleanup safety tag at each repo: `prefullsquash-2026-05-28`. Prior cleanup pass (pre-squash) summarised at `SUMMARY-2026-05-21.md`.

## Per-agent results

| # | Agent | Verdict | New commits | Surface change |
|---|---|---|---|---|
| 01 | DRY | applied | nwaku `d08083c5`, loose delivery `9240b8d0` | extracted `bytesToHexUpper*` to `logos_core_client.nim`; collapsed 3 idCommitment hex loops in `node_factory.nim`. Net −4 lines + clarity gain. |
| 02 | Types | report-only | — | Type layer already consolidated by prior pass: `MerkleNode`/`MembershipIndex`/`ExternalMerkleProof` single-home in plugin's `types.nim` + `onchain_group_manager.nim`; gifter RPC records single-home in `rpc.nim`. |
| 03 | Unused | applied | nwaku `1353d42d`, canonical+loose delivery `574cd9a7`/`227dd67f` | Removed `confirmMembershipLeafIndex`, several unused imports, duplicate kademlia conf wiring. Net −15 lines × 3 mirrors. |
| 04 | Cycles | report-only | — | Import graph is a clean DAG. Plugin→nwaku is forward-only; rln_gifter cluster topology is `rpc → rpc_codec → {protocol, client}` with no sibling cross-imports. |
| 05 | Weak types | report-only | — | Every remaining weak-type site sits at a hard ABI/framework boundary (C cdecl callbacks, QtRO `QVariant`, cross-thread GC-isolated `rlnGroupManager: pointer`). All justified. |
| 06 | try/except | applied | outer `f6dbb46`, nwaku `b70db9ac`, plugin `2ca5b2b`, canonical delivery `90ab4d97` | Narrowed silent `except CatchableError: continue` to typed `JsonParsingError`/`JsonKindError` with logging in `node_factory.nim:waitForChainCommit`; added `CancelledError: return` carve-outs in self-reg watcher; removed unreachable try/except wrappers around `{.raises: [].}` callbacks in plugin's `pollLoop`. |
| 07 | Legacy/fallback | report-only | — | The legacy targets (old RPC-shape else-branch in `onchain_group_manager.nim`, gifter self-reg DEBUG instrumentation) had already been removed in the pre-squash pass and survived the squash+rebase. |
| 08 | AI slop | report-only | — | Comment compression from the pre-squash pass survived into HEAD; remaining comments all pin non-obvious WHY (race-condition rationale, propagation cushion, cross-thread UB, etc.) and meet the keep-criteria. |

## End-of-pass verification

```
SIM_NETWORK=local ./simulations/mix_lez_chat/run_simulation.sh --fresh
→ ALL 15 CHECKS PASSED
```

Build chain clean: `liblogoschat` ✓ , `liblogosdelivery` ✓.

## Final repo tips

| Repo | Branch | Tip |
|---|---|---|
| outer logos-chat | `feat/sim-rln-gifter-auth-v2` | `f6dbb46` |
| vendor/nwaku | `feat/sim-rln-gifter-auth` | `b70db9ac` |
| vendor/logos-lez-rln | `feat/eip191-gifter-auth` | `950f287` (no cleanup changes) |
| vendor/logos-lez-rln/logos-delivery-module | `feat/logos-delivery-v2` | `680eaff` (no cleanup changes) |
| canonical / loose `logos-delivery` | `feat/sim-rln-gifter-auth-debug` | `90ab4d97` |
| vendor/nwaku/vendor/mix-rln-spam-protection-plugin | `cleanup` | `2ca5b2b` |
| logos-chat-module | `feat/logos-delivery-v2` | `7aecb1e` (no cleanup changes) |

All cleanup commits pushed `--force-with-lease` to their respective feature branches.

## Deferred (not blocking)

- C++ `liblogos_rln_module_api.h` triplicated across three Qt plugin submodules (chat-module, delivery-module, logos-rln-module). Requires a shared-header repo or build-time symlink across submodules — out of scope for type consolidation, belongs in a build-infra pass.
- `vendor/nwaku/apps/chat2mix/` + `vendor/nwaku/simulations/mixnet/` are superseded by the chat-module + logoscore stack but still wired into Make targets and `build_all.sh`. Removal is a multi-repo refactor, not a one-file unused-code edit.
- `is_member_registered` JSON 2-site param shape in `node_factory.nim` — extracting a typed param record would net to ~0 LoC while obscuring the wire format; revisit if a third call site appears.
