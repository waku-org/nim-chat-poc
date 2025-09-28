import chronicles
import chronos

import chat_sdk
import content_types


proc getContent(content: ContentFrame): string =
  # Skip type checks and assume its a TextFrame
  let m = decode(content.bytes, TextFrame).valueOr:
        raise newException(ValueError, fmt"Badly formed Content")
      return fmt"{m}"

proc main() {.async.} =

  # Create Configurations
  var cfg_saro = DefaultConfig()
  var cfg_raya = DefaultConfig()

  # Cross pollinate Peers - No Waku discovery is used in this example
  cfg_saro.staticPeers.add(cfg_raya.getMultiAddr())
  cfg_raya.staticPeers.add(cfg_saro.getMultiAddr())

  # Create Clients
  var saro = newClient(cfg_saro, createIdentity("Saro"))
  var raya = newClient(cfg_raya, createIdentity("Raya"))

  # Wire Callbacks
  saro.onNewMessage(proc(convo: Conversation, msg: ContentFrame) {.async.} =
    echo "    Saro  <------        :: " & getContent(msg)
    await sleepAsync(10000)
    discard await convo.sendMessage(saro.ds, initTextFrame("Ping").toContentFrame())
    )

  saro.onDeliveryAck(proc(convo: Conversation, msgId: string) {.async.} =
    echo "    Saro -- Read Receipt for " & msgId
  )




  raya.onNewMessage(proc(convo: Conversation, msg: ContentFrame) {.async.} =
    echo "           ------>  Raya :: " & getContent(msg)
    await sleepAsync(10000)
    sdiscard  await convo.sendMessage(raya.ds, initTextFrame("Pong").toContentFrame())
  )

  raya.onNewConversation(proc(convo: Conversation) {.async.} =
    echo "           ------>  Raya :: New Conversation: " & convo.id()
    discard await convo.sendMessage(raya.ds, initTextFrame("Hello").toContentFrame())
  )
  raya.onDeliveryAck(proc(convo: Conversation, msgId: string) {.async.} =
    echo "    raya -- Read Receipt for " & msgId
  )


  await saro.start()
  await raya.start()

  await sleepAsync(5000)

  # Perform OOB Introduction: Raya -> Saro
  let raya_bundle = raya.createIntroBundle()
  discard await saro.newPrivateConversation(raya_bundle)

  await sleepAsync(10000) # Run for some time 

  saro.stop()
  raya.stop()