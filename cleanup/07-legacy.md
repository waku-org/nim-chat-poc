Cleanup-07 (legacy/fallback/deprecated removal) — research and verdict
FEATURE: Code-quality sequential pass on feat/sim-rln-gifter-auth-v2

# Cleanup 07 — Deprecated / legacy / fallback (v2 pass)

This is the second 07 pass, run against the post-squash `feat/sim-rln-gifter-auth-v2`
branch state after agents 01-06 had completed (commits visible: cleanup(01-dry),
cleanup(03-unused), cleanup(06-try-catch); 02/04/05 produced no edits).

## Scope re-swept

Ran `rg 'DEPRECATED|TODO|FIXME|legacy|fallback|workaround|XXX'` across every
in-scope file class from CLEANUP_SCOPE.md:

- outer logos-chat: `src/chat/`, `library/`, `simulations/`, `scripts/`, `Makefile`
- nwaku scope: `waku/waku_mix/`, `waku/waku_rln_relay/rln_gifter/`,
  `waku/factory/{node_factory,waku_conf,conf_builder/mix_conf_builder}.nim`,
  `waku/discovery/waku_kademlia.nim`, `waku/node/kernel_api/relay.nim`,
  `liblogosdelivery/`, `apps/chat2mix/`, `simulations/mixnet/`,
  `scripts/build_rln_mix.sh`, `tools/confutils/cli_args.nim`,
  `tests/waku_rln_relay/test_rln_gifter.nim`
- lez-rln + plugins: `lez-rln/src/`, `lez-rln/rln-layouts/src/`,
  `lez-rln/lez-rln-ffi/src/`, `logos-rln-module/src/`,
  `logos-delivery-module/src/`, chat-module `src/`
- mix-rln-spam-protection-plugin: `src/mix_rln_spam_protection/`
- build/sim scripts: `build_all.sh`, `build_mix_sim.sh`, `dev.sh`,
  `dev/env.sh`, `testnet/env.sh`, `run_simulation.sh`, `setup_and_run.sh`,
  `run_in_docker.sh`

## Per-site verdicts

| Site | Verdict |
|---|---|
| `onchain_group_manager.nim` "Older RPC response shape" else-branch | **ALREADY GONE.** Both canonical (`vendor/nwaku/vendor/mix-rln-spam-protection-plugin`) and loose (`vendor/logos-lez-rln/logos-delivery/vendor/...`) trees only have the unified-`validRoots` path. No vestige to remove. |
| 40744d96 `DEBUG gifter self-reg gate` instrumentation | **NOT PRESENT** in either nwaku or loose/canonical `logos-delivery` checkouts at the current squashed tips. The 2-phase gifter self-reg path in `node_factory.nim:724-816` uses `info`/`warn`/`debug` log lines that are legitimate operational telemetry, not gate-instrumentation. One `debug` line at L791 ("Gifter self-reg watcher: statusHandler raised") is a meaningful exception-path trace, not session-time noise. |
| `waku_client.nim:238` "Sending via relay fallback (mix not ready or not enabled)" | **KEEP.** This is a runtime path (relay when mix not yet ready), not a code-shape fallback. Intentional and active. |
| `waku_client.nim:98` `# TODO: protect key exposure` | **KEEP.** Forward-looking security note, not a legacy marker. |
| `waku_client.nim:320` `# TODO: Use filter. Removing this stops relay…` | **KEEP.** Live constraint note. |
| `client.nim:104,208` `# TODO: (P1) …` | **KEEP.** Roadmap markers tied to P1 features. |
| `chat_module_plugin.h` many `// TODO: should not be async` | **OUT OF SCOPE / KEEP.** Pre-existing upstream design TODOs in chat-module. |
| `chat_module_plugin.cpp:62` "stderr fallback" + `simulations/.../README.md:200` "EVENT: stderr fallback" | **KEEP.** Documented intentional cross-platform telemetry path, not a code-shape fallback. |
| `node_factory.nim` `waku_archive_legacy` / `waku_store_legacy` / `waku_lightpush_legacy` imports + branches | **OUT OF SCOPE.** Upstream nwaku legacy protocols, not session work. |
| `tools/confutils/cli_args.nim` `legacyStore` | **OUT OF SCOPE.** Upstream. |
| `apps/chat2mix/*.nim` TODOs/XXX | **OUT OF SCOPE.** Upstream chat2mix design notes (pre-mix-integration). |
| `client.rs`, `rln-layouts`, FFI, guests, Qt plugins | No DEPRECATED/FIXME/XXX/workaround/fallback markers found. |
| Sim/build scripts (`run_simulation.sh`, `setup_and_run.sh`, `build_all.sh`, etc.) | No legacy/fallback/workaround markers found. No multi-path init logic. |
| `feat/sim-rln-gifter-auth-debug` branch name | Cosmetic; the branch carries the full canonical work, renaming requires coordination with the loose-checkout mirror dance. Deferred (same conclusion as prior round). |

## Applied

**Nothing.** All previously identified removals (the `# Older RPC response shape`
else-branch and the `DEBUG gifter self-reg gate` instrumentation) are already
absent from the current branch tips. The prior 07 round on
`feat/sim-rln-gifter-auth` plus the subsequent squash carried those removals
forward into `feat/sim-rln-gifter-auth-v2` cleanly.

## Deferred

- `feat/sim-rln-gifter-auth-debug` branch rename — cosmetic, cross-checkout
  coordination cost not worth it now (matches prior round's verdict).

## Commit SHAs

None — no edits applied this pass.

## Build status

No build attempted — no source changes.
