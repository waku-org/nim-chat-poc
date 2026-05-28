# Running the Mix + LEZ RLN Chat Simulation

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

**Prereqs:** Docker.

```bash
git clone -b feat/logos-delivery git@github.com:adklempner/logos-chat.git
cd logos-chat && bash scripts/run_in_docker.sh
```

The pre-built image (`ghcr.io/adklempner/logos-chat-sim`) is pulled automatically (~8.5GB download). Guest zkVM binaries must exist on the host from a previous macOS/x86_64 build, or set `GUEST_BINARIES_DIR`.

Each sim run: ~10 min (clone + sequencer build + sim). To force a local image rebuild: `REBUILD_IMAGE=1 bash scripts/run_in_docker.sh`.

## Pass criteria

**ALL 15 CHECKS PASSED** — 4 mix nodes mounted, gifter service, LEZ RLN active, sender+receiver initialized/started/mix-mounted, intro bundle created, messages sent and received.

## LEZ backend

The simulation runs against the SPEL framework (logos-lez-rln `sim-on-spel` branch, based on `feat/spel`). The on-chain RLN programs use SPEL's `#[lez_program]` macro with 32-byte tree IDs, Borsh-encoded state, and PDA-based account derivation via `combine_seeds`.

## Configuration

```bash
SIM_LOG_LEVEL=TRACE SIM_KADEMLIA_MIN_WAIT=10 bash simulations/mix_lez_chat/run_simulation.sh --fresh
```

Full list of `SIM_*` variables in `simulations/mix_lez_chat/README.md`.

## If it fails

Re-run with fresh state:
```bash
bash simulations/mix_lez_chat/run_simulation.sh --fresh
```

Wallet/sequencer errors:
```bash
rm -f vendor/logos-lez-rln/dev/wallet_config.json vendor/logos-lez-rln/dev/storage.json
rm -f ~/.logos-lez-rln/payment_account_*.txt
```

Guest binary errors after updating submodules:
```bash
rm -rf vendor/logos-lez-rln/lez-rln/methods/guest/target
bash simulations/mix_lez_chat/setup_and_run.sh
```

Docker logs are rescued to `./docker-sim-logs/` on failure.
