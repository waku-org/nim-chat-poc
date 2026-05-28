# Cleanup scope (post-squash, 2026-05-28)

The full LEZ+RLN+mix+gifter+sim work is now consolidated into a single squashed commit per repo. The files touched by each squashed commit define the cleanup boundary. Files NOT in this list are upstream code we should leave alone.

## Repos in scope

| Repo path | Squashed tip | Branch | Role |
|---|---|---|---|
| `.` (outer logos-chat) | `29c64b3` | `feat/sim-rln-gifter-auth-v2` | Chat client + sim harness |
| `vendor/nwaku` | `8e6ba04` | `feat/sim-rln-gifter-auth` | Mix protocol + 2-phase gifter (Nim) |
| `vendor/logos-lez-rln` | `950f287` | `feat/eip191-gifter-auth` | RLN program (Rust SPEL) + sim infra + testnet deploy |
| `vendor/logos-lez-rln/logos-delivery-module` | `680eaff` | `feat/logos-delivery-v2` | Qt plugin bridging logos-core ↔ nwaku |
| `vendor/logos-lez-rln/logos-delivery-module/vendor/logos-delivery` | `4f34568` | `feat/sim-rln-gifter-auth-debug` | Mirror of nwaku branch under delivery-module submodule chain |
| `vendor/nwaku/vendor/mix-rln-spam-protection-plugin` | `8763f61` | `cleanup` | Mix RLN spam protection (LEZ-backed group manager) |
| `/Users/arseniy/Waku/Logos/logos-chat-module` | `7aecb1e` | `feat/logos-delivery-v2` | Chat-side Qt plugin |

The loose `vendor/logos-lez-rln/logos-delivery` is a fork-of-nwaku checkout — its source is identical to `vendor/logos-lez-rln/logos-delivery-module/vendor/logos-delivery` (the canonical submodule path). Cleanups should be applied to ONE of them and mirrored to the other.

## In-scope file classes per repo

Pull the authoritative list with: `git -C <repo> show HEAD --name-only`.

Quick reference of key files (Nim/Rust/C++/Bash):

**outer logos-chat (`.`):**
- `src/chat/client.nim`, `src/chat/delivery/waku_client.nim` — chat-side mix integration + gifter watcher
- `simulations/mix_lez_chat/run_simulation.sh`, `simulations/mix_lez_chat/setup_and_run.sh`, `scripts/run_in_docker.sh` — sim harness
- `Makefile`, `nix/default.nix`, `library/api/client_api.nim`, `library/declare_lib.nim`, `library/liblogoschat.h`, `rust-bundle/Cargo.toml` — build glue
- `RUN_SLIM_TESTNET.md`, `cleanup/MODE_A_GIFTER_SLOT_BUG.md`, `README.md`, `simulations/mix_lez_chat/INSTRUCTIONS.md` — docs

**vendor/nwaku** (and identical loose `vendor/logos-lez-rln/logos-delivery`):
- `waku/waku_rln_relay/rln_gifter/{client,protocol,rpc,rpc_codec}.nim` — 2-phase gifter implementation
- `waku/waku_mix/{logos_core_client,protocol}.nim` — mix wiring + LEZ fetcher bridge
- `waku/factory/{node_factory,conf_builder/mix_conf_builder,waku_conf}.nim` — gifter mount + queue+worker + chat-mix config
- `waku/discovery/waku_kademlia.nim`, `waku/node/kernel_api/relay.nim` — mix-pool readiness gate, lightpush mix-mode
- `liblogosdelivery/{declare_lib.nim,liblogosdelivery.h,nim.cfg}` — delivery dylib FFI
- `apps/chat2mix/*.nim`, `simulations/mixnet/*`, `scripts/build_rln_mix.sh`, `tools/confutils/cli_args.nim`, `tests/waku_rln_relay/test_rln_gifter.nim` — sim harness + tooling

**vendor/logos-lez-rln** (Rust + bash + sidecars):
- `lez-rln/src/rln/client.rs`, `lez-rln/src/bin/{run_setup,register_member,register_commitments,get_roots,run_rln_proof}.rs` — host CLI
- `lez-rln/rln-layouts/src/*.rs` — shared instruction + PDA layouts
- `lez-rln/methods/guest/src/**` — RISC-V zkVM guests (Register handler, merkle tree)
- `lez-rln/lez-rln-ffi/src/lib.rs` + `lez_rln_ffi.h` — FFI surface used by logos-rln-module
- `logos-rln-module/src/{logos_rln_module.cpp,logos_rln_module.h,i_logos_rln_module.h,liblogos_rln_module_api.h}` — Qt RLN module
- `build_all.sh`, `build_mix_sim.sh`, `flake.nix`, `dev.sh`, `dev/env.sh`, `testnet/env.sh`, README — build / deploy infra
- `testnet/*` (config_account, payment_account, supply_holding, storage.json.seed, wallet_config.json) — shipped sidecars (data, not code; do not touch)

**vendor/logos-lez-rln/logos-delivery-module** (C++):
- `src/{delivery_module_plugin.cpp,delivery_module_plugin.h,delivery_module_interface.h,QExpected.h,liblogos_rln_module_api.h}` — Qt delivery module + rln_fetcher async trampoline
- `CMakeLists.txt`, `flake.nix`, `metadata.json`

**vendor/nwaku/vendor/mix-rln-spam-protection-plugin** (Nim):
- `src/mix_rln_spam_protection/{group_manager,onchain_group_manager,rln_interface,spam_protection}.nim`

**logos-chat-module** (C++):
- `src/{chat_module_plugin.cpp,chat_module_plugin.h,chat_module_interface.h,liblogos_rln_module_api.h}` — Qt chat module + rln_fetcher trampoline
- `CMakeLists.txt`, `flake.nix`, `metadata.json`

## Out of scope

- Upstream nwaku (anything under `vendor/nwaku/` that wasn't touched by the squashed commit). For nwaku in particular, only files in `waku/waku_mix/`, `waku/waku_rln_relay/rln_gifter/`, `liblogosdelivery/`, `apps/chat2mix/`, `simulations/mixnet/`, plus the specific files listed above in `waku/factory/`, `waku/discovery/`, `waku/node/kernel_api/`, `tests/waku_rln_relay/` are ours.
- `vendor/nwaku/vendor/*` other than `mix-rln-spam-protection-plugin`.
- `vendor/logos-lez-rln/lssa/`, `vendor/logos-lez-rln/logos-execution-zone-module/`, `vendor/logos-lez-rln/vendor/*`, and `vendor/logos-lez-rln/logos-rln-module/vendor/*` — third-party deps.
- `lez-rln/methods/guest/target/`, any `Cargo.lock` regenerations — build artifacts.
- `testnet/` data files (account IDs, storage.json.seed) — chain state, not code.
