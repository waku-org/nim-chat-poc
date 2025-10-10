import chronicles
import chronos
import strformat

import chat_sdk
import content_types

# TEsting
import ../src/chat_sdk/crypto


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

  let sKey = loadPrivateKeyFromBytes(@[45u8, 216, 160, 24, 19, 207, 193, 214, 98, 92, 153, 145, 222, 247, 101, 99, 96, 131, 149, 185, 33, 187, 229, 251, 100, 158, 20, 131, 111, 97, 181, 210]).get()
  let rKey = loadPrivateKeyFromBytes(@[43u8, 12, 160, 51, 212, 90, 199, 160, 154, 164, 129, 229, 147, 69, 151, 17, 239, 51, 190, 33, 86, 164, 50, 105, 39, 250, 182, 116, 138, 132, 114, 234]).get()

  let sIdent = Identity(name: "saro", privateKey: sKey)

  # Create Clients
  var saro = newClient(cfg_saro, sIdent)
  var raya = newClient(cfg_raya, Identity(name: "raya", privateKey: rKey))

  var ri = 0
  # Wire Callbacks
  saro.onNewMessage(proc(convo: Conversation, msg: ContentFrame) {.async.} =
    echo "    Saro  <------        :: " & getContent(msg)
    await sleepAsync(5000)
    discard await convo.sendMessage(saro.ds, initTextFrame("Ping").toContentFrame())
  
    )

  saro.onDeliveryAck(proc(convo: Conversation, msgId: string) {.async.} =
    echo "    Saro -- Read Receipt for " & msgId
  )




  raya.onNewMessage(proc(convo: Conversation, msg: ContentFrame) {.async.} =
    echo "           ------>  Raya :: " & getContent(msg)
    await sleepAsync(500)
    discard  await convo.sendMessage(raya.ds, initTextFrame("Pong" & $ri).toContentFrame())
    await sleepAsync(800)
    discard  await convo.sendMessage(raya.ds, initTextFrame("Pong" & $ri).toContentFrame())
    await sleepAsync(500)
    discard  await convo.sendMessage(raya.ds, initTextFrame("Pong" & $ri).toContentFrame())
    inc ri
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

  await sleepAsync(20000) # Run for some time 

  saro.stop()
  raya.stop()


when isMainModule:
  waitFor main()
  notice "Shutdown"
