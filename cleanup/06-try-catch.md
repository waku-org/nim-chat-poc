# Cleanup 06 - defensive try/except removal

Scope: in-scope Nim files (Level 1-5), C++ (logos-rln-module), Rust (lez-rln-ffi).
Restore tag: `restore/sim-15-15-pass-2026-05-21`.

This file supersedes the first-pass audit. The first pass concluded "no removals";
a second pass found three real issues and applied them.

## Research notes

`waku_client.nim` (Level 1): zero try/except.

`node_factory.nim` (Levels 2 & 5):
- ~L240-246: parseJson on FFI register_member response (returns Result) - boundary, KEEP.
- ~L265-278: `waitForChainCommit` poll loop: parseJson on FFI is_member_registered response. ORIGINAL: silent `except CatchableError: continue`. APPLIED FIX: narrow to `JsonParsingError`/`JsonKindError` and `warn`-log before `continue`.
- ~L295: `waitForChainCommit` invoked via `await` - now wrapped in caller's outer flow; left as-is.
- ~L730-810: Gifter self-registration handler (logs via `warn` in outer except) - KEEP.
  - INSIDE: ~L775-780 self-reg watcher poll loop. ORIGINAL: silent `except CatchableError: continue` around `await gifter.statusHandler(...)` and bare `await sleepAsync` (CancelledError unhandled). APPLIED FIX: add `CancelledError: return` carve-outs for both await sites; `debug`-log + `continue` for the libp2p I/O CatchableError branch.
- ~L820-832: gifter client registration RPC - KEEP.
- Other mountXxx wrappers and library-boundary catches - KEEP per first-pass audit.

`rln_gifter/client.nim` (Levels 2 & 5):
- L61-127: libp2p stream I/O `writeLp`/`readLp` wrapped in narrow `LPStreamError` - KEEP (mandated by `{.async: (raises: [CancelledError]).}` annotation).
- L148-160: watcher poll loop - already has correct `CancelledError: return` + `CatchableError -> Result.err(...)` pattern (NOT silent). KEEP.

`rln_gifter/protocol.nim` (Levels 2 & 5): server-side handlers - all narrow LPStreamError. KEEP.

`logos_core_client.nim` (Levels 2 & 5): parseHexInt / parseJson at FFI deserialization boundary - all convert to `Result.err(...)`. KEEP.

`onchain_group_manager.nim` (Level 3 - mix-rln-spam-protection-plugin):
- `pollLoop` L182-194 and L200-220: `try/except CatchableError as e: debug "..."` wrapping `await gm.fetchRoots()` and `await gm.fetchProof(...)`. APPLIED FIX: REMOVED both try/except blocks - **dead code**. The callbacks are typed `proc(): Future[...] {.gcsafe, raises: [].}` (see L25-26 of same file), so `await` cannot raise `CatchableError`. The Result inside the Future is the only error path, and the existing `if .isOk/.isErr` branches already log it.

`spam_protection.nim` (Level 3): `nullifierLog` `Table[]` access wrapped in narrow `KeyError -> Result.err(...)`. KEEP.

C++ (`logos_rln_module.cpp/.h`): no try/catch.
Rust (`lez-rln-ffi/src/lib.rs`): no defensive `match Err`. Out of scope.

## Critical assessment by category

1. **libp2p stream I/O catches** (`client.nim`, `protocol.nim`): KEEP. Narrow LPStreamError, converts to Result. Required by `(raises: [CancelledError])` annotation.
2. **chronos CancelledError**: KEEP and ADD where missing. Mandatory for graceful task cancellation.
3. **FFI parse boundaries** (`parseJson`, `parseHexInt`, `Address.fromHex`): KEEP. Real deserialization trust boundary; converts to typed `Result.err`.
4. **`await mountXxx` wrappers** (~11 sites): KEEP. Library-boundary `try -> err(...)`.
5. **`Table` KeyError**: KEEP. Library boundary.
6. **Outer wrappers that warn-log**: KEEP. Logged failures with intentional retry/continue.
7. **Poll-loop swallow + continue with NO log AND no Result conversion**: REMOVE or fix. Two sites in `node_factory.nim` (`waitForChainCommit` and self-reg watcher).
8. **try/except CatchableError around await of a `{.raises: [].}` proc**: REMOVE. Dead code by type system.

## Applied

### vendor/nwaku (Level 2) - branch `feat/sim-rln-gifter-auth`

`waku/factory/node_factory.nim`:
- `waitForChainCommit`: narrow `except CatchableError: continue` to `except JsonParsingError as e: warn ...; continue` + `except JsonKindError as e: warn ...; continue`.
- Self-reg watcher poll loop: replace bare `await sleepAsync` with `try/except CancelledError: return`; replace silent `except CatchableError: continue` on `await gifter.statusHandler(...)` with `except CancelledError: return` + `except CatchableError as e: debug ...; continue`.

`vendor/mix-rln-spam-protection-plugin/src/mix_rln_spam_protection/onchain_group_manager.nim` (Level 3 - branch `cleanup`):
- `pollLoop`: REMOVE both `try/except CatchableError as e: debug ...` blocks around `await gm.fetchRoots()` and `await gm.fetchProof(...)`. Callbacks are `{.raises: [].}` - the except branches were unreachable.

### Mirrored to (byte-identical):

- `vendor/logos-lez-rln/logos-delivery/waku/factory/node_factory.nim`
- `vendor/logos-lez-rln/logos-delivery-module/vendor/logos-delivery/waku/factory/node_factory.nim`
- `vendor/logos-lez-rln/logos-delivery/vendor/mix-rln-spam-protection-plugin/src/mix_rln_spam_protection/onchain_group_manager.nim`
- `vendor/logos-lez-rln/logos-delivery-module/vendor/logos-delivery/vendor/mix-rln-spam-protection-plugin/src/mix_rln_spam_protection/onchain_group_manager.nim`

## Deferred

- Two `parseJson`-wrapping `CatchableError` catches in `node_factory.nim` register_member (~L240) could be narrowed to `JsonParsingError`/`JsonKindError`. Deferred - already at boundary, logs in caller, low value.
- Gifter self-registration handler (`node_factory.nim` ~L742-803) outer `try/except CatchableError as e: warn`: could split the try to wrap only the `await gifter.registerHandler(...)`. Cosmetic; deferred.
- Rust `unwrap()` audit on FFI slice -> array conversions: out of try/catch scope (infallible-by-construction claims belong in a separate pass).

## Builds

- `make liblogoschat` - OK.
- `make liblogosdelivery` (under `vendor/logos-lez-rln/logos-delivery`) - OK.

## Sim

Skipped per agent-06 instructions; the user will run a single end-of-pass verification after all 8 agents.
