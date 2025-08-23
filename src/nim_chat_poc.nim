import chronos
import chronicles
import strformat

import chat_sdk/client
import chat_sdk/conversations
import chat_sdk/delivery/waku_client
import chat_sdk/utils

proc initLogging() =
  when defined(chronicles_runtime_filtering):
    setLogLevel(LogLevel.Debug)
    discard setTopicState("waku filter", chronicles.Normal, LogLevel.Error)
    discard setTopicState("waku relay", chronicles.Normal, LogLevel.Error)
    discard setTopicState("chat client", chronicles.Enabled, LogLevel.Debug)

proc main() {.async.} =

  # Create Configurations
  var cfg_saro = DefaultConfig()
  var cfg_raya = DefaultConfig()

  # Cross pollinate Peers
  cfg_saro.staticPeers.add(cfg_raya.getMultiAddr())
  cfg_raya.staticPeers.add(cfg_saro.getMultiAddr())

  info "CFG", cfg = cfg_raya
  info "CFG", cfg = cfg_saro

  # Start Clients
  var saro = newClient("Saro", cfg_saro)
  saro.onNewMessage(proc(convo: Conversation, msg: string) {.async.} =
    echo "    Saro  <------        :: " & msg
    await sleepAsync(10000)
    await convo.sendMessage(saro.ds, "Ping"))
  await saro.start()

  var raya = newClient("Raya", cfg_raya)
  raya.onNewMessage(proc(convo: Conversation, msg: string) {.async.} =
    echo "           ------>  Raya :: " & msg
    await sleepAsync(10000)
    await convo.sendMessage(raya.ds, "Pong")
  )

  raya.onNewConversation(proc(convo: Conversation) {.async.} =
    echo "           ------>  Raya :: New Conversation: " & convo.id()
    await convo.sendMessage(raya.ds, "Hello")
  )
  await raya.start()


  await sleepAsync(5000)

  # Perform OOB Introduction: Raya -> Saro
  let raya_bundle = raya.createIntroBundle()
  discard await saro.newPrivateConversation(raya_bundle)

  await sleepAsync(400000)

  saro.stop()
  raya.stop()

when isMainModule:
  initLogging()
  waitFor main()
  notice "Shutdown"
