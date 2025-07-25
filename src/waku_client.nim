import
  chronicles,
  chronos,
  confutils,
  eth/keys,
  eth/p2p/discoveryv5/enr,
  libp2p/crypto/crypto,
  std/random,
  stew/byteutils,
  strformat,
  waku/[
    common/logging,
    node/peer_manager,
    waku_core,
    waku_node,
    waku_enr,
    discovery/waku_discv5,
    factory/builder,
    waku_filter_v2/client,
  ]

import utils


const
  StaticPeer = "/ip4/64.225.80.192/tcp/30303/p2p/16Uiu2HAmNaeL4p3WEYzC9mgXBmBWSgWjPHRvatZTXnp8Jgv3iKsb"
  FilterContentTopic = ContentTopic("/chatsdk/test/proto")


type PayloadHandler* = proc(pubsubTopic: string, message: seq[byte]): Future[void] {.
    gcsafe, raises: [Defect]
  .}

type WakuConfig* = object
  port*: uint16
  clusterId*: uint16
  shardId*: seq[uint16] ## @[0'u16]
  pubsubTopic*: string

type
  WakuClient* = ref object
    cfg: WakuConfig
    node*: WakuNode
    handlers: seq[PayloadHandler]


proc DefaultConfig*(): WakuConfig =

  let clusterId = 1'u16
  let shardId = 3'u16
  var port: uint16 = 50000'u16 + uint16(rand(200))

  result = WakuConfig(port: port, clusterId: clusterId, shardId: @[shardId],
      pubsubTopic: &"/waku/2/rs/{clusterId}/{shardId}")


proc sendMessage*(client: WakuClient, payload: string): Future[void] {.async.} =
  let bytes = payload.toBytes

  var msg = WakuMessage(
    payload: bytes,
    contentTopic: FilterContentTopic,
    ephemeral: true,
    version: 0,
    timestamp: getTimestamp()
  )

  let pubMsg = WakuMessage(payload: bytes)
  let res = await client.node.publish(some(PubsubTopic(client.cfg.pubsubTopic)), msg)
  if res.isErr:
    error "Failed to Publish", err = res.error,
        pubsubTopic = client.cfg.pubsubTopic

  info "SendMessage", payload = payload, pubsubTopic = client.cfg.pubsubTopic, msg = msg

proc buildWakuNode(cfg: WakuConfig): WakuNode =

  let
    nodeKey = crypto.PrivateKey.random(Secp256k1, crypto.newRng()[])[]
    ip = parseIpAddress("0.0.0.0")
    flags = CapabilitiesBitfield.init(relay = true)

  let relayShards = RelayShards.init(cfg.clusterId, cfg.shardId).valueOr:
    error "Relay shards initialization failed", error = error
    quit(QuitFailure)

  var enrBuilder = EnrBuilder.init(nodeKey)
  enrBuilder.withWakuRelaySharding(relayShards).expect(
    "Building ENR with relay sharding failed"
  )

  let recordRes = enrBuilder.build()
  let record =
    if recordRes.isErr():
      error "failed to create enr record", error = recordRes.error
      quit(QuitFailure)
    else:
      recordRes.get()

  var builder = WakuNodeBuilder.init()
  builder.withNodeKey(nodeKey)
  builder.withRecord(record)
  builder.withNetworkConfigurationDetails(ip, Port(cfg.port)).tryGet()
  let node = builder.build().tryGet()

  node.mountMetadata(cfg.clusterId).expect("failed to mount waku metadata protocol")

  result = node

proc messageHandler(client: WakuClient, pubsubTopic: PubsubTopic,
    message: WakuMessage
) {.async, gcsafe.} =
  let payloadStr = string.fromBytes(message.payload)
  notice "message received",
    payload = payloadStr,
    pubsubTopic = pubsubTopic,
    contentTopic = message.contentTopic,
    timestamp = message.timestamp


  for handler in client.handlers:
    discard handler(pubsubTopic, message.payload)


proc taskKeepAlive(client: WakuClient) {.async.} =
  let peer = parsePeerInfo(StaticPeer).get()
  while true:
    notice "maintaining subscription"
    # First use filter-ping to check if we have an active subscription
    let pingRes = await client.node.wakuFilterClient.ping(peer)
    if pingRes.isErr():
      # No subscription found. Let's subscribe.
      notice "no subscription found. Sending subscribe request"

      let subscribeRes = await client.node.wakuFilterClient.subscribe(
        peer, client.cfg.pubsubTopic, @[FilterContentTopic]
      )

      if subscribeRes.isErr():
        notice "subscribe request failed. Quitting.", err = subscribeRes.error
        break
      else:
        notice "subscribe request successful."
    else:
      notice "subscription found."

    await sleepAsync(60.seconds) # Subscription maintenance interval


proc taskPublishDemo(client: WakuClient){.async.} =
  for i in 0 ..< 15:
    await client.sendMessage("Hello")
    await sleepAsync(30.seconds) # Subscription maintenance interval

proc start*(client: WakuClient) {.async.} =
  setupLog(logging.LogLevel.NOTICE, logging.LogFormat.TEXT)

  await client.node.mountFilterClient()

  await client.node.start()
  (await client.node.mountRelay()).isOkOr:
    error "failed to mount relay", error = error
    quit(1)

  client.node.peerManager.start()

  let subscription: SubscriptionEvent = (kind: PubsubSub, topic:
    client.cfg.pubsubTopic)

  let msg_handler = proc(pubsubTopic: PubsubTopic,
      message: WakuMessage) {.async, gcsafe.} = discard client.messageHandler(
      pubsubTopic, message)

  let res = subscribe(client.node, subscription, msg_handler)
  if res.isErr:
    error "Subscribe failed", err = res.error

  await allFutures(taskKeepAlive(client), taskPublishDemo(client))

proc initWakuClient*(cfg: WakuConfig, handlers: seq[
    PayloadHandler]): WakuClient =
  result = WakuClient(cfg: cfg, node: buildWakuNode(cfg), handlers: handlers)
