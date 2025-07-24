import
  chronos

import
  waku_client

proc main(): Future[void] {.async.} =
  echo "Starting POC"
  let cfg = DefaultConfig()
  let client = initWakuClient(cfg)
  await client.start()
  echo "End of POC"

when isMainModule:
  waitFor main()
