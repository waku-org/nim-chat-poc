import chronos
import chronicles
import strformat

import chat_sdk/client
import chat_sdk/conversations
import chat_sdk/delivery/waku_client
import chat_sdk/utils

import content_types/all


const SELF_DEFINED = 99

type ImageFrame {.proto3.} = object
  url {.fieldNumber: 1.}: string
  altText {.fieldNumber: 2.}: string


proc initImage(url: string): ContentFrame =
  result = ContentFrame(domain: SELF_DEFINED, tag: 0, bytes: encode(ImageFrame(
      url: url, altText: "This is an image")))

proc `$`*(frame: ImageFrame): string =
  result = fmt"ImageFrame(url:{frame.url}   alt_text:{frame.altText})"


proc initLogging() =
  when defined(chronicles_runtime_filtering):
    setLogLevel(LogLevel.Debug)
    discard setTopicState("waku filter", chronicles.Normal, LogLevel.Error)
    discard setTopicState("waku relay", chronicles.Normal, LogLevel.Error)
    discard setTopicState("chat client", chronicles.Enabled, LogLevel.Debug)

proc getContent(content: ContentFrame): string =
  notice "GetContent", domain = content.domain, tag = content.tag

  # TODO: Hide this complexity from developers
  if content.domain == 0:
    if content.tag == 0:
      let m = decode(content.bytes, TextFrame).valueOr:
        raise newException(ValueError, fmt"Badly formed Content (domain:{content.domain} tag:{content.tag})")
      return fmt"{m}"

  if content.domain == SELF_DEFINED:
    if content.tag == 0:
      let m = decode(content.bytes, ImageFrame).valueOr:
        raise newException(ValueError, fmt"Badly formed Content (domain:{content.domain} tag:{content.tag})")
      return fmt"{m}"

  raise newException(ValueError, fmt"Unhandled content (domain:{content.domain} tag:{content.tag})")


proc main() {.async.} =

  # Create Configurations
  var cfg_saro = DefaultConfig()
  var cfg_raya = DefaultConfig()

  # Cross pollinate Peers
  cfg_saro.staticPeers.add(cfg_raya.getMultiAddr())
  cfg_raya.staticPeers.add(cfg_saro.getMultiAddr())

  # Start Clients
  var saro = newClient("Saro", cfg_saro)
  saro.onNewMessage(proc(convo: Conversation, msg: ContentFrame) {.async.} =
    echo "    Saro  <------        :: " & getContent(msg)
    await sleepAsync(10000)
    await convo.sendMessage(saro.ds, initImage(
        "https://waku.org/theme/image/logo-black.svg"))
    )
  await saro.start()

  var raya = newClient("Raya", cfg_raya)
  raya.onNewMessage(proc(convo: Conversation, msg: ContentFrame) {.async.} =
    echo "           ------>  Raya :: " & getContent(msg)
    await sleepAsync(10000)
    await convo.sendMessage(raya.ds, initTextFrame("Pong").toContentFrame())
  )

  raya.onNewConversation(proc(convo: Conversation) {.async.} =
    echo "           ------>  Raya :: New Conversation: " & convo.id()
    await convo.sendMessage(raya.ds, initTextFrame("Hello").toContentFrame())
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
