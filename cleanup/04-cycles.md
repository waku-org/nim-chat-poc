# Cleanup 04 — Circular Import / Dependency Cycles

Agent 04 of 8. Scope: cycles introduced or worsened by this session in `CLEANUP_SCOPE.md` files. Tooling: manual `rg`/`grep` over `^import` lines (madge n/a for this Nim/Rust/C++ stack).

## Research notes — import graph of in-scope clusters

### Cluster A — `waku_mix/logos_core_client.nim` ↔ plugin

```
logos_core_client.nim
  -> mix_rln_spam_protection/group_manager   {.all.}
  -> mix_rln_spam_protection/types           {.all.}
  -> mix_rln_spam_protection/rln_interface
  -> mix_rln_spam_protection/onchain_group_manager   (NEW: re-exports ExternalMerkleProof)

mix_rln_spam_protection/onchain_group_manager.nim
  -> ./types  ./constants  ./rln_interface  ./group_manager
  (zero references to waku_mix / nwaku / logos-chat)

mix_rln_spam_protection/{group_manager,types,rln_interface}.nim
  -> only sibling plugin modules + std/chronos/results/chronicles/stew
```

`rg 'logos_core_client|waku_mix' vendor/nwaku/vendor/mix-rln-spam-protection-plugin/` → 0 hits.

### Cluster B — `rln_gifter/` four-file cluster

```
rpc.nim         -> std/options                              (leaf)
rpc_codec.nim   -> std/options, ../../common/protobuf, ./rpc
protocol.nim    -> std/[options,sets], chronos/results/..., ../../node/peer_manager/peer_manager,
                   ../../waku_core, ./rpc, ./rpc_codec
client.nim      -> std/options, results, chronos, bearssl/rand, libp2p/stream/connection,
                   ../../node/peer_manager, ../../waku_core, ../../utils/requests, ./rpc, ./rpc_codec
```

Topological order: `rpc` < `rpc_codec` < {`protocol`, `client`}. `protocol` and `client` are siblings; neither imports the other. Strict DAG.

### Cluster C — callers of the new symbols

```
node_factory.nim   -> logos_core_client (alias mix_lez_client)
                   -> mix_rln_spam_protection/onchain_group_manager  (direct)
                   -> rln_gifter/protocol, rln_gifter/client          (direct)

src/chat/delivery/waku_client.nim
                   -> waku/waku_mix/logos_core_client as mix_lez_client
                   -> waku/waku_rln_relay/rln_gifter/{client,protocol}
                   -> mix_rln_spam_protection/{onchain_group_manager,rln_interface,spam_protection}
```

Both callers use `OnchainLEZGroupManager`, `FetchRootsCallback`, `FetchProofCallback`,
`MembershipIndex` via the `onchain_group_manager.X` qualifier. The direct plugin import is
necessary, not redundant with the `logos_core_client` re-export (which only re-exports
`ExternalMerkleProof`).

## Critical assessment

| Candidate                                                                                                   | Verdict   | Reason |
|-------------------------------------------------------------------------------------------------------------|-----------|--------|
| `logos_core_client` -> `onchain_group_manager` -> ... -> `logos_core_client`                                | SPURIOUS  | Plugin has zero references to nwaku/waku_mix. Forward edge only. |
| Plugin's `onchain_group_manager` reaching back into nwaku via new accessors (proofRoot/getPollInterval)     | SPURIOUS  | New procs operate on plugin-local state and types; no nwaku imports added. |
| rln_gifter `protocol` <-> `client` mutual import                                                            | SPURIOUS  | Neither imports the other; both depend only on `rpc`/`rpc_codec`. |
| rln_gifter `rpc_codec` <-> `rpc`                                                                            | SPURIOUS  | `rpc_codec` -> `rpc` only; `rpc.nim` imports only `std/options`. |
| `node_factory` importing both `mix_lez_client` and `onchain_group_manager` (redundant?)                     | SPURIOUS  | Caller uses multiple plugin-only symbols; re-export covers only `ExternalMerkleProof`. |
| `waku_client.nim` (outer) similar dual import                                                               | SPURIOUS  | Same reason as node_factory. |
| "typed as pointer to break a cyclic import" workaround marker (logos_core_client.nim:53)                    | OBSOLETE COMMENT | The pointer is the FFI callback ABI to C++ (`setGroupManagerRef(gm: pointer)`); cycle is no longer the real reason. Plugin doesn't import logos_core_client, so a typed ref *would* compile. But the opaque `pointer` is correct as an FFI boundary type; only the comment is misleading. |

## Recommendations

1. No real cycles to break. Import graph in scope is a clean DAG.
2. (Doc-only, deferred) Re-word `logos_core_client.nim:53` comment from "typed as pointer to break a cyclic import" to "typed as opaque pointer for the C++ FFI callback boundary". Strictly cosmetic; not worth a commit churn on this load-bearing file during cleanup pass. Suggested for whoever next edits that region.
3. The `ExternalMerkleProof` re-export from `logos_core_client` is genuinely useful for downstream consumers that don't already need the broader `onchain_group_manager` surface — but both current callers (`node_factory`, outer `waku_client`) need the broader surface anyway and can drop reliance on the re-export. Not worth changing; the re-export is harmless.

## Applied

No code changes. Mirrors verified byte-identical post agents 01-03:

```
3c3bd2e20ffa315e37a9c86c2002f8bbe5095e5e33e1df7c805cc41db5552d4c  vendor/nwaku/waku/waku_mix/logos_core_client.nim
3c3bd2e20ffa315e37a9c86c2002f8bbe5095e5e33e1df7c805cc41db5552d4c  vendor/logos-lez-rln/logos-delivery/waku/waku_mix/logos_core_client.nim
3c3bd2e20ffa315e37a9c86c2002f8bbe5095e5e33e1df7c805cc41db5552d4c  vendor/logos-lez-rln/logos-delivery-module/vendor/logos-delivery/waku/waku_mix/logos_core_client.nim
```

Re-validation after agents 01 (`bytesToHexUpper` extraction), 02 (type
consolidation no-op), and 03 (drop dead `hexToBytes32LE` + stale imports):

- Plugin (`mix-rln-spam-protection-plugin/`) still has zero references to
  `logos_core_client` / `waku_mix` — agents 01/03 only touched the nwaku
  side, never the plugin side. Edge direction preserved.
- `rln_gifter/` four-file cluster topology unchanged: `rpc` < `rpc_codec`
  < {`protocol`, `client`} remains a clean DAG; no sibling cross-import.
- Agent 03's unused-import removals (`std/sequtils` from `protocol.nim`,
  `waku_peer_store` from `protocol.nim`, `sharding` from
  `waku_mix_coordination.nim`, `std/algorithm` from `logos_core_client`)
  only reduce dependency surface — none introduced a new edge.
- C++ header graph: `liblogos_rln_module_api.h` (chat-module +
  delivery-module + logos-rln-module copies) includes only outward-facing
  `logos_api*.h` / `logos_mode.h` / `logos_object.h`. No back-edges from
  any included header to its consumers. Plugin source files form the
  expected unidirectional chain `*_plugin.cpp -> *_plugin.h ->
  *_module_interface.h -> interface.h`. Clean DAG.

Updated note also retracts the prior deferred "comment rewording at
`logos_core_client.nim:53`" item — the live file's comment (lines 53-57)
already explains the `pointer` as a cross-thread GC isolation
workaround, not a cycle workaround. Stale wording already gone.

No commits at any of the 5 repo levels.

## Deferred

- None. `madge` not applicable to Nim/Rust/C++ stack; manual `^import` /
  `^#include` survey across the in-scope file set is sufficient and was
  run twice (initial pass + post-01/02/03 re-validation).
