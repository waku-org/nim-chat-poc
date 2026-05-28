# Slim sim against latest testnet deployment

```bash
git clone -b feat/sim-rln-gifter-auth-v2 git@github.com:logos-messaging/logos-chat.git
cd logos-chat && git submodule update --init --recursive
SIM_NETWORK=testnet SIM_SLIM=1 SIM_DELIVERY_TIMEOUT=1800 \
    bash simulations/mix_lez_chat/run_simulation.sh --fresh
```

~15-25 min depending on testnet block timing. Pass: **ALL 15 CHECKS PASSED**.

Slim mode reuses the on-chain RLN programs at the shipped `TREE_ID` (committed in `vendor/logos-lez-rln/testnet/`) — no fresh deploy. The shipped payment account holds 1B RLNTOK (~1000 registrations) drawn from a 10B supply, refilled by re-running `vendor/logos-lez-rln/lez-rln/target/debug/run_setup` against testnet when needed.

`SIM_DELIVERY_TIMEOUT=1800` (30 min) is required: the gifter now serializes registrations through a single-writer worker that awaits chain confirmation between submissions to avoid per-signer nonce collisions. With testnet's ~60-90 s block cadence and up to ~6 jobs ahead in the queue, the chat sender (last in line) needs the longer delivery window. The default 300 s value would expire before its registration confirms.

If a run still fails after a clean retry: the most likely cause is a stale `~/.logos-lez-rln/payment_account_<TREE_ID>.txt` cache from a previous shipped TREE_ID. Wipe with:

```bash
rm -f ~/.logos-lez-rln/payment_account_*.txt \
      ~/.logos-lez-rln/supply_holding_*.txt \
      vendor/logos-lez-rln/testnet/storage.json \
      vendor/logos-lez-rln/testnet/wallet_config.json
```

and re-run — `seed_copy` will then re-seed from the shipped sidecars.

If you haven't built the modules on this machine before, run `bash simulations/mix_lez_chat/setup_and_run.sh` once first to build the dylibs.

Background on the bug class this used to hit: `cleanup/MODE_A_GIFTER_SLOT_BUG.md`.
