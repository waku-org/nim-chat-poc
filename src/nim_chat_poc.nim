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
