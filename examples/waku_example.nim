import
  std/[options, strutils, sequtils, net],
  chronicles,
  chronos,
  metrics,
  system/ansi_c,
  libp2p/crypto/crypto
import waku as waku_module

logScope:
  topics = "waku example main"

const git_version* {.strdefine.} = "n/a"

proc mm() {.async.} =
  await sleepAsync(1000)
  echo "Hello, world!"

when isMainModule:
  const versionString = "version / git commit hash: " & waku.git_version

  var wakuNodeConf = WakuNodeConf.load(version = versionString).valueOr:
    error "failure while loading the configuration", error = error
    quit(QuitFailure)

  ## Also called within Waku.new. The call to startRestServerEssentials needs the following line
  logging.setupLog(wakuNodeConf.logLevel, wakuNodeConf.logFormat)

  let conf = wakuNodeConf.toWakuConf().valueOr:
    error "Waku configuration failed", error = error
    quit(QuitFailure)

  var waku = (waitFor Waku.new(conf)).valueOr:
    error "Waku initialization failed", error = error
    quit(QuitFailure)

  (waitFor startWaku(addr waku)).isOkOr:
    error "Starting waku failed", error = error
    quit(QuitFailure)

  debug "Setting up shutdown hooks"
  proc asyncStopper(waku: Waku) {.async: (raises: [Exception]).} =
    await waku.stop()
    quit(QuitSuccess)

  # Handle Ctrl-C SIGINT
  proc handleCtrlC() {.noconv.} =
    when defined(windows):
      # workaround for https://github.com/nim-lang/Nim/issues/4057
      setupForeignThreadGc()
    notice "Shutting down after receiving SIGINT"
    asyncSpawn asyncStopper(waku)

  setControlCHook(handleCtrlC)

  # Handle SIGTERM
  when defined(posix):
    proc handleSigterm(signal: cint) {.noconv.} =
      notice "Shutting down after receiving SIGTERM"
      asyncSpawn asyncStopper(waku)

    c_signal(ansi_c.SIGTERM, handleSigterm)

  info "Node setup complete"

  runForever()
