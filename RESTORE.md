# Restore point: working testnet sim — 2026-05-17

Snapshot taken before consolidation / refactoring. Reproduces a passing
testnet sim run in two modes:

- **Default**: `SIM_NETWORK=testnet ./simulations/mix_lez_chat/run_simulation.sh --fresh`
  — runs `run_setup` to create a fresh per-dev payment account, registers
  all 5 sim participants on the deployed RLN tree, delivers test messages.
- **Slim**: `SIM_NETWORK=testnet SIM_SLIM=1 ./simulations/mix_lez_chat/run_simulation.sh --fresh`
  — skips `run_setup`; uses the shared payment account shipped in the
  submodule. Useful for fresh-clone devs who don't want to build the
  `lez-rln/run_setup` Rust binary.

Both modes pass at ~2/3 reliability (intermittent mix-routing / QtRO flake;
re-run with `--fresh` if a single attempt stalls).

## Pinned commits (per repo)

Each repo carries both an annotated tag and a branch named
`restore/working-2026-05-17` at the listed commit. Either can be used to
recover the state if HEAD moves during consolidation.

| Repo | Branch when tagged | Commit |
|---|---|---|
| `.` (logos-chat) | `feat/sim-rln-gifter-auth-v2` | `b6f094e` |
| `vendor/nwaku` | `feat/sim-rln-gifter-auth` | `60e875f3` |
| `vendor/logos-lez-rln` | `feat/eip191-gifter-auth` | `ed88c8f8` |
| `vendor/logos-lez-rln/logos-delivery-module` | `feat/eip191-gifter-auth` | `94173a3d` |
| `vendor/logos-lez-rln/logos-delivery-module/vendor/logos-delivery` | `feat/eip191-gifter-auth` | `e2799efe` |

## Restore

```bash
# From the outer repo root:
for r in . vendor/nwaku vendor/logos-lez-rln \
         vendor/logos-lez-rln/logos-delivery-module \
         vendor/logos-lez-rln/logos-delivery-module/vendor/logos-delivery; do
  git -C "$r" checkout restore/working-2026-05-17
done
```

After checkout, rebuild affected nim/Rust artifacts:

```bash
# Rebuild liblogosdelivery (used by sim's delivery_module_plugin)
( cd vendor/logos-lez-rln/logos-delivery-module/vendor/logos-delivery && make liblogosdelivery )

# Rebuild run_setup (only needed for default mode, not slim)
( cd vendor/logos-lez-rln/lez-rln && cargo build --bin run_setup )
```

## What's in this state

- TREE_ID `…1a05100200000000` (2026-05-16 deploy #2) — programs deployed on
  testnet, `is_initialized=true`.
- `vendor/logos-lez-rln/testnet/storage.json.seed` ships full post-deploy
  wallet state (10 accounts: 2 roots + 3 deploy publics + intermediate +
  shared payment + 4 preconfigured).
- `vendor/logos-lez-rln/testnet/{supply_holding,payment_account,config_account}.txt`
  for the slim-mode bootstrap.
- Gifter (mix node 0) self-registers as a mix relay at startup
  (eliminates the "Plugin not ready" forwarding drop when sender's
  circuit routes through it).
- FFI aligned with SPEL `ConfigState` (240-byte borsh) + 4-field Register
  instruction.
- Cross-thread Nim heap-string race fix in `mix_lez_client`.
