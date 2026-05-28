# Cleanup 05 — weak types

## Research notes

Grep across in-scope files for `pointer`, `void*`, `\bany\b`, `\bunknown\b`, `cast[`.

### Nim weak-type sites

| Site | Kind | File |
|---|---|---|
| `rlnGroupManager: pointer` (module global) | type erasure | `vendor/nwaku/waku/waku_mix/logos_core_client.nim:52` + L5 mirror |
| `setGroupManagerRef(gm: pointer)` | param erasure | same files :77 |
| `cast[GroupManager](gm)` | re-typing back | same files :112 |
| `cast[pointer](lezGm)` (3 call sites) | call-site erasure | `node_factory.nim:194` (nwaku + L5), `src/chat/delivery/waku_client.nim:338` |
| `cast[ptr FetchResult](userData)` (×2) | C callback userData | `logos_core_client.nim:181, 212` |
| `cast[cstring](methodCopy/paramsCopy)` | `allocShared0` → `cstring` | `logos_core_client.nim:266-267` |
| `RlnFetchCallback userData: pointer` / `fetcherData: pointer` | C ABI | `logos_core_client.nim:28-33` |

No `void*`, no `any`/`unknown` (Nim doesn't have those keywords in that sense). No other `cast[…]` in in-scope Nim.

### Rust FFI weak-type sites (`lez-rln-ffi/src/lib.rs`)

`*const u8` / `*mut u8` paired with explicit `len`/array-size; `unsafe { from_raw_parts(...) }` blocks reconstituting slices/fixed arrays (e.g. `&*(ptr as *const [u8; 32])`). All occurrences are inside `#[no_mangle] extern "C"` functions — they ARE the C ABI surface.

## Critical assessment

| Site | Verdict |
|---|---|
| `rlnGroupManager: pointer` global | **Justified — keep `pointer`, fix comment.** The original comment claims "break a cyclic import"; Agent 04 already confirmed no real import cycle exists (`logos_core_client.nim` directly imports `onchain_group_manager`). The Agent 04 hand-off also claimed `setGroupManagerRef` is the C++ FFI ABI — wrong: grep across the tree shows it has only three Nim callers and zero C/C++ callers. The actual reason `pointer` is correct here: the global is touched under `rlnFetcherLock` from threads other than the one that sets it (`callRlnFetcherAsync` spawns dedicated threads via `createThread`, and the C++ plugin invokes setters from its own thread). Storing a Nim `ref` in such a global subjects it to ORC/GC interference across thread boundaries. Erasing to `pointer` is the standard Nim pattern for cross-thread handle storage. |
| `setGroupManagerRef(gm: pointer)` + `cast[pointer](lezGm)` call sites + `cast[GroupManager](gm)` | **Justified consequence of the global's type.** If the storage is `pointer`, the setter must be `pointer` and the getter must `cast` back. Nothing to win by replacing the call-site `cast[pointer](lezGm)` with a one-liner converter. |
| `cast[ptr FetchResult](userData)` | **Justified — standard C-callback userData pattern.** `userData` is a `pointer` opaque payload by C ABI; the cast back is the only way to recover the typed `FetchResult`. |
| `cast[cstring](allocShared)` | **Justified.** `allocShared0` returns `pointer`; we need a `cstring` view of the buffer to pass through the C ABI. |
| `pointer` in `RlnFetchCallback`/`RlnFetcherFunc` (`callbackData`, `userData`, `fetcherData`) | **Justified — C ABI.** These are `{.cdecl.}` callbacks invoked from C. |
| Rust `*const u8` / `*mut u8` + `unsafe { from_raw_parts }` in `lez-rln-ffi/src/lib.rs` | **Justified — C ABI surface.** Every site is inside an `extern "C"` function. Tightening to `&[u8]` would break the FFI signature consumed by C++ in `logos-rln-module` (out of scope). The `unsafe { &*(ptr as *const [u8; 32]) }` already tightens what it can (raw ptr → typed fixed-array ref) immediately after entry. |

## Recommendations

The only fixable issue is the **misleading comment** on `rlnGroupManager: pointer`. Rewrite it to reflect the true reason (cross-thread storage avoiding GC tracking). The pointer type itself stays; the casts stay.

No new Nim/Rust types are introduced — wrapping `pointer` in an opaque typed handle would not prevent any bug (the same module owns the only writer and the only reader, and the cast target type is unambiguous).

## Applied

- L5 `vendor/logos-lez-rln/logos-delivery` — commit `6e377054` on `feat/sim-rln-gifter-auth-debug`
  - `waku/waku_mix/logos_core_client.nim`: replace `## …break a cyclic import…` doc-comment with accurate 4-line rationale.
- L2 `vendor/nwaku` — commit `9ce6dee9` on `feat/sim-rln-gifter-auth`
  - Same change, mirrored.

L1 (outer `logos-chat`), L3, L4 not touched (no candidates required fixing in-scope).

### Verify

- `make liblogoschat` — built OK (exit 0).
- `make liblogosdelivery` (under `vendor/logos-lez-rln/logos-delivery`) — built OK (exit 0).
- Simulation skipped: this commit is comment-only; no codegen, no runtime path, no symbol surface change. The build success above is sufficient. Main session can run the fallback sim if it wants confirmation.

## Deferred

- None. Every weak-type site was assessed and found justified except for the misleading comment, which has been corrected.
- The `OnchainLEZGroupManager`/`GroupManager` typed-wrapper idea (an opaque `distinct pointer` handle) was considered and rejected: it would buy zero safety (the same module is the only writer/reader) and would force every call site through a converter without removing the underlying erasure.

## Re-validation pass (Agent 05, sequential 8-agent run)

Re-walked the in-scope file list after agents 01-04. Confirmed:

- `vendor/nwaku/waku/waku_mix/logos_core_client.nim`: 05B fixes present in code (`setGroupManagerRef*(lezGm: OnchainLEZGroupManager)`, `cast[OnchainLEZGroupManager](gm)` in `setRlnIdentity`, accurate cross-thread-storage comment on the `pointer` global). Both casts at the global boundary remain justified.
- `library/declare_lib.nim` + `library/api/client_api.nim`: every `pointer` is C-ABI callback userData. Justified — no change.
- C++ `void*` / `QVariant` in `chat_module_plugin.h`, `delivery_module_plugin.cpp`, `liblogos_rln_module_api.h`: all dictated by Qt-Remote-Objects `invokeRemoteMethod` (returns `QVariant`) and the nwaku C callback signature (`(int, const char*, size_t, void*)`). Already wrapped by `liblogos_rln_module_api.h` helpers where a typed view is possible. No further tightening without breaking the QtRO/FFI surface.
- Rust `*const u8` in `lez-rln-ffi`: every site inside `extern "C"`. C ABI, not fixable.

No new edits applied this pass. Nothing to commit. Builds not re-run — no code changed.
