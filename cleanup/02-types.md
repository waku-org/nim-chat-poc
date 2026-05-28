# Cleanup 02 — Type consolidation (post-squash, 2026-05-28)

## Research notes

Re-scanned in-scope files after the May-28 squash. Earlier (pre-squash)
pass already folded the duplicated `MerkleNode`/`MembershipIndex`/
`ExternalMerkleProof` triplet and removed the adapter procs; this pass
verifies the merged state and checks the rest of the type surface.

Verified survey:

Nim (nwaku + plugin + outer):
- `vendor/nwaku/vendor/mix-rln-spam-protection-plugin/src/mix_rln_spam_protection/types.nim` — single home for `MerkleNode`, `MembershipIndex`, `IDCommitment`, `IDSecretHash`, `RateLimitProof`, `IdentityCredential`, etc.
- `vendor/nwaku/waku/waku_mix/logos_core_client.nim` — imports `mix_rln_spam_protection/types {.all.}` and `onchain_group_manager`; `export onchain_group_manager.ExternalMerkleProof`. No local re-aliases.
- `vendor/nwaku/vendor/mix-rln-spam-protection-plugin/src/mix_rln_spam_protection/onchain_group_manager.nim` — single home for `ExternalMerkleProof`, `FetchRootsCallback`, `FetchProofCallback`, `OnchainLEZGroupManager`.
- `vendor/nwaku/waku/waku_rln_relay/rln_gifter/rpc.nim` — single home for `MembershipAllocationSuccess/Failure`, `RlnGifterRequest/Response`, `MembershipStatusRequest/Response`. Consumed by `protocol.nim` (server), `client.nim` (client) and the gifter handler in `node_factory.nim`.
- `vendor/nwaku/waku/factory/node_factory.nim` — local `GifterJob` ref object, function-scoped. Not duplicated.

Rust (lez-rln): `AccountId`, `HashType` etc. come from the upstream LEZ SDK; not re-declared in our tree. `rln-layouts/src/*.rs` is the shared instruction/PDA layout module, already consumed by both host CLI and zkVM guests.

C++: `liblogos_rln_module_api.h` is byte-identical (md5 `4b7a51f2…`) across chat-module, delivery-module and logos-rln-module. Triplication is a Qt-plugin convention (each plugin ships its own public C API header); collapsing requires a shared-header repo or build-time symlink across three submodules — out of scope for type consolidation. `bytesToHex` exists only in `logos_rln_module.cpp`; chat-module/delivery-module use `QByteArray::toHex()` directly.

JSON shapes (ad-hoc string concat in `node_factory.nim`):
- `{"configAccountId":"…","userHoldingAccountId":"…","idCommitment":"…","rateLimit":N}` — 1 site (`gifterSubmitOnce`).
- `{"configAccountId":"…","idCommitment":"…"}` — 2 sites (`waitForChainCommit`, `statusHandler`).
Both already use agent-01's `bytesToHexUpper` for byte→hex. Rule-of-two only on the 2-field shape.

## Critical assessment

| Candidate | Verdict | Reason |
|---|---|---|
| `MerkleNode`/`MembershipIndex` shared | DONE in prior pass | `logos_core_client.nim` imports plugin's `types.nim`. No re-alias remains. |
| `ExternalMerkleProof` location | DONE in prior pass | Single definition in `onchain_group_manager.nim`, re-exported by `logos_core_client.nim`. |
| Gifter RPC records | DONE | All `MembershipAllocation*` / `MembershipStatus*` types live once in `rpc.nim`; both peers + handler import. |
| C++ `liblogos_rln_module_api.h` triplicate | SKIP | Out-of-scope build-system change (three separate submodules). |
| `is_member_registered` JSON 2-site dup | SKIP | 2 lines per site; extracting a typed param record would be net-zero and obscure the wire format. |
| `register_member` JSON 1-site | SKIP | Single use. |
| Rust `AccountId`/`HashType` | N/A | From upstream LEZ SDK, not duplicated in our tree. |

## Recommendations

1. **High confidence**: none. Type layer is already consolidated by prior passes; agent 01 verified the import wiring while extracting `bytesToHexUpper`.
2. **Deferred**: see below.

## Applied

No source edits this pass. The type surface is already minimal; nothing met the bar for a high-confidence change. Sim re-run to confirm baseline health for downstream agents.

## Deferred

- C++ `liblogos_rln_module_api.h` duplicated across three plugin submodules. Needs a shared-header repo or build-time symlink across submodules — leave for an infra pass.
- `is_member_registered` JSON 2-site shape in `node_factory.nim`. Each site is 2 lines; a typed param record would net to ~0 LoC change while obscuring the wire format. Revisit if a third call site appears.

## Commit SHAs

- Report-only this pass; no source changes in any repo.

## Sim result

(filled in after the run completes — see below)
