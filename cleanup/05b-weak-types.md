# Cleanup 05B — Weak types re-evaluation

Follow-up to `05-weak-types.md`. Cleanup Agent 05's verdict was "everything justified, only the doc-comment is fixable". Re-examination found one site Agent 05 dismissed too quickly.

## Push-back assessment

| Site Agent 05 dismissed | New verdict | Why |
|---|---|---|
| `cast[pointer](lezGm)` at the three call sites | **FIXABLE** | Agent 05 framed this as "consequence of the global being `pointer`". Correct premise, wrong conclusion. The PUBLIC SURFACE of `setGroupManagerRef` doesn't need to be `pointer` — it can take the concrete `OnchainLEZGroupManager` and erase to `pointer` internally for the lock-protected global. Removes 3 `cast[pointer]` from caller sites with no semantic change. |
| `cast[GroupManager](gm)` in `setRlnIdentity` | **FIXABLE** | Agent 05 left this alone. The cast was to the *base* `GroupManager` type even though every caller stashes an `OnchainLEZGroupManager`. Narrowing the cast target to the concrete subtype is type-honest and free. |
| `rlnGroupManager: pointer` global itself | **AGREE, keep `pointer`** | Cross-thread lock-protected global; Nim `ref` storage there risks GC interference. Agent 05 was right. |
| `cast[ptr FetchResult](userData)` | **AGREE, keep** | C-callback userData pattern. |
| `cast[cstring](allocShared0(...))` | **AGREE, keep** | `allocShared0` returns `pointer`; the `cstring` cast is the typed view. |
| `pointer` in `RlnFetchCallback` / `RlnFetcherFunc` (`callbackData`, `fetcherData`) | **AGREE, keep** | `{.cdecl.}` callbacks invoked from C. |
| Rust `*const u8` in `lez-rln-ffi/src/lib.rs` | **AGREE, keep** | C ABI surface. |

## Applied

- `vendor/nwaku/waku/waku_mix/logos_core_client.nim`:
  - `setGroupManagerRef*(gm: pointer)` → `setGroupManagerRef*(lezGm: OnchainLEZGroupManager)`. Internal `cast[pointer](lezGm)` does the erasure for the cross-thread global.
  - `setRlnIdentity` casts back to `OnchainLEZGroupManager` (the concrete subtype that every caller actually stashes) instead of `GroupManager`.
  - Comment on `rlnGroupManager: pointer` updated accordingly (mentions `OnchainLEZGroupManager`).
- `vendor/nwaku/waku/factory/node_factory.nim`: caller drops `cast[pointer](lezGm)` — passes the ref directly.
- `src/chat/delivery/waku_client.nim`: same caller-site cast dropped.
- Mirrored into the loose `logos-delivery` checkout (byte-identical).

Builds: both `liblogoschat` and `liblogosdelivery` clean.
Local sim: ALL 15 PASS.

### Commit SHAs

- vendor/nwaku: `618ce267`
- vendor/logos-lez-rln/logos-delivery (loose): `d960a564`
- outer logos-chat: `fce56b3`

## Deferred

- The internal `cast[pointer](lezGm)` inside `setGroupManagerRef` and the `cast[OnchainLEZGroupManager](gm)` inside `setRlnIdentity` are now the only two casts in this path. Both are mandated by the cross-thread global pattern. Wrapping them in a `distinct pointer` handle was considered and rejected: a `distinct pointer` would buy zero safety here (single writer + single reader inside the same module, both casts justified by the cross-thread storage contract), while adding a new type that has to be threaded through callers.
