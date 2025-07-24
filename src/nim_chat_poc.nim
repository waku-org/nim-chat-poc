import
  chronicles,
  chronos

import
  waku_client


proc handleMessages(pubsubTopic: string, message: seq[byte]): Future[
    void] {.gcsafe, raises: [Defect].} =
  info "ClientRecv", pubTopic = pubsubTopic, msg = message

proc main(): Future[void] {.async.} =
  echo "Starting POC"
  let cfg = DefaultConfig()
  let client = initWakuClient(cfg, @[PayloadHandler(handleMessages)])
  await client.start()
  echo "End of POC"

when isMainModule:
  waitFor main()
