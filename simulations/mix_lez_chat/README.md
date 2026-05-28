# Mix + LEZ RLN Chat Simulation

End-to-end private chat between two logos-chat-module clients over a 4-node mix network with LEZ-backed RLN spam protection.

Two logoscore instances (sender + receiver) establish an X3DH key agreement via an out-of-band intro bundle, then exchange double-ratchet-encrypted messages routed through 3-hop Sphinx onion routes with per-hop RLN proof generation and verification. Node 0 mounts the rln_gifter service; nodes 1-3 and both chat clients register RLN memberships on-chain via the gifter protocol. The sender publishes via `lightpushPublish(mixify=true)`, the mix exit node verifies the RLN proof before fanning out via gossipsub relay, and the receiver consumes the message via a Waku filter subscription.

## macOS

**Prereqs:** nix (with flakes), Docker, cargo-risczero, SSH access to GitHub.

```bash
git clone -b feat/logos-delivery git@github.com:adklempner/logos-chat.git
cd logos-chat && bash simulations/mix_lez_chat/setup_and_run.sh
```

First run: ~15-25 min. Re-runs: `bash simulations/mix_lez_chat/run_simulation.sh --fresh` (~5 min).

## Linux (native)

**Prereqs:** nix (with flakes), Docker, cargo-risczero, SSH access to GitHub.

```bash
git clone -b feat/logos-delivery git@github.com:adklempner/logos-chat.git
cd logos-chat && bash simulations/mix_lez_chat/setup_and_run.sh
```

Same as macOS. On x86_64 Linux this should work out of the box. On aarch64 Linux, guest zkVM binaries must be pre-built on another platform (rzup doesn't support aarch64-linux) and the wallet module nix build needs `RISC0_SKIP_BUILD_KERNELS=1`.

## Linux (via Docker)

**Prereqs:** Docker with 24GB RAM allocated.

```bash
git clone -b feat/logos-delivery git@github.com:adklempner/logos-chat.git
cd logos-chat && bash scripts/run_in_docker.sh
```

The pre-built image (`ghcr.io/adklempner/logos-chat-sim`) is pulled automatically (~8.5GB download). Guest zkVM binaries must exist on the host from a previous macOS/x86_64 build, or set `GUEST_BINARIES_DIR`.

Each sim run: ~10 min (clone + sequencer build + sim). To force a local image rebuild: `REBUILD_IMAGE=1 bash scripts/run_in_docker.sh`.

## Pass criteria

**ALL 15 CHECKS PASSED** — 4 mix nodes mounted, gifter service, LEZ RLN active, sender+receiver initialized/started/mix-mounted, intro bundle created, messages sent and received.

## Architecture

```
logoscore (per mix node)                    logoscore (per chat client)
├── wallet_module (LEZ wallet)              ├── wallet_module (LEZ wallet)
├── liblogos_rln_module (RLN proofs)        ├── liblogos_rln_module (RLN proofs)
└── delivery_module (Waku mix relay)        └── chat_module (logos-chat-module)
    ├── liblogosdelivery.so                     ├── chat_module_plugin.so
    └── mix + relay + filter + gifter           └── liblogoschat.so
                                                    └── mix client + filter + gifter client
```

Node 0 runs the RLN gifter service. Nodes 1-3 register via gifter on startup. Chat clients also register via gifter when `startChat()` runs.

## Configuration

Override defaults via environment:

| Variable | Default | Description |
|---|---|---|
| `SIM_NUM_NODES` | `4` | Number of mix relay nodes |
| `SIM_BASE_TCP_PORT` | `60001` | First node's TCP port (increments per node) |
| `SIM_BASE_DISC_PORT` | `9001` | First node's discv5 UDP port (increments per node) |
| `SIM_CLUSTER_ID` | `99` | Waku cluster ID |
| `SIM_LOG_LEVEL` | `INFO` | Node log level (TRACE, DEBUG, INFO, WARN, ERROR) |
| `SIM_CHAT_RECV_PORT` | `60010` | Chat receiver TCP port |
| `SIM_CHAT_SEND_PORT` | `60011` | Chat sender TCP port |
| `SIM_KADEMLIA_MIN_WAIT` | `30` (local) / `120` (testnet) | Minimum seconds to wait for kademlia propagation |
| `SIM_RECEIVER_MIN_WAIT` | `15` (local) / `60` (testnet) | Minimum seconds to wait for receiver to join mix |
| `SIM_DELIVERY_TIMEOUT` | `120` (local) / `300` (testnet) | Max seconds to wait for message delivery |
| `SIM_NODE_STARTUP_SLEEP` | `10` (local) / `30` (testnet) | Seconds between launching each mix node |
| `SIM_NETWORK` | `local` | `local` runs against a sequencer on `127.0.0.1:3040`; `testnet` runs against `https://testnet.lez.logos.co/` |

Example — fast iteration with verbose logging:

```bash
SIM_LOG_LEVEL=TRACE SIM_KADEMLIA_MIN_WAIT=10 SIM_RECEIVER_MIN_WAIT=5 \
  bash simulations/mix_lez_chat/run_simulation.sh --fresh
```

## Running against the public testnet

```bash
SIM_NETWORK=testnet bash simulations/mix_lez_chat/run_simulation.sh --fresh
```

Effect of `SIM_NETWORK=testnet`:
- Phase 1 (local sequencer launch) is skipped; the script does a one-shot reachability check against `https://testnet.lez.logos.co/` and dies up front if unreachable.
- Wallet config is picked from `vendor/logos-lez-rln/testnet/` instead of `dev/`. The wallet's `storage.json` and the on-chain registration accounts persist across runs.
- `run_setup` deploys + initializes on first run, then short-circuits via `is_initialized` on every run after — see "Config account: …" in the setup output either way.
- Timing floors (`SIM_KADEMLIA_MIN_WAIT`, `SIM_RECEIVER_MIN_WAIT`, `SIM_DELIVERY_TIMEOUT`, `SIM_NODE_STARTUP_SLEEP`) and `LEZ_RLN_BLOCK_SEAL_SECS` default higher to match ~60s testnet block times.

Prerequisites:
- The gifter mix node's payment account must be funded on testnet. The first successful `SIM_NETWORK=testnet … --fresh` run populates `~/.logos-lez-rln/payment_account_<tree_id>.txt` automatically; subsequent runs reuse it.
- Expected wall-clock runtime: ~20–25 minutes (first run) / ~15 minutes (subsequent runs), vs. ~3 minutes locally.
- Only one developer at a time — concurrent testnet sim runs share the gifter wallet and will collide.

### Reproducibility on a fresh clone

The canonical testnet deployment (RLN tree + minted supply) is shared across developers. On first run, the script seeds two artifacts from the submodule so `run_setup` can short-circuit to `create_funded_user`:

- `vendor/logos-lez-rln/testnet/storage.json.seed` → copied to `vendor/logos-lez-rln/testnet/storage.json` if absent. Contains only the supply holding account + its signing key.
- `vendor/logos-lez-rln/testnet/supply_holding.txt` → copied to `~/.logos-lez-rln/supply_holding_<tree_id>.txt` if absent. Contains the supply `AccountId`.

What stays shared vs. fresh:

| Artifact | Shared | Per-dev fresh |
|---|---|---|
| `TREE_ID`, sequencer URL, deployed program IDs (on-chain), gifter EIP-191 auth keys, mix node identity keys | ✓ | |
| Supply holding account + signing key (seeded from submodule) | ✓ | |
| Per-run payment account (`~/.logos-lez-rln/payment_account_<tree>.txt`) | | ✓ |
| Working-copy `testnet/storage.json` (gitignored; accumulates payment accounts) | | ✓ |
| Mix + chat RLN credentials (in `.sim_state/rln_keystore_*.json`) | | ✓ |

**Security:** the supply signing key being in the repo is acceptable only because testnet does not charge gas and the tokens are test tokens with no real value.

### Slim mode (`SIM_SLIM=1`, testnet only)

`SIM_SLIM=1 SIM_NETWORK=testnet ./run_simulation.sh --fresh` skips `run_setup` entirely and reuses the shipped `config_account` + cached `payment_account` from `vendor/logos-lez-rln/testnet/`. Two consequences:

- No `lez-rln/run_setup` binary build is required. Combined with the submodule split below, a fresh clone can run the sim without ever invoking `cargo` from `lez-rln/`.
- All slim-mode runs share one on-chain payment account — concurrent runs across devs will race on its nonce. Use serially.

**Minimum submodule set for slim mode:**

```bash
git clone --branch feat/logos-delivery <repo> logos-chat
cd logos-chat
git submodule update --init vendor/logos-lez-rln vendor/nwaku vendor/nimbus-build-system vendor/nim-protobuf-serialization vendor/npeg vendor/blake2 vendor/libchat vendor/nim-ffi
(cd vendor/logos-lez-rln && git submodule update --init logos-delivery-module)
(cd vendor/logos-lez-rln/logos-delivery-module && git submodule update --init --recursive vendor/logos-delivery)
```

The previously-required `lssa` (~11 GB) and `logos-execution-zone-module` clones are unnecessary for slim mode — both are fetched via nix flake from GitHub when building the wallet/RLN modules. The top-level `vendor/logos-lez-rln/logos-delivery` submodule was removed entirely (the active copy is the nested `logos-delivery-module/vendor/logos-delivery`).

For the local-sequencer flow (`SIM_NETWORK=local`) or to hack on the wallet/sequencer source, init the extras: `(cd vendor/logos-lez-rln && git submodule update --init lssa logos-execution-zone-module)`. The Docker bootstrap (`setup_and_run.sh`) gates these on `SIM_NETWORK=local` automatically; pass `SIM_FULL_SUBMODS=1` to force the wide init.

## `--fresh` behavior

When `--fresh` is passed:
- Kills all existing `logos_host` processes
- Cleans `/tmp/logos_*` Qt RemoteObjects sockets
- Removes `.sim_state/` directory
- On `SIM_NETWORK=local` (default): removes sequencer state (`rocksdb/`, `bedrock_signing_key`), rebuilds and restarts the sequencer, redeploys RLN programs via `run_setup`
- On `SIM_NETWORK=testnet`: leaves on-chain state and the persistent wallet under `vendor/logos-lez-rln/testnet/` intact; `run_setup` short-circuits to `create_funded_user`

Without `--fresh`, on `SIM_NETWORK=local` it reuses an existing sequencer if port 3040 is already bound.

## Troubleshooting

**Re-run with fresh state:**
```bash
bash simulations/mix_lez_chat/run_simulation.sh --fresh
```

**"Sequencer failed to start"** — port 3040 already in use:
```bash
kill $(lsof -ti tcp:3040) && bash simulations/mix_lez_chat/run_simulation.sh --fresh
```

**"run_setup failed" / "Timeout waiting for account"** — stale guest binaries or wallet state:
```bash
rm -rf vendor/logos-lez-rln/lez-rln/methods/guest/target
rm -f vendor/logos-lez-rln/dev/wallet_config.json vendor/logos-lez-rln/dev/storage.json
bash simulations/mix_lez_chat/setup_and_run.sh
```

**"Sender started FAIL"** — stale Qt RemoteObjects sockets:
```bash
rm -f /tmp/logos_*
bash simulations/mix_lez_chat/run_simulation.sh --fresh
```

Docker logs are rescued to `./docker-sim-logs/` on failure.

## Adapting for other LEZ programs

This simulation provides a complete mix network infrastructure that other logos modules can reuse for testing. To test your own module:

### What the sim provides
- 4 logoscore mix nodes with `delivery_module` (Waku relay + mix + RLN)
- LEZ sequencer with deployed RLN programs
- RLN gifter service on node 0
- Wallet modules for on-chain transactions

### What you replace
The chat_module sender/receiver instances (phase 5 of run_simulation.sh). Your module needs:

1. **A C++ Qt plugin** implementing `PluginInterface` (see `chat_module_plugin.cpp`)
   - `initLogos(LogosAPI*)` — receive the LogosAPI instance
   - `eventResponse(QString, QVariantList)` signal — mandatory per logos-liblogos contract
   - Methods exposed via `LOGOS_METHOD` for logoscore `-c` invocation
2. **A shared library** with your program logic (like `liblogoschat.so`)
3. **RLN integration** — wire `setRlnConfig` to pass RLN credentials from the C++ plugin to your library
4. **EVENT: stderr fallback** — on Linux, Qt signal forwarding from plugin to logoscore doesn't work across the FFI thread boundary. Write event data to stderr in `EVENT:name:data` format (gated by `LOGOS_EVENT_STDERR` env var) for cross-platform reliability.

### How to stage your module

```bash
MDIR=$(mktemp -d)
mkdir -p "$MDIR/your_module"
cp your_module_plugin.so "$MDIR/your_module/"
cp libyour_library.so "$MDIR/your_module/"
echo '{"name":"your_module","version":"1.0.0","type":"core",...}' > "$MDIR/your_module/manifest.json"

logoscore -m "$MDIR" \
  -l "liblogos_execution_zone_wallet_module,liblogos_rln_module,your_module" \
  -c "liblogos_execution_zone_wallet_module.open($WALLET_CONFIG,$WALLET_STORAGE)" \
  -c "your_module.init(@config.json)" \
  -c "your_module.start()"
```

### Reference
- `chat_module_plugin.cpp` — complete working example with RLN, gifter, mix, and event emission
- `delivery_module_plugin.cpp` — more complex example with full RLN fetcher integration
- `run_simulation.sh` — orchestration, module staging, and verification patterns

## Logs

All logs in `simulations/mix_lez_chat/.sim_state/`:
- `node0.log` – `node3.log` — mix relay nodes
- `chat_receiver.log` — receiver chat module
- `chat_sender.log` — sender chat module
- `sequencer.log` — LEZ sequencer
