
import
  chronicles,
  chronos,
  strformat

import
  waku_client


proc handleMessages(pubsubTopic: string, message: seq[byte]): Future[
    void] {.gcsafe, raises: [Defect].} =
  info "ClientRecv", pubTopic = pubsubTopic, msg = message

proc demoSendLoop(client: WakuClient): Future[void] {.async.} =
  for i in 1..10:
    await sleepAsync(20.seconds)
    discard client.sendMessage(&"Message:{i}")

proc main(): Future[void] {.async.} =
  echo "Starting POC"
  let cfg = DefaultConfig()
  let client = initWakuClient(cfg, @[PayloadHandler(handleMessages)])
  asyncSpawn client.start()

  await demoSendLoop(client)

  echo "End of POC"

when isMainModule:
  waitFor main()

# import client
# import chronicles
# import proto_types

# proc log(transport_message: TransportMessage) =
#   ## Log the transport message
#   info "Transport Message:", topic = transport_message.topic,
#       payload = transport_message.payload

# proc demo() =

#   # Initalize Clients
#   var saro = initClient("Saro")
#   var raya = initClient("Raya")

#   # # Exchange Contact Info
#   let raya_bundle = raya.createIntroBundle()

#   # Create Conversation
#   let invite = saro.createPrivateConvo(raya_bundle)
#   invite.log()
#   let msgs = raya.recv(invite)

#   # raya.convos()[0].sendText("Hello Saro, this is Raya!")


# when isMainModule:
#   echo("Starting ChatPOC...")

#   try:
#     demo()
#   except Exception as e:
#     error "Crashed ", error = e.msg

#   echo("Finished...")
