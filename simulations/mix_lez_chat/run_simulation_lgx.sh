#!/usr/bin/env bash
# Mix + LEZ RLN simulation (.lgx / daemon-mode logoscore variant).
# Same behavior + checks as run_simulation.sh, but consumes the new
# logoscore-cli daemon+subcommand model: each instance starts a daemon
# (logoscore -m MDIR -D) under an isolated LOGOSCORE_CONFIG_DIR, loads modules
# via `load-module <name>`, and issues `-c "X.method(args)"` calls against the
# running daemon. Modules ship as .lgx bundles produced by nix-bundle-lgx and
# installed into the modules dir via install_lgx.
#
# Prerequisites: same as run_simulation.sh.
# Usage: ./run_simulation_lgx.sh [--fresh]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGOS_CHAT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHAT_MODULE_DIR="${CHAT_MODULE_DIR:-$(cd "$LOGOS_CHAT_DIR/../logos-chat-module" && pwd)}"

# Use vendored logos-lez-rln submodule, or auto-detect as sibling
LEZ_RLN_DIR="${LEZ_RLN_DIR:-}"
if [ -z "$LEZ_RLN_DIR" ] && [ -d "$LOGOS_CHAT_DIR/vendor/logos-lez-rln/lez-rln" ]; then
    LEZ_RLN_DIR="$LOGOS_CHAT_DIR/vendor/logos-lez-rln"
fi
for candidate in "$LOGOS_CHAT_DIR/.." "$LOGOS_CHAT_DIR/../logos-lez-rln"; do
    [ -n "$LEZ_RLN_DIR" ] && break
    [ -d "$candidate/lez-rln" ] && LEZ_RLN_DIR="$(cd "$candidate" && pwd)" && break
done
[ -z "$LEZ_RLN_DIR" ] && { echo "FATAL: Cannot find logos-lez-rln repo. Set LEZ_RLN_DIR or run: git submodule update --init --recursive"; exit 1; }

DELIVERY_MODULE_DIR="${DELIVERY_MODULE_DIR:-$LEZ_RLN_DIR/logos-delivery-module}"
DELIVERY_DIR="$DELIVERY_MODULE_DIR/vendor/logos-delivery"

export RISC0_DEV_MODE=1
export TMPDIR=/tmp
export LOGOS_EVENT_STDERR=1  # Mirror EVENT: lines to stderr so the sim can grep them.

die() { echo "  FATAL: $*" >&2; exit 1; }
log() { echo "[$(date '+%H:%M:%S')] $*"; }

# Poll a logoscore log until it shows >= $expected "Method call successful"
# lines, or until $timeout iterations (sleeping $sleep_sec each) have elapsed.
# Sets global $N to the last observed count so callers can branch on it.
wait_method_calls() {
    local logfile="$1" expected="$2" timeout="$3" sleep_sec="${4:-1}"
    local t
    for t in $(seq 1 "$timeout"); do
        # New logoscore `call` subcommand emits one JSON line per successful
        # invocation: `{"method":"...","module":"...","result":N,"status":"ok"}`.
        N=$(grep -c '"status":"ok"' "$logfile" 2>/dev/null || true); N=${N:-0}
        [ "$N" -ge "$expected" ] && return 0
        sleep "$sleep_sec"
    done
    return 1
}

# Install a .lgx bundle into a logoscore modules dir. Extracts the manifest +
# the current $PLATFORM variant into <mdir>/<manifest.name>/, flattens dylibs
# to the top, and writes a `variant` marker file with the platform key.
install_lgx() {
    local mdir="$1" lgx="$2"
    local name tmp
    name=$(tar xzOf "$lgx" manifest.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')
    [ -z "$name" ] && die "install_lgx: cannot read name from $lgx"
    tmp=$(mktemp -d)
    tar xzf "$lgx" -C "$tmp"
    rm -rf "$mdir/$name"
    mkdir -p "$mdir/$name"
    cp "$tmp/manifest.json" "$mdir/$name/manifest.json"
    if [ -d "$tmp/variants/$PLATFORM" ]; then
        cp -L "$tmp"/variants/"$PLATFORM"/* "$mdir/$name/"
    else
        die "install_lgx: $lgx has no variants/$PLATFORM"
    fi
    printf '%s' "$PLATFORM" > "$mdir/$name/variant"
    rm -rf "$tmp"
}

# Copy a runtime-shared dylib into an already-installed module dir. nix-bundle-lgx
# currently drops `metadata.json:include[]` libs from the .lgx (tracked upstream),
# so we patch them in post-install. The dylib is looked up via @loader_path from
# the plugin, so dropping it next to the plugin is the correct fix.
install_extra_lib() {
    local mdir="$1" module="$2" lib="$3"
    [ -f "$lib" ] || die "install_extra_lib: missing $lib for $module"
    cp -L "$lib" "$mdir/$module/"
}

# Start a logoscore daemon under an isolated config dir, then load the
# comma-separated $LOAD list (in order, satisfies inter-module dependencies),
# then issue each subsequent argument as a `-c` call. Daemon PID is appended
# to INSTANCE_PIDS; config dirs accumulate in INSTANCE_CFG_DIRS so cleanup can
# tear everything down. Sets $LAST_DAEMON_PID for callers that need to wait.
#
# Usage: start_logoscore_instance <log_file> <modules_dir> <load_csv> <call1> [<call2> ...]
start_logoscore_instance() {
    local log_file="$1" mdir="$2" load_csv="$3"; shift 3
    local cfg_dir
    cfg_dir=$(mktemp -d); INSTANCE_CFG_DIRS+=("$cfg_dir")
    LAST_DAEMON_CFG="$cfg_dir"
    # CRITICAL: daemon and client MUST share the same effective TMPDIR — Qt
    # LocalSocket sockets are created under $TMPDIR (resolved via
    # QStandardPaths::TempLocation) and the client looks them up there. The sim's
    # top-level `export TMPDIR=/tmp` (legacy, for old logoscore path-length
    # workaround) would otherwise leave daemon at the macOS default
    # (/var/folders/.../T/, via env -i) and client at /tmp/ — mismatch → client
    # hangs at connect with no diagnostic. We unset TMPDIR on BOTH sides so they
    # converge on the macOS default.
    #
    # DYLD_INSERT_LIBRARIES is the fix for modules whose plugin was built with
    # `-undefined dynamic_lookup` (logos-module-builder default) — those plugins
    # have NO LC_LOAD_DYLIB entry for their `EXTERNAL_LIBS` dylib (e.g.
    # liblogosdelivery, liblogoschat), so dyld can't resolve their flat-namespace
    # symbols at dlopen time. Pre-loading the lib via DYLD_INSERT_LIBRARIES into
    # the daemon makes the subprocess (logos_host_qt) inherit it — but only when
    # the daemon is launched via `env -i` with a clean env (otherwise Qt's
    # QProcess sanitization strips DYLD_*). Per-module pairing happens in the
    # caller via the DYLD_PRELOAD_LIBS env. When unset, no injection happens and
    # modules without flat-namespace deps work fine.
    local -a daemon_env=(HOME="$HOME" PATH="$PATH" LOGOSCORE_CONFIG_DIR="$cfg_dir")
    [ -n "${DYLD_PRELOAD_LIBS:-}" ] && daemon_env+=(DYLD_INSERT_LIBRARIES="$DYLD_PRELOAD_LIBS")
    # Truncate first via `:>`, then daemon AND client both append via `>>`.
    # Critical: using bash `>` for the daemon leaves its fd in O_WRONLY (no
    # O_APPEND), so when the client interleaves appends via `>>` and then the
    # daemon writes again, the daemon's fd at its prior offset overwrites the
    # client's JSON response. O_APPEND on both sides keeps the file coherent.
    : > "$log_file"
    (cd "$STATE_DIR" && env -i "${daemon_env[@]}" \
        "$LOGOSCORE" -m "$mdir" -D </dev/null >>"$log_file" 2>&1) &
    LAST_DAEMON_PID=$!; INSTANCE_PIDS+=("$LAST_DAEMON_PID")
    # Two-phase readiness: client config file (daemon emitted) AND list-modules
    # responding with capability_module loaded. The config file alone is too
    # eager — the daemon's QtRO local server isn't always ready to accept
    # subprocess load requests yet, which made load-module return RPC failures.
    local t
    for t in $(seq 1 60); do
        [ -f "$cfg_dir/client/config.json" ] && break
        sleep 1
    done
    [ -f "$cfg_dir/client/config.json" ] || { echo "    daemon $LAST_DAEMON_PID failed to start (no client config)"; return 1; }
    for t in $(seq 1 60); do
        # 5s timeout per probe call: a daemon mid-subprocess-load can be momentarily
        # unresponsive over QtRO; without the timeout one stuck probe wedges the
        # whole sim.
        timeout 5 env -u TMPDIR LOGOSCORE_CONFIG_DIR="$cfg_dir" "$LOGOSCORE" --quiet --json list-modules 2>/dev/null \
            | grep -q '"capability_module".*"loaded"' && break
        sleep 1
    done
    # Even after list-modules shows capability_module "loaded", the daemon's
    # QtRO registry may not be fully ready to broker load-module RPCs (which
    # spawn new logos_host_qt subprocesses that handshake with capability_module
    # for tokens). Empirically, RPCs fired within the first ~3s of capability
    # loaded hang past a 30s timeout. Settle for a fixed window.
    sleep 5
    # Load modules in declared order; logoscore resolves their deps internally.
    # Each subprocess load takes ~1-5s; 30s/module is generous.
    local mod rc
    for mod in ${load_csv//,/ }; do
        echo "  [debug] cfg=$cfg_dir loading $mod..." >&2
        echo "=== CLIENT LOAD $mod ===" >> "$log_file"
        timeout 30 env -u TMPDIR LOGOSCORE_CONFIG_DIR="$cfg_dir" "$LOGOSCORE" --json load-module "$mod" \
            >>"$log_file" 2>&1
        rc=$?
        echo "=== rc=$rc ===" >> "$log_file"
        echo "  [debug] load $mod rc=$rc" >&2
        [ "$rc" -ne 0 ] && { echo "    load-module $mod failed (pid $LAST_DAEMON_PID, rc=$rc)"; return 1; }
    done
    # Issue per-call invocations against the running daemon. The top-level
    # `-c "X.method(args)"` flag is NOT a client — it spawns a SEPARATE daemon,
    # so it can never reach the modules we just loaded. The correct surface is
    # the `call` subcommand: `logoscore call <module> <method> <arg>...`.
    # `parse_call` splits our legacy "X.method(a,b,c)" string into the discrete
    # args the subcommand wants. Each successful call logs a JSON line
    # `{"method":"...","result":N,"status":"ok"}` — replaces the old "Method
    # call successful" marker that wait_method_calls used to grep for.
    local call mod meth args_str arg_tmp_dir
    arg_tmp_dir=$(mktemp -d); INSTANCE_CFG_DIRS+=("$arg_tmp_dir")
    for call in "$@"; do
        mod=${call%%.*}
        meth=${call#*.}; meth=${meth%%(*}
        args_str=${call#*\(}; args_str=${args_str%\)}
        # IFS split on comma; if args_str is empty, pass no args.
        local -a raw_args=() final_args=()
        [ -n "$args_str" ] && IFS=',' read -ra raw_args <<< "$args_str"
        # Wrap any digit-leading non-purely-numeric arg as @tmpfile to force
        # string typing — logoscore-cli's `call` parser auto-coerces numeric-
        # looking tokens to int/double, which mangles digit-prefixed identifiers
        # like wallet account IDs (e.g. "3SdWB8iLJ8Ct..." → int 3 → server-side
        # "failed to resolve account IDs"). The @file form bypasses coercion.
        local i=0 a
        for a in "${raw_args[@]+"${raw_args[@]}"}"; do
            if [[ "$a" =~ ^[0-9] ]] && [[ "$a" =~ [^0-9] ]]; then
                local f="$arg_tmp_dir/${RANDOM}_${i}.arg"
                printf '%s' "$a" > "$f"
                final_args+=("@$f")
            else
                final_args+=("$a")
            fi
            i=$((i+1))
        done
        # Default 180s timeout per call. Wallet open/startChat can take ~30s on
        # cold sequencer; mix peer joins ~5s. Bump via CALL_TIMEOUT env if needed.
        # Don't return on failure — keep dispatching remaining calls. Non-gifter
        # delivery_module.start()'s RPC reply times out (~20s QtRO ceiling) because
        # its async backend (gifter client registration + on-chain watcher) keeps
        # the Qt thread busy past the deadline, even though the underlying node
        # actually started fine. Subsequent calls (setRlnConfig, subscribe) MUST
        # still dispatch — they're independent of start()'s reply.
        timeout "${CALL_TIMEOUT:-180}" env -u TMPDIR LOGOSCORE_CONFIG_DIR="$cfg_dir" "$LOGOSCORE" --json call "$mod" "$meth" "${final_args[@]+"${final_args[@]}"}" \
            >>"$log_file" 2>&1 \
            || echo "    call failed: $call (pid $LAST_DAEMON_PID) — continuing"
    done
    return 0
}

# --- Node identity constants (4 mix nodes) ---
NODEKEYS=(
    "f98e3fba96c32e8d1967d460f1b79457380e1a895f7971cecc8528abe733781a"
    "09e9d134331953357bd38bbfce8edb377f4b6308b4f3bfbe85c610497053d684"
    "ed54db994682e857d77cd6fb81be697382dc43aa5cd78e16b0ec8098549f860e"
    "42f96f29f2d6670938b0864aced65a332dcf5774103b4c44ec4d0ea4ef3c47d6"
)
PEER_IDS=(
    "16Uiu2HAmPiEs2ozjjJF2iN2Pe2FYeMC9w4caRHKYdLdAfjgbWM6o"
    "16Uiu2HAmLtKaFaSWDohToWhWUZFLtqzYZGPFuXwKrojFVF6az5UF"
    "16Uiu2HAmTEDHwAziWUSz6ZE23h5vxG2o4Nn7GazhMor4bVuMXTrA"
    "16Uiu2HAmPwRKZajXtfb1Qsv45VVfRZgK3ENdfmnqzSrVm3BczF6f"
)
MIXKEYS=(
    "c86029e02c05a7e25182974b519d0d52fcbafeca6fe191fbb64857fb05be1a53"
    "b858ac16bbb551c4b2973313b1c8c8f7ea469fca03f1608d200bbf58d388ec7f"
    "d8bd379bb394b0f22dd236d63af9f1a9bc45266beffc3fbbe19e8b6575f2535b"
    "780fff09e51e98df574e266bf3266ec6a3a1ddfcf7da826a349a29c137009d49"
)
MIX_PUBKEYS=(
    "9231e86da6432502900a84f867004ce78632ab52cd8e30b1ec322cd795710c2a"
    "275cd6889e1f29ca48e5b9edb800d1a94f49f13d393a0ecf1a07af753506de6c"
    "e0ed594a8d506681be075e8e23723478388fb182477f7a469309a25e7076fc18"
    "8fd7a1a7c19b403d231452a9b1ea40eb1cc76f455d918ef8980e7685f9eeeb1f"
)
# --- Configurable parameters (override via environment) ---
NUM_NODES=${SIM_NUM_NODES:-4}
BASE_TCP_PORT=${SIM_BASE_TCP_PORT:-60001}
BASE_DISC_PORT=${SIM_BASE_DISC_PORT:-9001}
CLUSTER_ID=${SIM_CLUSTER_ID:-99}
NUM_SHARDS=1
CONTENT_TOPIC="/logos-chat/1/mix-test/proto"
TEST_MESSAGE_PREFIX="chatmixtest"
LOG_LEVEL=${SIM_LOG_LEVEL:-INFO}
CHAT_RECV_PORT=${SIM_CHAT_RECV_PORT:-60010}
CHAT_RECV2_PORT=${SIM_CHAT_RECV2_PORT:-60012}
CHAT_SEND_PORT=${SIM_CHAT_SEND_PORT:-60011}
SIM_NETWORK=${SIM_NETWORK:-local}
case "$SIM_NETWORK" in
  local|testnet) ;;
  *) die "SIM_NETWORK must be 'local' or 'testnet', got: $SIM_NETWORK";;
esac

# Timing floors: local sequencer ~15s blocks vs testnet ~60s + more variance.
if [ "$SIM_NETWORK" = testnet ]; then
    KADEMLIA_MIN_WAIT=${SIM_KADEMLIA_MIN_WAIT:-120}
    # Testnet block times + finality lag can stretch RLN tx confirmations to
    # multiple minutes per mix node. 4 nodes × ~5 min each + slack ≈ 30 min.
    KADEMLIA_HARD_CAP=${SIM_KADEMLIA_HARD_CAP:-1800}
    RECEIVER_MIN_WAIT=${SIM_RECEIVER_MIN_WAIT:-60}
    DELIVERY_TIMEOUT=${SIM_DELIVERY_TIMEOUT:-300}
    NODE_STARTUP_SLEEP=${SIM_NODE_STARTUP_SLEEP:-30}
    export LEZ_RLN_BLOCK_SEAL_SECS="${LEZ_RLN_BLOCK_SEAL_SECS:-90}"
else
    KADEMLIA_MIN_WAIT=${SIM_KADEMLIA_MIN_WAIT:-30}
    KADEMLIA_HARD_CAP=${SIM_KADEMLIA_HARD_CAP:-180}
    RECEIVER_MIN_WAIT=${SIM_RECEIVER_MIN_WAIT:-15}
    DELIVERY_TIMEOUT=${SIM_DELIVERY_TIMEOUT:-240}
    NODE_STARTUP_SLEEP=${SIM_NODE_STARTUP_SLEEP:-10}
fi
TESTNET_RPC_URL="https://testnet.lez.logos.co/"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) PLATFORM="darwin-arm64-dev"; EXT="dylib";;
  Linux-x86_64) PLATFORM="linux-x86_64-dev"; EXT="so";;
  Linux-aarch64) PLATFORM="linux-aarch64-dev"; EXT="so";;
  *) die "Unsupported platform";;
esac

STATE_DIR="$SCRIPT_DIR/.sim_state"
FRESH=0
for arg in "$@"; do [ "$arg" = "--fresh" ] && FRESH=1; done
[ "$FRESH" -eq 1 ] && rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"

SEQUENCER_PID=""
OWN_SEQUENCER=0
INSTANCE_PIDS=()
INSTANCE_CFG_DIRS=()
MODULES_DIRS=()
SENDER_PID=""
RECEIVER_PID=""
EXIT_CODE=1

cleanup() {
    set +u
    echo ""; echo "=== Shutting down ==="
    [ -n "$SENDER_PID" ] && kill "$SENDER_PID" 2>/dev/null || true
    [ -n "$RECEIVER_PID" ] && kill "$RECEIVER_PID" 2>/dev/null || true
    for pid in "${INSTANCE_PIDS[@]+"${INSTANCE_PIDS[@]}"}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; done
    pkill -f 'logos_host' 2>/dev/null || true
    [ "$OWN_SEQUENCER" -eq 1 ] && [ -n "$SEQUENCER_PID" ] && kill "$SEQUENCER_PID" 2>/dev/null || true
    for mdir in "${MODULES_DIRS[@]+"${MODULES_DIRS[@]}"}"; do [ -n "$mdir" ] && rm -rf "$mdir"; done
    for cdir in "${INSTANCE_CFG_DIRS[@]+"${INSTANCE_CFG_DIRS[@]}"}"; do [ -n "$cdir" ] && rm -rf "$cdir"; done
    echo "  Logs: $STATE_DIR"; echo "Done."; exit "$EXIT_CODE"
}
trap cleanup EXIT

echo "=== Mix + LEZ RLN Chat Simulation ($NUM_NODES nodes) ==="
echo "  Network:          $SIM_NETWORK"
[ "$SIM_NETWORK" = testnet ] && echo "  Testnet RPC:      $TESTNET_RPC_URL"
echo "  LEZ repo:         $LEZ_RLN_DIR"
echo "  Chat module:      $CHAT_MODULE_DIR"
echo "  Logos-chat:        $LOGOS_CHAT_DIR"
echo ""

pkill -f 'logos_host' 2>/dev/null || true; sleep 1
# Stale QtRO LocalServer sockets confuse capability_module lookups.
rm -f /tmp/logos_* 2>/dev/null || true

# ---------- Phase 1: Sequencer ----------
echo "[1/6] Sequencer..."
if [ "$SIM_NETWORK" = testnet ]; then
    # Fail fast if testnet RPC is unreachable before 10+ min of setup work.
    BLOCK_RESP=$(curl -sS -m 10 -X POST -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"getLastBlockId","params":[],"id":1}' \
        "$TESTNET_RPC_URL" 2>&1)
    case "$BLOCK_RESP" in
      *'"result"'*) log "  Testnet reachable: $(echo "$BLOCK_RESP" | grep -oE '"result":[0-9]+' | head -1)";;
      *) die "Testnet unreachable at $TESTNET_RPC_URL: $BLOCK_RESP";;
    esac
elif nc -z 127.0.0.1 3040 2>/dev/null && [ "$FRESH" -eq 0 ]; then
    SEQUENCER_PID=$(lsof -ti tcp:3040 2>/dev/null || true)
    echo "  Already running (PID $SEQUENCER_PID)"
else
    [ "$(nc -z 127.0.0.1 3040 2>/dev/null; echo $?)" = "0" ] && kill "$(lsof -ti tcp:3040 2>/dev/null)" 2>/dev/null || true; sleep 1
    rm -rf "$LEZ_RLN_DIR/lssa/rocksdb" "$LEZ_RLN_DIR/lssa/sequencer/service/bedrock_signing_key"

    # Pre-built binary path skips both the cargo build and the lssa auto-sync
    # (auto-sync needs full git history; shallow Docker clones break it).
    if [ -x "$LEZ_RLN_DIR/lssa/target/debug/sequencer_service" ]; then
        log "  Using pre-built sequencer"
        SEQ_BIN="./target/debug/sequencer_service"; SEQ_CFG="sequencer/service/configs/debug/sequencer_config.json"
    else
        # lssa rev must match what lez-rln's host-side client pins, else
        # DeserializeUnexpectedEnd from wire-format divergence.
        LSSA_REV=$(grep -oE '(rev|tag)\s*=\s*"[^"]+"' "$LEZ_RLN_DIR/lez-rln/Cargo.toml" | head -1 | sed 's/.*"\([^"]*\)"/\1/')
        [ -z "$LSSA_REV" ] && die "Could not extract lssa rev from lez-rln/Cargo.toml"
        if ! git -C "$LEZ_RLN_DIR/lssa" merge-base --is-ancestor "$LSSA_REV" HEAD 2>/dev/null; then
            log "  Pinning lssa to $LSSA_REV..."
            (cd "$LEZ_RLN_DIR/lssa" && git fetch --quiet --tags origin && git checkout --quiet "$LSSA_REV") \
                || die "lssa checkout $LSSA_REV failed"
        fi
        log "  Building sequencer..."
        if (cd "$LEZ_RLN_DIR/lssa" && cargo build --features standalone -p sequencer_service 2>&1 | tail -3); then
            SEQ_BIN="./target/debug/sequencer_service"; SEQ_CFG="sequencer/service/configs/debug/sequencer_config.json"
        elif (cd "$LEZ_RLN_DIR/lssa" && cargo build --features standalone -p sequencer_runner 2>&1 | tail -3); then
            SEQ_BIN="./target/debug/sequencer_runner"; SEQ_CFG="sequencer_runner/configs/debug"
        else die "sequencer build failed"; fi
    fi
    (cd "$LEZ_RLN_DIR/lssa" && env RUST_LOG=info "$SEQ_BIN" "$SEQ_CFG") >"$STATE_DIR/sequencer.log" 2>&1 &
    SEQUENCER_PID=$!; OWN_SEQUENCER=1; echo "  PID: $SEQUENCER_PID"
    for _ in $(seq 1 60); do nc -z 127.0.0.1 3040 2>/dev/null && break; sleep 1; done
    nc -z 127.0.0.1 3040 2>/dev/null || die "Sequencer failed to start"
    log "  Ready."
fi

# ---------- Phase 2: Deploy programs ----------
echo "[2/6] Deploying programs..."
# `local` -> dev/ (re-init each run); `testnet` -> testnet/ (persistent
# wallet + on-chain state). wallet_config.json under each picks the sequencer.
WALLET_HOME_SUBDIR=$([ "$SIM_NETWORK" = testnet ] && echo testnet || echo dev)
export NSSA_WALLET_HOME_DIR="$LEZ_RLN_DIR/$WALLET_HOME_SUBDIR"
export WALLET_CONFIG="$NSSA_WALLET_HOME_DIR/wallet_config.json"
export WALLET_STORAGE="$NSSA_WALLET_HOME_DIR/storage.json"
TREE_ID_HEX="000102030405060708090a0b0c0d0e0f10111213141516171a05100200000001"
GIFTER_ACCOUNT_FILE="$HOME/.logos-lez-rln/payment_account_${TREE_ID_HEX}.txt"

# Local: clean wallet each run so run_setup re-deploys.
# Testnet: persist wallet + on-chain state; run_setup short-circuits via
# is_initialized() into create_funded_user.
if [ "$SIM_NETWORK" = local ] && [ "${SIM_PERSIST_LOCAL:-0}" != "1" ]; then
    rm -f "$WALLET_CONFIG" "$WALLET_STORAGE"
fi

# Testnet bootstrap: seed wallet + supply-holding sidecar from the
# submodule-shipped artifacts on first run. After that, create_funded_user
# draws fresh per-dev payment accounts from the shared supply.
if [ "$SIM_NETWORK" = testnet ]; then
    # Copy shipped seed -> runtime location iff runtime is missing.
    seed_copy() {
        local label="$1" src="$2" dst="$3"
        [ -f "$dst" ] && return 0
        [ -f "$src" ] || return 0
        log "  Seeding $label -> $dst"
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
    }
    seed_copy "testnet wallet" \
        "$LEZ_RLN_DIR/testnet/storage.json.seed" "$WALLET_STORAGE"
    seed_copy "supply holding sidecar" \
        "$LEZ_RLN_DIR/testnet/supply_holding.txt" \
        "$HOME/.logos-lez-rln/supply_holding_${TREE_ID_HEX}.txt"
    seed_copy "payment account sidecar" \
        "$LEZ_RLN_DIR/testnet/payment_account.txt" \
        "$HOME/.logos-lez-rln/payment_account_${TREE_ID_HEX}.txt"
fi

# Slim mode (SIM_SLIM=1, testnet only): skip run_setup when the shipped
# config_account + cached payment_account are both present — lets fresh
# clones avoid building lez-rln/run_setup. The shared payment_account is
# signed in storage.json.seed and has enough RLNTOK for ~1M Register txs.
# Experimental; the default run_setup path is better-tested.
CONFIG_ACCOUNT_SEED="$LEZ_RLN_DIR/testnet/config_account.txt"
SLIM=0
if [ "$SIM_NETWORK" = testnet ] && [ "${SIM_SLIM:-0}" = "1" ] \
        && [ -f "$CONFIG_ACCOUNT_SEED" ] && [ -f "$GIFTER_ACCOUNT_FILE" ]; then
    SLIM=1
fi
if [ "$SLIM" = "1" ]; then
    log "  Slim mode: skipping run_setup (using shipped config_account + cached payment_account)"
    CONFIG_ACCOUNT=$(tr -d '\n\r' < "$CONFIG_ACCOUNT_SEED")
    GIFTER_ACCOUNT=$(cat "$GIFTER_ACCOUNT_FILE")
else
    if [ -x "$LEZ_RLN_DIR/lez-rln/target/debug/run_setup" ]; then
        SETUP_OUTPUT=$(cd "$LEZ_RLN_DIR/lez-rln" && ./target/debug/run_setup 2>&1) || die "run_setup failed"
    else
        SETUP_OUTPUT=$(cd "$LEZ_RLN_DIR/lez-rln" && cargo run --bin run_setup 2>&1) || die "run_setup failed"
    fi
    echo "$SETUP_OUTPUT" | tail -4
    # Both deploy + already-initialized branches print "Config account:".
    CONFIG_ACCOUNT=$(echo "$SETUP_OUTPUT" | grep -oE 'Config account:\s+\S+' | awk '{print $NF}' || true)
    [ -z "$CONFIG_ACCOUNT" ] && die "Failed to parse config account"
    GIFTER_ACCOUNT=$(cat "$GIFTER_ACCOUNT_FILE" 2>/dev/null || true)
    [ -z "$GIFTER_ACCOUNT" ] && die "Gifter account not found at $GIFTER_ACCOUNT_FILE"
fi
echo "  CONFIG_ACCOUNT=$CONFIG_ACCOUNT"
echo "  GIFTER_ACCOUNT=$GIFTER_ACCOUNT"

# EIP-191 auth fixtures: secp256k1 keys + gifter (mix node 0) allowlist.
# Committed test fixtures only — do NOT reuse in prod.
GIFTER_AUTH_DIR="$SCRIPT_DIR/fixtures/gifter_auth"
# shellcheck disable=SC1091
source "$GIFTER_AUTH_DIR/keys.env"
# shellcheck disable=SC1091
source "$GIFTER_AUTH_DIR/addresses.env"
GIFTER_ALLOWLIST="$ADDR_MIX1,$ADDR_MIX2,$ADDR_MIX3,$ADDR_SENDER,$ADDR_RECEIVER,$ADDR_RECEIVER2"
echo "  Gifter allowlist: $GIFTER_ALLOWLIST"

# ---------- Phase 3: Prerequisites ----------
echo "[3/6] Verifying prerequisites..."
# Use liblogos's native SDK pin — overriding to 1468180b breaks liblogos
# 7df6195's source (uses old requestObject/onEvent shapes). Plugins built
# via logos-module-builder use SDK 8bdbd13 transitively; smoke load shows
# they're ABI-compatible with the native build.
LOGOSCORE="${LOGOSCORE:-$(nix build github:logos-co/logos-logoscore-cli --no-link --print-out-paths)/bin/logoscore}"

# Build .lgx bundles for all four plugins. nix bundle is cached so this is fast
# after the first run. The new logoscore-cli discovers modules by reading
# manifest.json from each module subdir, not raw .dylib filenames.
log "  Bundling .lgx packages..."
lgx_from() {
    local dir="$1" attr="$2"
    local out_link store_path lgx
    out_link=$(mktemp -d)/result
    (cd "$dir" && nix bundle --bundler github:logos-co/nix-bundle-lgx --out-link "$out_link" ".#$attr" >/dev/null 2>&1) \
        || die "nix bundle failed in $dir for $attr"
    store_path=$(readlink "$out_link")
    lgx=$(find "$store_path" -maxdepth 1 -name "*.lgx" | head -1)
    rm -f "$out_link"; rmdir "$(dirname "$out_link")" 2>/dev/null || true
    [ -f "$lgx" ] || die "no .lgx in bundle output for $attr (looked at $store_path)"
    printf '%s' "$lgx"
}
# Per-module overrides let dev shortcut to a previously-built .lgx in
# /nix/store/<hash>/<name>.lgx, useful when an upstream cargo/git-source fetch
# fails (e.g. crates.io 403s on librln-mix vendor) but the cached .lgx is
# still good.
WALLET_LGX=${WALLET_LGX:-$(lgx_from "$LEZ_RLN_DIR" "wallet-module")}
RLN_LGX=${RLN_LGX:-$(lgx_from "$LEZ_RLN_DIR" "logos-rln-module")}
DELIVERY_LGX=${DELIVERY_LGX:-$(lgx_from "$DELIVERY_MODULE_DIR" "lib")}
CHAT_LGX=${CHAT_LGX:-$(lgx_from "$CHAT_MODULE_DIR" "lib")}

# liblogosdelivery.dylib is stripped by nix-bundle-lgx, so we patch it into the
# delivery_module's runtime dir post-install. The dylib is the Nim-built backend
# behind the C++ delivery_module_plugin.dylib; without it the plugin's dlopen
# fails with `symbol not found: _logosdelivery_get_available_configs`. Pick the
# 17-symbol version — older 8-symbol builds linger in /nix/store and would
# silently load but fail at first call (missing FFI entrypoints).
pick_lib_with_min_symbols() {
    local pattern="$1" symbol_prefix="$2" min_count="$3"
    local cand
    for cand in $(find /nix/store -maxdepth 5 -path "$pattern" 2>/dev/null); do
        local n; n=$(nm -gU "$cand" 2>/dev/null | grep -c "$symbol_prefix") || true
        [ "${n:-0}" -ge "$min_count" ] && { printf '%s' "$cand"; return 0; }
    done
    return 1
}
if [ -z "${DELIVERY_EXTRA_LIB:-}" ]; then
    # Prefer the vendor working-copy build over /nix/store hits — the
    # local build has the gifter mount code ("RLN gifter service mounted for
    # mix"). The nix-store builds of logos-delivery-module-lib (e.g.
    # ng60yfx... 48MB) lack gifter mount and produce 14/15 PASS at best with
    # receiver-message-delivery the only fail. The local build is 53MB+.
    if [ -f "$DELIVERY_DIR/build/liblogosdelivery.$EXT" ]; then
        DELIVERY_EXTRA_LIB="$DELIVERY_DIR/build/liblogosdelivery.$EXT"
    else
        DELIVERY_EXTRA_LIB=$(pick_lib_with_min_symbols "*logos-delivery-module-lib*/lib/liblogosdelivery.$EXT" "_logosdelivery_" 15)
    fi
fi
[ -f "$DELIVERY_EXTRA_LIB" ] || die "liblogosdelivery.$EXT (17-symbol) not found; build delivery-module first or set DELIVERY_EXTRA_LIB"

# chat_module has the same flat-namespace gap on liblogoschat.dylib.
if [ -z "${CHAT_EXTRA_LIB:-}" ]; then
    if [ -f "$LOGOS_CHAT_DIR/build/liblogoschat.$EXT" ]; then
        CHAT_EXTRA_LIB="$LOGOS_CHAT_DIR/build/liblogoschat.$EXT"
    else
        CHAT_EXTRA_LIB=$(find /nix/store -maxdepth 5 -path "*logos-chat-module*/lib/liblogoschat.$EXT" 2>/dev/null | head -1)
    fi
fi
[ -f "$CHAT_EXTRA_LIB" ] || die "liblogoschat.$EXT not found; build chat lib first or set CHAT_EXTRA_LIB"
for lgx in "$WALLET_LGX" "$RLN_LGX" "$DELIVERY_LGX" "$CHAT_LGX"; do
    [ -f "$lgx" ] || die "Missing .lgx: $lgx"
done
log "  All .lgx bundles present."

# ---------- Phase 4: Start mix nodes ----------
echo "[4/6] Starting $NUM_NODES mix+LEZ nodes..."
LOAD_ORDER="logos_execution_zone,liblogos_rln_module,delivery_module"
WALLET_CALL="logos_execution_zone.open($WALLET_CONFIG,$WALLET_STORAGE)"
BOOTSTRAP_PEER="/ip4/127.0.0.1/tcp/$BASE_TCP_PORT/p2p/${PEER_IDS[0]}"

# All RLN memberships are issued at runtime by the gifter on node 0 — no
# off-chain setup_credentials / pre-registration step.

for i in $(seq 0 $((NUM_NODES - 1))); do
    TCP_PORT=$((BASE_TCP_PORT + i)); DISC_PORT=$((BASE_DISC_PORT + i))
    NODE_CONFIG="$STATE_DIR/node${i}_config.json"
    LOG_FILE="$STATE_DIR/node${i}.log"
    KAD_BOOTSTRAP="[]"; [ "$i" -gt 0 ] && KAD_BOOTSTRAP="[\"$BOOTSTRAP_PEER\"]"
    PEER_LIST=""
    for j in $(seq 0 $((NUM_NODES - 1))); do
        [ "$j" -eq "$i" ] && continue
        [ -n "$PEER_LIST" ] && PEER_LIST="$PEER_LIST,"
        PEER_LIST="$PEER_LIST\"/ip4/127.0.0.1/tcp/$((BASE_TCP_PORT + j))/p2p/${PEER_IDS[$j]}\""
    done
    STATIC_PEERS="[$PEER_LIST]"

    GIFTER_FIELDS=""
    if [ "$i" -eq 0 ]; then
        GIFTER_FIELDS="\"mixGifterService\": true, \"mixGifterWalletAccount\": \"$GIFTER_ACCOUNT\", \"mixGifterAllowlist\": \"$GIFTER_ALLOWLIST\","
    else
        # KEY_MIX{1..3} align with non-gifter nodes 1..3.
        AUTH_KEY_VAR="KEY_MIX$i"
        GIFTER_FIELDS="\"mixGifterNode\": \"$BOOTSTRAP_PEER\", \"mixGifterWalletAccount\": \"$GIFTER_ACCOUNT\", \"mixGifterAuthKey\": \"${!AUTH_KEY_VAR}\","
    fi

    cat > "$NODE_CONFIG" <<EOF
{
  "clusterId": $CLUSTER_ID,
  "numShardsInNetwork": $NUM_SHARDS,
  "listenAddress": "127.0.0.1",
  "tcpPort": $TCP_PORT,
  "websocketPort": $((TCP_PORT + 1000)),
  "discv5UdpPort": $DISC_PORT,
  "nat": "extip:127.0.0.1",
  "extMultiAddrs": ["/ip4/127.0.0.1/tcp/$TCP_PORT"],
  "extMultiAddrsOnly": true,
  "nodekey": "${NODEKEYS[$i]}",
  "staticnodes": $STATIC_PEERS,
  "relay": true,
  "lightpush": true,
  "filter": true,
  "mix": true,
  "mixkey": "${MIXKEYS[$i]}",
  "mixOnchainLEZ": true,
  $GIFTER_FIELDS
  "enableKadDiscovery": true,
  "kadBootstrapNodes": $KAD_BOOTSTRAP,
  "peerExchange": false,
  "rendezvous": false,
  "colocationLimit": 0,
  "logLevel": "$LOG_LEVEL"
}
EOF

    MDIR=$(mktemp -d); MODULES_DIRS+=("$MDIR")
    install_lgx "$MDIR" "$WALLET_LGX"
    install_lgx "$MDIR" "$RLN_LGX"
    install_lgx "$MDIR" "$DELIVERY_LGX"
    install_extra_lib "$MDIR" delivery_module "$DELIVERY_EXTRA_LIB"
    # Optional delivery_module_plugin.dylib override (same rationale as
    # CHAT_PLUGIN_OVERRIDE): drop-in replacement carrying the createNode
    # patch that installs logosdelivery_set_rln_fetcher unconditionally, so
    # non-gifter mix nodes — which never call setRlnConfig from outside —
    # still get the C++→Nim rln_fetcher trampoline wired. Otherwise their
    # spam-protection groupManager's poll loop hits "RLN fetcher not
    # registered", cachedProof never lands, isReady stays false, and every
    # sphinx hop fails "Failed to generate spam protection proof for next
    # hop: Plugin not ready" → SURB timeout on sender.
    if [ -n "${DELIVERY_PLUGIN_OVERRIDE:-}" ] && [ -f "$DELIVERY_PLUGIN_OVERRIDE" ]; then
        cp "$DELIVERY_PLUGIN_OVERRIDE" "$MDIR/delivery_module/delivery_module_plugin.dylib"
        codesign --force --sign - "$MDIR/delivery_module/delivery_module_plugin.dylib" 2>/dev/null || true
    fi

    log "  Starting node $i (port $TCP_PORT)..."
    # Node 0 is the gifter — it must self-register on-chain (paying its own
    # RLNTOK from $GIFTER_ACCOUNT) so its mix init can complete and the gifter
    # service can mount. Nodes 1-3 register via the gifter protocol AUTOMATICALLY
    # during Nim startNode() (triggered by mixGifterNode config), so the sim
    # must NOT call setRlnConfig for them — that's the gifter's job and a
    # manual call would overwrite the gifter-assigned leaf. The new
    # OnchainLEZGroupManager.register() explicitly bans Self-registration to
    # force everything through selfRegisterRln (for the gifter) or the gifter
    # protocol (for everyone else).
    if [ "$i" -eq 0 ]; then
        # Wallet needs an explicit sync to bring its account state up to current
        # chain height before register_member can construct a valid tx — open()
        # alone leaves last_synced_block=0 even though storage.json knows about
        # accounts at higher chain_index values. Query sequencer for current
        # head and pass as the sync target.
        # Probe sequencer for current head. On testnet there's no local
        # server on 3040; use the testnet RPC URL instead. Wrap in || true
        # to defuse set -e under pipefail when curl returns connection-refused.
        if [ "$SIM_NETWORK" = "local" ]; then
            CHAIN_HEAD=$(curl -sS -m 5 -X POST -H 'Content-Type: application/json' \
                --data '{"jsonrpc":"2.0","method":"getLastBlockId","params":[],"id":1}' \
                http://127.0.0.1:3040/ 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"])' 2>/dev/null || true)
        else
            CHAIN_HEAD=$(curl -sS -m 10 -X POST -H 'Content-Type: application/json' \
                --data '{"jsonrpc":"2.0","method":"getLastBlockId","params":[],"id":1}' \
                "$TESTNET_RPC_URL" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"])' 2>/dev/null || true)
        fi
        : "${CHAIN_HEAD:=10000}"
        log "    chain head=$CHAIN_HEAD (for wallet sync)"
        # selfRegisterRln args go via @file JSON object — logoscore-cli's `call`
        # subcommand auto-coerces digit-leading positional args (e.g. base58
        # accounts like "38nxK...") to int. Wrapping all three args inside a
        # single JSON blob whose first char is `{` dodges that coercion (same
        # trick createNode already uses for its config blob).
        REGISTER_ARGS="$STATE_DIR/node${i}_register.json"
        cat > "$REGISTER_ARGS" <<EOF
{"config":"$CONFIG_ACCOUNT","wallet":"$GIFTER_ACCOUNT","rate":100}
EOF
        EXTRA_CALLS=(
            "logos_execution_zone.sync_to_block($CHAIN_HEAD)"
            "delivery_module.selfRegisterRlnJson(@$REGISTER_ARGS)"
        )
        EXPECTED_CALLS=6
    else
        EXTRA_CALLS=()
        EXPECTED_CALLS=5
    fi
    # For non-gifter mix nodes: install C++ rln_fetcher trampoline with
    # placeholder config IMMEDIATELY AFTER createNode, BEFORE start. The
    # trampoline only needs deliveryCtx (createNode provides it); placing it
    # before start ensures it's dispatched while the daemon's Qt event loop
    # is still responsive. Nim's internal gifter registration during start()
    # later calls mix_lez_client.setRlnConfig to overwrite the placeholder
    # config with real account/leaf — the C++ fetcher install persists.
    # Without this, the spam-protection poll loop's callRlnFetcher returns
    # "RLN fetcher not registered", cachedProof never lands, every sphinx
    # hop fails "Plugin not ready". setRlnConfig also can't be issued after
    # start() because start()'s async backend saturates Qt indefinitely,
    # blocking all subsequent RPCs to delivery_module.
    if [ "$i" -ne 0 ]; then
        PRE_START_CALLS=("delivery_module.setRlnConfig($CONFIG_ACCOUNT,0)")
    else
        PRE_START_CALLS=()
    fi
    DYLD_PRELOAD_LIBS="$DELIVERY_EXTRA_LIB" \
    start_logoscore_instance "$LOG_FILE" "$MDIR" "$LOAD_ORDER" \
        "$WALLET_CALL" \
        "delivery_module.createNode(@$NODE_CONFIG)" \
        "${PRE_START_CALLS[@]+"${PRE_START_CALLS[@]}"}" \
        "delivery_module.start()" \
        "${EXTRA_CALLS[@]+"${EXTRA_CALLS[@]}"}" \
        "delivery_module.subscribe($CONTENT_TOPIC)" || true
    wait_method_calls "$LOG_FILE" "$EXPECTED_CALLS" 90 1 || true
    if [ "${N:-0}" -ge "$EXPECTED_CALLS" ]; then
        log "    Node $i ready ($N/$EXPECTED_CALLS calls) PID: $LAST_DAEMON_PID"
    else
        echo "  WARNING: Node $i: $N/$EXPECTED_CALLS calls"
    fi
    NODE_CFG_DIRS[$i]="$LAST_DAEMON_CFG"
    sleep "$NODE_STARTUP_SLEEP"
done

# (Post-loop fetcher wiring removed — moved into the per-node EXTRA_CALLS in
#  Phase 4 above. Doing it externally after daemon stabilization doesn't work
#  because delivery_module's Qt event loop is saturated by chronos poll loops
#  within seconds of start(), making subsequent RPCs to delivery_module hang
#  indefinitely. The early-batch placeholder install runs before Qt blocks.)
echo ""

# ---------- Phase 5: Chat module sender/receiver ----------
echo "[5/6] Starting chat module instances..."

# Wait for all nodes ready (gifter registrations finalize during startup).
for i in $(seq 0 $((NUM_NODES - 1))); do
    wait_method_calls "$STATE_DIR/node${i}.log" 5 120 2 || true
done

# Wait for RLN root convergence. Mix pool is seeded from each node's
# mixNodes config (processBootNodes), so kademlia isn't required for routing —
# the kad-peer count is logged only for diagnostics.
echo "  Waiting for kademlia propagation + RLN convergence..."
KADEMLIA_T0=$SECONDS
# Block chat startup until every mix hop has RLN credentials confirmed
# on-chain — unregistered hops drop sphinx packets (Plugin not ready).
REQUIRED_CLIENT_REGS=$((NUM_NODES - 1))
while true; do
    ELAPSED=$((SECONDS - KADEMLIA_T0))
    GR=$(sed 's/\x1b\[[0-9;]*m//g' "$STATE_DIR/node0.log" 2>/dev/null | grep -c "RLN gifter registration succeeded" || true); GR=${GR:-0}
    SELF=$(sed 's/\x1b\[[0-9;]*m//g' "$STATE_DIR/node0.log" 2>/dev/null | grep -c "Gifter self-registered as mix relay" || true); SELF=${SELF:-0}
    LR=0
    MIX_PEERS_PER_NODE=""
    for i in $(seq 0 $((NUM_NODES - 1))); do
        LOG="$STATE_DIR/node${i}.log"
        L=$(sed 's/\x1b\[[0-9;]*m//g' "$LOG" 2>/dev/null | grep -c "Polled valid roots\|Fetched roots from\|valid_roots\|OnchainLEZGroupManager initialized\|Wired LEZ callbacks" || true)
        LR=$((LR + L))
        MP=$(sed 's/\x1b\[[0-9;]*m//g' "$LOG" 2>/dev/null | grep -c "mix peer added via kademlia lookup" || true); MP=${MP:-0}
        MIX_PEERS_PER_NODE="${MIX_PEERS_PER_NODE}n${i}=${MP} "
    done
    if [ "$ELAPSED" -ge "$KADEMLIA_MIN_WAIT" ] && [ "$GR" -ge "$REQUIRED_CLIENT_REGS" ] && [ "$SELF" -ge 1 ] && [ "$LR" -ge 40 ]; then break; fi
    [ "$ELAPSED" -ge "$KADEMLIA_HARD_CAP" ] && break
    sleep 1
done
log "  Kademlia ready after $((SECONDS - KADEMLIA_T0))s ($GR/$REQUIRED_CLIENT_REGS client regs, self=$SELF, $LR LEZ root events, kad mix peers: $MIX_PEERS_PER_NODE)"

RECEIVER_LOG="$STATE_DIR/chat_receiver.log"
SENDER_LOG="$STATE_DIR/chat_sender.log"

# Build mix node list (multiaddr:mixPubKey) for chat config.
MIXNODE_LIST=""
for j in $(seq 0 $((NUM_NODES - 1))); do
    [ -n "$MIXNODE_LIST" ] && MIXNODE_LIST="$MIXNODE_LIST,"
    MIXNODE_LIST="$MIXNODE_LIST\"/ip4/127.0.0.1/tcp/$((BASE_TCP_PORT + j))/p2p/${PEER_IDS[$j]}:${MIX_PUBKEYS[$j]}\""
done

# Stage wallet + RLN + chat modules for a logoscore instance.
stage_chat_module() {
    local MDIR=$1
    install_lgx "$MDIR" "$WALLET_LGX"
    install_lgx "$MDIR" "$RLN_LGX"
    install_lgx "$MDIR" "$CHAT_LGX"
    install_extra_lib "$MDIR" chat_module "$CHAT_EXTRA_LIB"
    # Optional plugin override: if CHAT_PLUGIN_OVERRIDE is set, replace the
    # chat_module_plugin.dylib that came out of the pinned CHAT_LGX with a
    # locally-rebuilt one. Used to ship the onInit auto-wire patch that sets
    # m_impl.logosAPI without a separate initLogos RPC (chat .lgx rebuild
    # itself is blocked by crates.io 403 on librln-mix-2.0.0-vendor-staging).
    if [ -n "${CHAT_PLUGIN_OVERRIDE:-}" ] && [ -f "$CHAT_PLUGIN_OVERRIDE" ]; then
        cp "$CHAT_PLUGIN_OVERRIDE" "$MDIR/chat_module/chat_module_plugin.dylib"
        codesign --force --sign - "$MDIR/chat_module/chat_module_plugin.dylib" 2>/dev/null || true
    fi
}

CHAT_LOAD_ORDER="logos_execution_zone,liblogos_rln_module,chat_module"

# --- Receiver ---
RECV_MDIR=$(mktemp -d); MODULES_DIRS+=("$RECV_MDIR")
stage_chat_module "$RECV_MDIR"

RECV_CONFIG="$STATE_DIR/chat_receiver_config.json"
# Static peers so chat nodes join the relay mesh.
CHAT_STATIC_PEERS=""
for j in $(seq 0 $((NUM_NODES - 1))); do
    [ -n "$CHAT_STATIC_PEERS" ] && CHAT_STATIC_PEERS="$CHAT_STATIC_PEERS,"
    CHAT_STATIC_PEERS="$CHAT_STATIC_PEERS\"/ip4/127.0.0.1/tcp/$((BASE_TCP_PORT + j))/p2p/${PEER_IDS[$j]}\""
done
cat > "$RECV_CONFIG" <<EOF
{
  "name": "receiver",
  "clusterId": $CLUSTER_ID,
  "shardId": 0,
  "port": $CHAT_RECV_PORT,
  "mixEnabled": true,
  "mixNodes": [$MIXNODE_LIST],
  "destPeerAddr": "$BOOTSTRAP_PEER",
  "minMixPoolSize": 4,
  "gifterNodeAddr": "$BOOTSTRAP_PEER",
  "gifterAuthKey": "$KEY_RECEIVER",
  "staticPeers": [$CHAT_STATIC_PEERS]
}
EOF

# Prefix with byte 0xff so the hex string starts with letter 'f', dodging
# logoscore-cli's positional-arg auto-coercion (digit-leading args get cast to
# qulonglong, truncating at the first non-digit — for hex-of-ASCII that
# corrupts the payload AND yields odd length, which hexToSeqByte rejects).
TEST_MSG_HEX=$(printf '\xff%s' "$TEST_MESSAGE_PREFIX" | xxd -p | tr -d '\n')

log "  Starting receiver..."
# Drop the legacy hardcoded setRlnConfig call — the new chat client registers
# via the gifter protocol during startChat() (using gifterNodeAddr/gifterAuthKey
# from the chat config), and the gifter assigns the leaf dynamically. A manual
# setRlnConfig would overwrite the gifter-assigned leaf.
DYLD_PRELOAD_LIBS="$CHAT_EXTRA_LIB" \
start_logoscore_instance "$RECEIVER_LOG" "$RECV_MDIR" "$CHAT_LOAD_ORDER" \
    "$WALLET_CALL" \
    "chat_module.initChat(@$RECV_CONFIG)" \
    "chat_module.setEventCallback()" \
    "chat_module.startChat()" \
    "chat_module.createIntroBundle()" || true
RECEIVER_PID="$LAST_DAEMON_PID"
RECEIVER_CFG_DIR="$LAST_DAEMON_CFG"
log "  Receiver PID: $RECEIVER_PID"

RECV_EXPECTED=5
wait_method_calls "$RECEIVER_LOG" "$RECV_EXPECTED" 180 2 || true
log "  Receiver method calls: $N/$RECV_EXPECTED"

# Extract intro bundle (emitted as chatCreateIntroBundleResult). The new chat
# module logs IntroBundleCreated with the bundle as a decimal byte array, e.g.
# bundle="[108, 111, 103, ...]" — decode bytes to recover the string form.
INTRO_BUNDLE=""
for t in $(seq 1 30); do
    INTRO_BUNDLE=$(sed 's/\x1b\[[0-9;]*m//g' "$RECEIVER_LOG" 2>/dev/null \
        | grep -oE 'bundle="\[[0-9, ]+\]"' \
        | head -1 \
        | sed -E 's/bundle="\[//;s/\]"$//' \
        | awk -F', *' '{for(i=1;i<=NF;i++) printf "%c",$i}')
    [ -n "$INTRO_BUNDLE" ] && break; sleep 2
done
if [ -n "$INTRO_BUNDLE" ]; then
    log "  Receiver intro bundle: ${INTRO_BUNDLE:0:40}..."
else
    log "  WARNING: Could not extract intro bundle from receiver log"
fi

# Wait for async startChat (Waku client started) + a floor for the filter
# subscription to propagate through the relay mesh.
echo "  Waiting for receiver to join mix network..."
JOIN_T0=$SECONDS
while true; do
    ELAPSED=$((SECONDS - JOIN_T0))
    RS=$(grep -c "Waku client started" "$RECEIVER_LOG" 2>/dev/null || true); RS=${RS:-0}
    [ "$ELAPSED" -ge "$RECEIVER_MIN_WAIT" ] && [ "$RS" -ge 1 ] && break
    [ "$ELAPSED" -ge 60 ] && break
    sleep 1
done
log "  Receiver joined after $((SECONDS - JOIN_T0))s"

# --- Receiver 2 (optional, demonstrates sender reusing membership for multiple convos) ---
RECEIVER2_LOG="$STATE_DIR/chat_receiver2.log"
RECEIVER2_PID=""
RECEIVER2_CFG_DIR=""
INTRO_BUNDLE2=""
if [ "${SIM_RECEIVER2:-0}" = "1" ]; then
    RECV2_MDIR=$(mktemp -d); MODULES_DIRS+=("$RECV2_MDIR")
    stage_chat_module "$RECV2_MDIR"

    RECV2_CONFIG="$STATE_DIR/chat_receiver2_config.json"
    cat > "$RECV2_CONFIG" <<EOF
{
  "name": "receiver2",
  "clusterId": $CLUSTER_ID,
  "shardId": 0,
  "port": $CHAT_RECV2_PORT,
  "mixEnabled": true,
  "mixNodes": [$MIXNODE_LIST],
  "destPeerAddr": "$BOOTSTRAP_PEER",
  "minMixPoolSize": 4,
  "gifterNodeAddr": "$BOOTSTRAP_PEER",
  "gifterAuthKey": "$KEY_RECEIVER2",
  "staticPeers": [$CHAT_STATIC_PEERS]
}
EOF

    log "  Starting receiver2..."
    DYLD_PRELOAD_LIBS="$CHAT_EXTRA_LIB" \
    start_logoscore_instance "$RECEIVER2_LOG" "$RECV2_MDIR" "$CHAT_LOAD_ORDER" \
        "$WALLET_CALL" \
        "chat_module.initChat(@$RECV2_CONFIG)" \
        "chat_module.setEventCallback()" \
        "chat_module.startChat()" \
        "chat_module.createIntroBundle()" || true
    RECEIVER2_PID="$LAST_DAEMON_PID"
    RECEIVER2_CFG_DIR="$LAST_DAEMON_CFG"
    log "  Receiver2 PID: $RECEIVER2_PID"

    wait_method_calls "$RECEIVER2_LOG" 5 180 2 || true
    log "  Receiver2 method calls: $N/5"

    # Extract receiver2's intro bundle
    for t in $(seq 1 30); do
        INTRO_BUNDLE2=$(sed 's/\x1b\[[0-9;]*m//g' "$RECEIVER2_LOG" 2>/dev/null \
            | grep -oE 'bundle="\[[0-9, ]+\]"' \
            | head -1 \
            | sed -E 's/bundle="\[//;s/\]"$//' \
            | awk -F', *' '{for(i=1;i<=NF;i++) printf "%c",$i}')
        [ -n "$INTRO_BUNDLE2" ] && break; sleep 2
    done
    [ -n "$INTRO_BUNDLE2" ] && log "  Receiver2 intro bundle: ${INTRO_BUNDLE2:0:40}..." \
        || log "  WARNING: Could not extract receiver2 intro bundle"

    # Wait for receiver2 to join
    echo "  Waiting for receiver2 to join mix network..."
    R2_JOIN_T0=$SECONDS
    while true; do
        R2S=$(grep -c "Waku client started" "$RECEIVER2_LOG" 2>/dev/null || true)
        [ "$((SECONDS - R2_JOIN_T0))" -ge "$RECEIVER_MIN_WAIT" ] && [ "${R2S:-0}" -ge 1 ] && break
        [ "$((SECONDS - R2_JOIN_T0))" -ge 60 ] && break
        sleep 1
    done
    log "  Receiver2 joined after $((SECONDS - R2_JOIN_T0))s"
fi

# --- Sender ---
# Interactive infra-only mode (SIM_INFRA_ONLY=1): skip headless sender, print
# the env vars + intro bundle so a human-driven GUI client (logos-chat-ui-app)
# can act as the sender. Sim keeps sequencer + mix nodes + receiver running
# and polls for incoming messages until SIGINT.
if [ "${SIM_INFRA_ONLY:-0}" = "1" ]; then
    echo
    echo "======================================================================"
    echo "  Infra mode: receiver running headless, sender = your GUI client."
    echo "======================================================================"
    echo
    echo "1) Stage the standalone chat-ui-app (one-time):"
    echo "   bash $SCRIPT_DIR/setup_chat_ui_app.sh"
    echo
    echo "2) Launch the GUI with these env vars set:"
    echo
    cat <<EOF
export CHAT_NAME="sender_gui"
export CHAT_CLUSTER_ID=$CLUSTER_ID
export CHAT_SHARD_ID=0
export CHAT_PORT=$CHAT_SEND_PORT
export CHAT_DEST_PEER_ADDR="$BOOTSTRAP_PEER"
export CHAT_GIFTER_NODE_ADDR="$BOOTSTRAP_PEER"
export CHAT_GIFTER_AUTH_KEY="$KEY_SENDER"
export CHAT_MIN_MIX_POOL_SIZE=4
export CHAT_MIX_NODES='$(echo "$MIXNODE_LIST" | tr -d '"')'
export CHAT_STATIC_PEERS='$(echo "$CHAT_STATIC_PEERS" | tr -d '"')'

/tmp/chat_ui_app_staged/bin/logos-chat-ui-app
EOF
    echo
    echo "3) In the GUI: Ctrl+I (Initialize Chat) → Ctrl+S (Start Chat) →"
    echo "   File → New Private Conversation → paste this intro bundle:"
    echo
    echo "   $INTRO_BUNDLE"
    echo
    echo "   Type a message, send. The sim will detect arrival at the receiver."
    echo
    echo "Receiver log: $RECEIVER_LOG"
    echo "Polling for inbound chatNewMessage events (Ctrl+C to stop)..."
    echo
    LAST_COUNT=0
    while true; do
        N=$(grep -c "chatNewMessage" "$RECEIVER_LOG" 2>/dev/null || true); N=${N:-0}
        if [ "$N" -gt "$LAST_COUNT" ]; then
            log "  RECEIVED MESSAGE #$N (total: $N)"
            # Extract the latest payload
            tail -100 "$RECEIVER_LOG" | sed 's/\x1b\[[0-9;]*m//g' \
                | grep "chatNewMessage" | tail -1 | head -c 300
            echo
            LAST_COUNT=$N
        fi
        sleep 2
    done
fi

SEND_MDIR=$(mktemp -d); MODULES_DIRS+=("$SEND_MDIR")
stage_chat_module "$SEND_MDIR"

SEND_CONFIG="$STATE_DIR/chat_sender_config.json"
cat > "$SEND_CONFIG" <<EOF
{
  "name": "sender",
  "clusterId": $CLUSTER_ID,
  "shardId": 0,
  "port": $CHAT_SEND_PORT,
  "mixEnabled": true,
  "mixNodes": [$MIXNODE_LIST],
  "destPeerAddr": "$BOOTSTRAP_PEER",
  "minMixPoolSize": 4,
  "gifterNodeAddr": "$BOOTSTRAP_PEER",
  "gifterAuthKey": "$KEY_SENDER",
  "staticPeers": [$CHAT_STATIC_PEERS]
}
EOF

# Sender calls: init/start ONLY in the first batch. Defer newPrivateConversation
# until after the sender's gifter-granted RLN membership is confirmed on chain.
# Reason: the chat client's mix-side spam-protection plugin is only `isReady()`
# after the on-chain confirmation lands AND the next poll-loop tick fetches our
# merkle proof from LEZ. sendBytes inside newPrivateConversation only waits
# ~90s for plugin readiness; local sequencer confirmation takes ~3min, so
# running them back-to-back lands us in the "publish anyway with not-ready
# plugin → Failed to generate spam protection proof" failure path with the
# message dropped (no retry). Waiting for confirmation here lets the call sit
# until the plugin is genuinely ready, so the message goes out on first try.
SENDER_CALLS=(
    "$WALLET_CALL"
    "chat_module.initChat(@$SEND_CONFIG)"
    "chat_module.setEventCallback()"
    "chat_module.startChat()"
)

log "  Starting sender..."
DYLD_PRELOAD_LIBS="$CHAT_EXTRA_LIB" \
start_logoscore_instance "$SENDER_LOG" "$SEND_MDIR" "$CHAT_LOAD_ORDER" "${SENDER_CALLS[@]}" || true
SENDER_PID="$LAST_DAEMON_PID"
log "  Sender PID: $SENDER_PID"

SEND_EXPECTED=4
wait_method_calls "$SENDER_LOG" "$SEND_EXPECTED" 180 2 || true

# On slower systems (Docker/ARM) the sender's async gifter registration may
# trail newPrivateConversation. Wait for RLN readiness; the Nim async code
# retries newPrivateConversation once credentials land.
echo "  Waiting for sender RLN readiness..."
SENDER_RLN_T0=$SECONDS
for t in $(seq 1 60); do
    SG=$(sed 's/\x1b\[[0-9;]*m//g' "$SENDER_LOG" 2>/dev/null | grep -c "Registered via RLN gifter\|Waku client started" || true)
    [ "${SG:-0}" -ge 2 ] && break
    sleep 1
done
log "  Sender RLN ready after $((SECONDS - SENDER_RLN_T0))s"
N=$(grep -c '^Method call successful' "$SENDER_LOG" 2>/dev/null || true); N=${N:-0}
log "  Sender method calls: $N/$SEND_EXPECTED"

# Wait for the sender's gifter-granted RLN membership to be confirmed on chain
# before dispatching newPrivateConversation. The chat client's mix-side spam-
# protection plugin only becomes isReady() after this confirmation lands AND
# the next 10s poll cycle fetches our merkle proof from LEZ. Local sequencer
# typically confirms in ~3 min; testnet up to 5-30 min.
if [ -n "$INTRO_BUNDLE" ]; then
    echo "  Waiting for sender on-chain membership confirmation..."
    CONFIRM_T0=$SECONDS
    # Local: ~3min typical. Testnet: 5-30min per registration due to block
    # times + finality lag. Default scales with network.
    if [ "$SIM_NETWORK" = testnet ]; then
        CONFIRM_TIMEOUT=${SIM_SENDER_CONFIRM_TIMEOUT:-3600}
    else
        CONFIRM_TIMEOUT=${SIM_SENDER_CONFIRM_TIMEOUT:-600}
    fi
    for t in $(seq 1 $CONFIRM_TIMEOUT); do
        if sed 's/\x1b\[[0-9;]*m//g' "$SENDER_LOG" 2>/dev/null | grep -q "membership confirmed on-chain"; then
            log "  Sender membership confirmed after $((SECONDS - CONFIRM_T0))s"
            break
        fi
        sleep 1
    done
    # Cushion: give the next poll tick (~10s) time to fetch the proof so
    # isReady() flips true before we issue the publish. Longer cushion (60s)
    # also gives all mix nodes' poll loops time to converge their valid_roots
    # window on the latest tree state — without this, mix entry node 0's
    # self-verify of generated proof fails with "Expected one of the provided
    # roots" because its valid_roots window doesn't yet contain the root its
    # generated proof references (race between fetchProof + tree changes from
    # late client registrations).
    sleep 60

    SENDER_CFG_DIR="$LAST_DAEMON_CFG"

    # Wire the chat module's RLN fetcher → liblogos_rln_module bridge. Without
    # this, mix_lez_client.callRlnFetcher returns "RLN fetcher not registered",
    # the mix spam-protection plugin can never fetch roots/proofs from LEZ, and
    # every publish fails with "Plugin not ready". Old single-process logoscore
    # flow ran chat_module.selfRegisterRln which internally called setRlnConfig
    # (which registers the C++ rln_fetcher trampoline); the new gifter-only
    # flow doesn't, so the sim has to do it explicitly. Extract config account
    # + leaf from the gifter-success log line.
    GIFTER_INFO=$(sed 's/\x1b\[[0-9;]*m//g' "$SENDER_LOG" 2>/dev/null \
        | grep "Registered via RLN gifter" | tail -1)
    SENDER_CONFIG_ACCT=$(printf '%s' "$GIFTER_INFO" | sed -nE 's/.*configAccount=([A-Za-z0-9]+).*/\1/p')
    SENDER_LEAF=$(printf '%s' "$GIFTER_INFO" | sed -nE 's/.*leafIndex=([0-9]+).*/\1/p')
    if [ -n "$SENDER_CONFIG_ACCT" ] && [ -n "$SENDER_LEAF" ]; then
        log "  Wiring sender RLN fetcher: account=$SENDER_CONFIG_ACCT leaf=$SENDER_LEAF"
        SETCFG_ACCT_ARG="$STATE_DIR/sender_setcfg_acct.arg"
        printf '%s' "$SENDER_CONFIG_ACCT" > "$SETCFG_ACCT_ARG"
        timeout "${CALL_TIMEOUT:-180}" env -u TMPDIR LOGOSCORE_CONFIG_DIR="$SENDER_CFG_DIR" "$LOGOSCORE" --json call chat_module setRlnConfig "@$SETCFG_ACCT_ARG" "$SENDER_LEAF" \
            >>"$SENDER_LOG" 2>&1 \
            || log "  setRlnConfig call failed"
        # setRlnConfig schedules the valid_roots subscription 15s later; wait
        # for that to subscribe + one poll cycle so roots+proof are cached.
        sleep 25
    else
        log "  WARN: couldn't extract sender gifter configAccount/leafIndex"
    fi

    log "  Sending newPrivateConversation..."
    # @file wrapper avoids logoscore-cli's positional-arg auto-coercion of
    # numeric-looking tokens, same trick as parse_call's inner loop.
    NPC_BUNDLE_ARG="$STATE_DIR/sender_npc_bundle.arg"
    NPC_HEX_ARG="$STATE_DIR/sender_npc_hex.arg"
    printf '%s' "$INTRO_BUNDLE" > "$NPC_BUNDLE_ARG"
    printf '%s' "$TEST_MSG_HEX" > "$NPC_HEX_ARG"

    # Retry the NPC on mix-lightpush timeout. Each NPC creates a fresh
    # convoId on success; if the first attempt's sphinx packet doesn't
    # generate a SURB reply within 15s, the chat client logs
    # "Mix lightpush timed out" and abandons the send. Without a retry,
    # the receiver never gets the conversation handshake and any
    # subsequent sendMessage extras arrive as orphans (unknown convoId →
    # silently dropped). Re-dispatching newPrivateConversation creates a
    # new conversation; the receiver accepts whichever arrives.
    NPC_MAX_RETRIES=${SIM_NPC_RETRIES:-2}
    for attempt in $(seq 0 "$NPC_MAX_RETRIES"); do
        # Snapshot sender log line count so we only inspect entries
        # produced by THIS attempt's mix send.
        LOG_BEFORE=$(wc -l < "$SENDER_LOG" 2>/dev/null || echo 0)
        timeout "${CALL_TIMEOUT:-180}" env -u TMPDIR LOGOSCORE_CONFIG_DIR="$SENDER_CFG_DIR" "$LOGOSCORE" --json call chat_module newPrivateConversation "@$NPC_BUNDLE_ARG" "@$NPC_HEX_ARG" \
            >>"$SENDER_LOG" 2>&1 \
            || log "  newPrivateConversation call failed (attempt $((attempt+1)))"

        # Wait for either success or timeout marker in the newly-emitted
        # log range. The chat client doesn't start "Sending via mix"
        # until ~20s after the NPC call (after intro-bundle parsing +
        # mix-pool readiness gate), and the SURB deadline is now 60s
        # (widened from 15s per Phase-B+C mitigation in waku_client.nim).
        # Outcome determined within ~85s of dispatch. 100s window adds
        # slack for log flush + slow daemons.
        NPC_OUTCOME=""
        for w in $(seq 1 100); do
            LINE_RANGE=$(tail -n +"$((LOG_BEFORE + 1))" "$SENDER_LOG" 2>/dev/null \
                | sed -E 's/\x1b\[[0-9;]*m//g')
            if grep -q "Message sent via mix successfully" <<<"$LINE_RANGE"; then
                NPC_OUTCOME=ok
                break
            elif grep -qE "Mix lightpush timed out|Mix lightpush: no SURB reply" <<<"$LINE_RANGE"; then
                # SURB reply not received within deadline. Even though
                # forward delivery is independent of SURB, the receiver-
                # side conversation handshake may not have fully landed
                # (the chat module relies on the round-trip to confirm
                # delivery and update conversation state). Retry to give
                # the receiver another shot at the handshake.
                NPC_OUTCOME=timeout
                break
            fi
            sleep 1
        done

        if [ "$NPC_OUTCOME" = ok ]; then
            log "  NPC attempt $((attempt+1)) succeeded via mix"
            break
        elif [ "$NPC_OUTCOME" = timeout ]; then
            if [ "$attempt" -lt "$NPC_MAX_RETRIES" ]; then
                log "  NPC attempt $((attempt+1)) mix-lightpush timed out — retrying"
                sleep 5
            else
                log "  NPC exhausted $((NPC_MAX_RETRIES+1)) attempts; continuing"
            fi
        else
            # No clear marker yet — likely succeeded but flush lag, OR
            # the chat client is still working on something else. Don't
            # retry; downstream delivery check will catch true failure.
            log "  NPC attempt $((attempt+1)) outcome unclear after 25s; continuing"
            break
        fi
    done

    # Optional: send N additional messages after newPrivateConversation.
    # Controlled via SIM_EXTRA_MESSAGES (default 0). The convId is extracted
    # from the sender's "CREATED ... convoId=..." log line emitted by
    # newPrivateConversation. Each extra send is dispatched via the same
    # `chat_module.sendMessage(convoId, hex)` Q_INVOKABLE the chat-ui would
    # call, separated by SIM_EXTRA_MESSAGE_GAP seconds (default 5) so RLN
    # rate-limit windows don't reject closely-spaced sends.
    EXTRA_N=${SIM_EXTRA_MESSAGES:-0}
    EXTRA_GAP=${SIM_EXTRA_MESSAGE_GAP:-5}
    if [ "$EXTRA_N" -gt 0 ]; then
        # Wait briefly for the CREATED log line — the convo emit fires from
        # the chat client's async newPrivateConversation callback.
        CONVO_ID=""
        for t in $(seq 1 30); do
            CONVO_ID=$(sed 's/\x1b\[[0-9;]*m//g' "$SENDER_LOG" 2>/dev/null \
                | grep -oE "convoId=[0-9a-f]+" | head -1 | cut -d= -f2)
            [ -n "$CONVO_ID" ] && break
            sleep 1
        done
        if [ -z "$CONVO_ID" ]; then
            log "  WARN: couldn't extract convoId for extra messages; skipping"
        else
            log "  Sending $EXTRA_N extra messages (convoId=${CONVO_ID:0:12}…, gap=${EXTRA_GAP}s)"
            for i in $(seq 1 "$EXTRA_N"); do
                sleep "$EXTRA_GAP"
                BODY="mixmsg #$i $(date -u +%H:%M:%S)"
                BODY_HEX=$(printf '\xff%s' "$BODY" | xxd -p | tr -d '\n')
                SM_JSON_ARG="$STATE_DIR/sender_sm_json_$i.arg"
                # logoscore-cli's `call` subcommand coerces digit-leading
                # positional args (and @file content) to qulonglong even with
                # @-prefix. Wrap the args in a JSON object and dispatch via
                # the Json variant — same pattern as selfRegisterRlnJson.
                printf '{"convoId":"%s","contentHex":"%s"}' "$CONVO_ID" "$BODY_HEX" > "$SM_JSON_ARG"
                timeout "${CALL_TIMEOUT:-180}" env -u TMPDIR LOGOSCORE_CONFIG_DIR="$SENDER_CFG_DIR" "$LOGOSCORE" --json call chat_module sendMessageJson "@$SM_JSON_ARG" \
                    >>"$SENDER_LOG" 2>&1 \
                    || log "    extra send #$i call failed"
            done
            log "  Extra messages dispatched"
        fi
    fi
fi

# Poll receiver log for delivery. Initial NPC handshake emits a few events
# (chatNewConversation + chatNewMessage); each extra sendMessage adds at
# least one more chatNewMessage. We want to see ≥ (1 + EXTRA_N) inbound
# chat events before declaring delivery successful.
echo "  Waiting for message delivery via mix..."
DELIVERY_EXPECTED=$(( 1 + ${SIM_EXTRA_MESSAGES:-0} ))
DELIVERY_T0=$SECONDS
for t in $(seq 1 $DELIVERY_TIMEOUT); do
    RM=$(grep -c "chatNewMessage\|chatNewConversation\|New Message\|new_message" "$RECEIVER_LOG" 2>/dev/null || true); RM=${RM:-0}
    [ "$RM" -ge "$DELIVERY_EXPECTED" ] && break
    sleep 1
done
log "  Delivery check after $((SECONDS - DELIVERY_T0))s (messages: $RM/expected ≥$DELIVERY_EXPECTED)"

# ─── Receiver replies back to sender ───
# Once the receiver has received messages, have it send replies back through
# the mix network. Uses the same convoId (extracted from sender's CREATED log).
REPLY_N=${SIM_REPLY_MESSAGES:-0}
REPLY_GAP=${SIM_REPLY_MESSAGE_GAP:-5}
if [ "$REPLY_N" -gt 0 ] && [ "${RM:-0}" -ge 1 ] && [ -n "${CONVO_ID:-}" ] && [ -n "${RECEIVER_CFG_DIR:-}" ]; then
    log "  Receiver sending $REPLY_N replies (convoId=${CONVO_ID:0:12}…, gap=${REPLY_GAP}s)"
    for i in $(seq 1 "$REPLY_N"); do
        sleep "$REPLY_GAP"
        BODY="reply #$i $(date -u +%H:%M:%S)"
        BODY_HEX=$(printf '\xff%s' "$BODY" | xxd -p | tr -d '\n')
        RM_JSON_ARG="$STATE_DIR/receiver_sm_json_$i.arg"
        printf '{"convoId":"%s","contentHex":"%s"}' "$CONVO_ID" "$BODY_HEX" > "$RM_JSON_ARG"
        timeout "${CALL_TIMEOUT:-180}" env -u TMPDIR LOGOSCORE_CONFIG_DIR="$RECEIVER_CFG_DIR" "$LOGOSCORE" --json call chat_module sendMessageJson "@$RM_JSON_ARG" \
            >>"$RECEIVER_LOG" 2>&1 \
            || log "    receiver reply #$i call failed"
    done
    log "  Receiver replies dispatched"

    # Wait for sender to receive the replies
    SENDER_REPLY_EXPECTED=$REPLY_N
    echo "  Waiting for sender to receive replies..."
    for t in $(seq 1 $DELIVERY_TIMEOUT); do
        SM=$(grep -c "chatNewMessage\|chatNewConversation\|New Message\|new_message" "$SENDER_LOG" 2>/dev/null || true); SM=${SM:-0}
        [ "$SM" -ge "$SENDER_REPLY_EXPECTED" ] && break
        sleep 1
    done
    log "  Sender received $SM reply events (expected ≥$SENDER_REPLY_EXPECTED)"
fi

# ─── Sender → Receiver2 conversation (reuses sender's existing RLN membership) ───
if [ "${SIM_RECEIVER2:-0}" = "1" ] && [ -n "$INTRO_BUNDLE2" ] && [ -n "$SENDER_CFG_DIR" ]; then
    echo ""
    echo "  --- Sender → Receiver2 (reusing existing membership) ---"

    NPC2_BUNDLE_ARG="$STATE_DIR/npc2_bundle.arg"
    NPC2_HEX_ARG="$STATE_DIR/npc2_hex.arg"
    NPC2_MSG="hello receiver2 $(date -u +%H:%M:%S)"
    NPC2_MSG_HEX=$(printf '\xff%s' "$NPC2_MSG" | xxd -p | tr -d '\n')
    printf '%s' "$INTRO_BUNDLE2" > "$NPC2_BUNDLE_ARG"
    printf '%s' "$NPC2_MSG_HEX" > "$NPC2_HEX_ARG"

    log "  Sending newPrivateConversation to receiver2..."
    timeout "${CALL_TIMEOUT:-180}" env -u TMPDIR LOGOSCORE_CONFIG_DIR="$SENDER_CFG_DIR" \
        "$LOGOSCORE" --json call chat_module newPrivateConversation "@$NPC2_BUNDLE_ARG" "@$NPC2_HEX_ARG" \
        >>"$SENDER_LOG" 2>&1 || true

    # Wait for receiver2 to get the message
    echo "  Waiting for receiver2 delivery..."
    R2_DELIVERY_T0=$SECONDS
    for t in $(seq 1 $DELIVERY_TIMEOUT); do
        R2M=$(grep -c "chatNewMessage\|chatNewConversation\|New Message\|new_message" "$RECEIVER2_LOG" 2>/dev/null || true); R2M=${R2M:-0}
        [ "$R2M" -ge 1 ] && break
        sleep 1
    done
    log "  Receiver2 delivery check after $((SECONDS - R2_DELIVERY_T0))s (messages: $R2M)"
fi

echo ""

# ---------- Phase 6: Verify ----------
echo "[6/6] Verification"; echo ""
PASS=0; FAIL=0
check() { local c=$1 d=$2; if eval "$c"; then echo "  PASS: $d"; PASS=$((PASS+1)); else echo "  FAIL: $d"; FAIL=$((FAIL+1)); fi; }

echo "  --- logos-core mix nodes ---"
for i in $(seq 0 $((NUM_NODES - 1))); do
    M=$(sed 's/\x1b\[[0-9;]*m//g' "$STATE_DIR/node${i}.log" 2>/dev/null | grep -c "mounting mix protocol" || true)
    check "[ ${M:-0} -ge 1 ]" "Node $i mounted mix ($M)"
done
echo ""

echo "  --- RLN gifter ---"
GIFTER_MOUNTED=$(sed 's/\x1b\[[0-9;]*m//g' "$STATE_DIR/node0.log" 2>/dev/null | grep -c "RLN gifter service mounted" || true)
check "[ ${GIFTER_MOUNTED:-0} -ge 1 ]" "Node 0 gifter service mounted ($GIFTER_MOUNTED)"
echo ""

echo "  --- LEZ RLN ---"
LEZ_ROOTS=0
for i in $(seq 0 $((NUM_NODES - 1))); do
    R=$(sed 's/\x1b\[[0-9;]*m//g' "$STATE_DIR/node${i}.log" 2>/dev/null | grep -c "Polled valid roots\|Fetched roots from\|valid_roots\|OnchainLEZGroupManager initialized\|Wired LEZ callbacks" || true)
    LEZ_ROOTS=$((LEZ_ROOTS + R))
done
check "[ $LEZ_ROOTS -ge 1 ]" "LEZ RLN active ($LEZ_ROOTS events across nodes)"
echo ""

echo "  --- chat module ---"
RECV_INIT=$(grep -c "chatInitResult\|Chat context created" "$RECEIVER_LOG" 2>/dev/null || true)
check "[ ${RECV_INIT:-0} -ge 1 ]" "Receiver initialized ($RECV_INIT)"
RECV_START=$(grep -c "chatStartResult\|Waku client started" "$RECEIVER_LOG" 2>/dev/null || true)
check "[ ${RECV_START:-0} -ge 1 ]" "Receiver started ($RECV_START)"
SEND_INIT=$(grep -c "chatInitResult\|Chat context created" "$SENDER_LOG" 2>/dev/null || true)
check "[ ${SEND_INIT:-0} -ge 1 ]" "Sender initialized ($SEND_INIT)"
SEND_START=$(grep -c "chatStartResult\|Waku client started" "$SENDER_LOG" 2>/dev/null || true)
check "[ ${SEND_START:-0} -ge 1 ]" "Sender started ($SEND_START)"

RECV_MIX=$(grep -c "mounting mix protocol\|Wired LEZ callbacks" "$RECEIVER_LOG" 2>/dev/null || true)
check "[ ${RECV_MIX:-0} -ge 1 ]" "Receiver mounted mix+LEZ ($RECV_MIX)"
SEND_MIX=$(grep -c "mounting mix protocol\|Wired LEZ callbacks" "$SENDER_LOG" 2>/dev/null || true)
check "[ ${SEND_MIX:-0} -ge 1 ]" "Sender mounted mix+LEZ ($SEND_MIX)"

RECV_BUNDLE=$(grep -c "IntroBundleCreated\|chatCreateIntroBundleResult" "$RECEIVER_LOG" 2>/dev/null || true)
check "[ ${RECV_BUNDLE:-0} -ge 1 ]" "Receiver created intro bundle ($RECV_BUNDLE)"
echo ""

echo "  --- message exchange ---"
SEND_MSG=$(grep -c "chatNewPrivateConversationResult\|chatSendMessageResult\|Message sent via mix" "$SENDER_LOG" 2>/dev/null || true)
check "[ ${SEND_MSG:-0} -ge 1 ]" "Sender sent message ($SEND_MSG)"
RECV_MSG=$(grep -c "chatNewMessage\|chatNewConversation\|New Message\|new_message" "$RECEIVER_LOG" 2>/dev/null || true)
check "[ ${RECV_MSG:-0} -ge ${DELIVERY_EXPECTED:-1} ]" "Receiver received message ($RECV_MSG / ≥${DELIVERY_EXPECTED:-1})"

if [ "${SIM_RECEIVER2:-0}" = "1" ]; then
    echo ""
    echo "  --- receiver2 (membership reuse) ---"
    R2_INIT=$(grep -c "chatInitResult\|Chat context created" "$RECEIVER2_LOG" 2>/dev/null || true)
    check "[ ${R2_INIT:-0} -ge 1 ]" "Receiver2 initialized ($R2_INIT)"
    R2_START=$(grep -c "chatStartResult\|Waku client started" "$RECEIVER2_LOG" 2>/dev/null || true)
    check "[ ${R2_START:-0} -ge 1 ]" "Receiver2 started ($R2_START)"
    R2_MSG=$(grep -c "chatNewMessage\|chatNewConversation\|New Message\|new_message" "$RECEIVER2_LOG" 2>/dev/null || true)
    check "[ ${R2_MSG:-0} -ge 1 ]" "Receiver2 received message ($R2_MSG)"
fi

echo ""; echo "  =========================================="
if [ "$FAIL" -eq 0 ]; then echo "  ALL $PASS CHECKS PASSED"; EXIT_CODE=0
else echo "  $FAIL FAILED, $PASS passed"; EXIT_CODE=1; fi
echo "  =========================================="
