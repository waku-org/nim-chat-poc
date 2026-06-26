import
  chronicles,
  chronos,
  confutils,
  eth/common/addresses as eth_addresses,
  eth/common/keys as eth_keys,
  eth/p2p/discoveryv5/enr as eth_enr,
  bearssl/rand,
  libp2p/crypto/crypto,
  libp2p/crypto/secp,
  libp2p/crypto/curve25519,
  libp2p/crypto/rng as libp2p_rng,
  libp2p/peerid,
  libp2p/multiaddress,
  libp2p/nameresolving/dnsresolver,
  libp2p/protocols/kademlia/types,
  libp2p/protocols/service_discovery/types as sd_types,
  libp2p_mix,
  libp2p_mix/curve25519 as mix_curve25519,
  libp2p_mix/entry_connection,
  libp2p_mix/mix_protocol as mix_proto,
  nimcrypto/utils as ncrutils,
  std/[random, sets, strutils],
  stew/byteutils,
  strformat,
  logos_delivery/waku/[
    common/logging,
    common/enr as common_enr,
    node/peer_manager,
    waku_core,
    waku_core/codecs,
    waku_core/peers,
    waku_node,
    waku_enr,
    waku_mix/protocol as waku_mix_protocol,
    waku_lightpush/client as lightpush_client,
    discovery/waku_discv5,
    discovery/waku_dnsdisc,
    discovery/waku_kademlia,
    factory/builder,
    waku_filter_v2/client,
  ],
  mix_rln_spam_protection/spam_protection

from std/os import copyFile

logScope:
  topics = "chat waku"

type ChatPayload* = object
  pubsubTopic*: PubsubTopic
  contentTopic*: string
  timestamp*: waku_core.Timestamp
  bytes*: seq[byte]

proc toChatPayload*(msg: WakuMessage, pubsubTopic: PubsubTopic): ChatPayload =
  result = ChatPayload(pubsubTopic: pubsubTopic, contentTopic: msg.contentTopic,
      timestamp: msg.timestamp, bytes: msg.payload)



const
  # Placeholder
  FilterContentTopic = ContentTopic("/chatsdk/test/proto")
  LibchatDeliveryAddress = ContentTopic("delivery_address")

  ## Logos.dev Fleet ENRs

  # delivery-01.do-ams3.logos.dev.status.im - 16Uiu2HAmTUbnxLGT9JvV6mu9oPyDjqHK4Phs1VDJNUgESgNSkuby
  LogosDevDelivery01DoAms3 = "enr:-MG4QNjpXNETi50MXYSQNZyzd7YVi5UDmy53GjC7i9y1rmuRWd_rGhizRXV4YKLrb8G_ezIrE1gVkiuY_GzFGk6lfikBgmlkgnY0gmlwhIpEeomKbXVsdGlhZGRyc4wACgSKRHqJBh9A3gOCcnOTAAIIAAAAAQACAAMABAAFAAYAB4lzZWNwMjU2azGhA9w1_W3QN9zZw8FcFQT5XWJ7I_qBGXFCxeO5iOBgeWXkg3RjcIJ2X4N1ZHCCIyiFd2FrdTIv"

  # delivery-02.do-ams3.logos.dev.status.im - 16Uiu2HAmMK7PYygBtKUQ8EHp7EfaD3bCEsJrkFooK8RQ2PVpJprH
  LogosDevDelivery02DoAms3 = "enr:-MG4QO7X4HJ8BfAkbSbtG4uDvX1t4HIjEMTbdh4aYR4EV00cMrpa1NYejjVIGD0SXJGqbrRs2YYf59Me9K92iyyi_X4BgmlkgnY0gmlwhK6KavSKbXVsdGlhZGRyc4wACgSuimr0Bh9A3gOCcnOTAAIIAAAAAQACAAMABAAFAAYAB4lzZWNwMjU2azGhA4ChhnJvGLCZgYfCAn6zGi0_lump80dOnTXuwEdMqnveg3RjcIJ2X4N1ZHCCIyiFd2FrdTIv"

  # delivery-01.gc-us-central1-a.logos.dev.status.im - 16Uiu2HAm4S1JYkuzDKLKQvwgAhZKs9otxXqt8SCGtB4hoJP1S397
  LogosDevDelivery01GcUsCentral1a = "enr:-MG4QIiRL2QYsAMJuofnJ2ketbMf_vq448kZxa0DGzu_Wj8PW7YdeIFEJbEJapA2K-b_UMC-TdEaQ2LukC9ynyegRQ4BgmlkgnY0gmlwhIh3nFeKbXVsdGlhZGRyc4wACgSId5xXBh9A3gOCcnOTAAIIAAAAAQACAAMABAAFAAYAB4lzZWNwMjU2azGhAoXPCAUveBrCoOScJxl_jdLrPu4xyzbCmwP_ovGsqNkGg3RjcIJ2X4N1ZHCCIyiFd2FrdTIv"

  # delivery-02.gc-us-central1-a.logos.dev.status.im - 16Uiu2HAm8Y9kgBNtjxvCnf1X6gnZJW5EGE4UwwCL3CCm55TwqBiH
  LogosDevDelivery02GcUsCentral1a = "enr:-MG4QJ2n_Hkl0_ZaGxK4ye_lmXPCHi8qXISESIucQyrPd0oCOFXZf9ws5gjN3hovMw08GTJSAptX2q0GrrjQS9wOpb8BgmlkgnY0gmlwhCJ7yRmKbXVsdGlhZGRyc4wACgQie8kZBh9A3gOCcnOTAAIIAAAAAQACAAMABAAFAAYAB4lzZWNwMjU2azGhAsLQ0aIXN3XPEkZiqfPGU8aQp-Q8Vx8GoEipJx-uf4Dig3RjcIJ2X4N1ZHCCIyiFd2FrdTIv"

  # delivery-01.ac-cn-hongkong-c.logos.dev.status.im - 16Uiu2HAm8YokiNun9BkeA1ZRmhLbtNUvcwRr64F69tYj9fkGyuEP
  LogosDevDelivery01AcCnHongkongC = "enr:-MG4QFQc9ULfGsloUceZk2i1XiFDuZ4zDoMWIkfOrQQ2rlW_ZLIN7CAzw67W7oGSQ4-sJ3Ehat6-tKxJ3Vj428TlWyABgmlkgnY0gmlwhC_ygr2KbXVsdGlhZGRyc4wACgQv8oK9Bh9A3gOCcnOTAAIIAAAAAQACAAMABAAFAAYAB4lzZWNwMjU2azGhAsL7yU6Z4_I47DAMN8zTlJxl1DF0GVeBtFXj8uQM5vpog3RjcIJ2X4N1ZHCCIyiFd2FrdTIv"

  # delivery-02.ac-cn-hongkong-c.logos.dev.status.im - 16Uiu2HAkvwhGHKNry6LACrB8TmEFoCJKEX29XR5dDUzk3UT3UNSE
  LogosDevDelivery02AcCnHongkongC = "enr:-MG4QDnRm93660fPMd0MAwhYIYS1I6YzNI8lYGZP-IoDy6NYSsmgE-m4aIThWuiveMquo8uZz7f4-jpxjYM48kuZONgBgmlkgnY0gmlwhCtjZwqKbXVsdGlhZGRyc4wACgQrY2cKBh9A3gOCcnOTAAIIAAAAAQACAAMABAAFAAYAB4lzZWNwMjU2azGhAhaMkDdziqKJqwaxdMWwq9A21gF7Wp5eCfDA6VmJkccDg3RjcIJ2X4N1ZHCCIyiFd2FrdTIv"

  # Logos.dev fleet static peers
  LogosDevStaticPeers* = @[
    LogosDevDelivery01DoAms3,
    LogosDevDelivery02DoAms3,
    LogosDevDelivery01GcUsCentral1a,
    LogosDevDelivery02GcUsCentral1a,
    LogosDevDelivery01AcCnHongkongC,
    LogosDevDelivery02AcCnHongkongC,
  ]


type QueueRef* = ref object
  queue*: AsyncQueue[ChatPayload]


type WakuConfig* = object
  nodekey*: crypto.PrivateKey  # TODO: protect key exposure
  port*: uint16
  clusterId*: uint16
  shardId*: seq[uint16]
  pubsubTopic*: string
  staticPeers*: seq[string]
  mixEnabled*: bool
  mixNodes*: seq[string]
  kadBootstrapNodes*: seq[string]
  rlnKeystoreSource*: string
  minMixPoolSize*: int

type
  WakuClient* = ref object
    cfg*: WakuConfig
    node*: WakuNode
    dispatchQueues: seq[QueueRef]
    staticPeerList: seq[RemotePeerInfo]
    mixReady*: bool


proc DefaultConfig*(): WakuConfig =
  # libp2p 1.15.3+: PrivateKey.random expects a libp2p Rng (ref object
  # wrapping a HmacDrbgContext); wrap BearSSL's rng accordingly.
  let drbg = HmacDrbgContext.new()
  let nodeKey = crypto.PrivateKey.random(
    Secp256k1, libp2p_rng.newBearSslRng(drbg)
  ).valueOr:
    raise newException(ValueError, "failed to generate nodeKey: " & $error)
  let clusterId = 2'u16
  let shardId = 1'u16
  var port: uint16 = 50000'u16 + uint16(rand(200))

  result = WakuConfig(nodeKey: nodeKey, port: port, clusterId: clusterId,
      shardId: @[shardId], pubsubTopic: &"/waku/2/rs/{clusterId}/{shardId}",
          staticPeers: LogosDevStaticPeers,
          mixEnabled: false, mixNodes: @[], minMixPoolSize: 4)


proc parseNodeKey*(hex: string): Result[crypto.PrivateKey, string] =
  ## Parse a 64-char hex secp256k1 private key (e.g. to adopt a provisioned
  ## identity whose RLN keystore the mix node pool already knows).
  let sk = SkPrivateKey.init(ncrutils.fromHex(hex)).valueOr:
    return err("invalid nodekey hex: " & $error)
  ok(crypto.PrivateKey(scheme: Secp256k1, skkey: sk))


proc sendBytes*(
    client: WakuClient, contentTopic: string, bytes: seq[byte]
): Future[Result[void, string]] {.async.} =
  let msg = WakuMessage(contentTopic: contentTopic, payload: bytes)

  if client.cfg.mixEnabled:
    # Required (mix) mode: never fall back to relay. Fail fast if the mix pool is
    # below the minimum so the caller/UI can surface "can't send anonymously"
    # instead of blocking indefinitely or silently relaying.
    if not client.mixReady:
      warn "Mix not ready: not enough mix peers",
        poolSize = client.node.getMixNodePoolSize(),
        required = client.cfg.minMixPoolSize
      return err("not enough mix peers available")

    # Bounded wait for RLN spam-protection readiness so the first send right after
    # startup doesn't race RLN init. Membership is STATIC: every mix node loads the
    # same immutable rln_tree.db at startup, so the Merkle root is identical across
    # nodes from t=0 and never changes. There is no root to "converge", so no
    # per-send wait is needed (that only mattered for dynamic on-chain membership).
    if not client.node.wakuMix.isNil:
      var attempts = 0
      while not client.node.wakuMix.mixRlnSpamProtection.isReady() and attempts < 300:
        if attempts mod 5 == 0:
          info "Waiting for RLN spam protection readiness...", attempt = attempts
        await sleepAsync(2.seconds)
        attempts += 1
      if not client.node.wakuMix.mixRlnSpamProtection.isReady():
        warn "RLN spam protection not ready after timeout, sending anyway"

    info "Sending via mix (lightpushPublish)",
      contentTopic = contentTopic, mixPoolSize = client.node.getMixNodePoolSize()
    let publishFut = client.node.lightpushPublish(
      some(PubsubTopic(client.cfg.pubsubTopic)), msg, none(RemotePeerInfo), mixify = true
    )
    # Forward delivery is independent of the SURB reply, so a SURB-reply timeout
    # is a warning (message may still have been delivered), not a failure.
    if not await publishFut.withTimeout(60.seconds):
      await publishFut.cancelAndWait()
      warn "Mix lightpush: no SURB reply within 60s (forward path independent of SURB reply)"
      return ok()
    let res = publishFut.read()
    if res.isErr:
      error "Failed to publish via mix", err = $res.error
      return err("mix send failed")
    info "Message sent via mix successfully"
    return ok()

  # None mode: normal relay publish.
  let res = await client.node.publish(some(PubsubTopic(client.cfg.pubsubTopic)), msg)
  if res.isErr:
    error "Failed to Publish", err = res.error, pubsubTopic = client.cfg.pubsubTopic
    return err("relay send failed")
  return ok()

proc buildWakuNode(cfg: WakuConfig): WakuNode =
  let
    ip = parseIpAddress("0.0.0.0")
    flags = CapabilitiesBitfield.init(relay = true)

  let relayShards = RelayShards.init(cfg.clusterId, cfg.shardId).valueOr:
    error "Relay shards initialization failed", error = error
    quit(QuitFailure)

  var enrBuilder = EnrBuilder.init(cfg.nodeKey)
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
  builder.withNodeKey(cfg.nodeKey)
  builder.withRecord(record)
  builder.withNetworkConfigurationDetails(ip, Port(cfg.port)).tryGet()
  # DNS resolver so /dns4/ fleet bootstrap addrs (kad discovery) resolve and dial;
  # without it libp2p logs "Can't resolve DNSADDR without NameResolver".
  builder.withSwitchConfiguration(
    nameResolver = DnsResolver.new(
      @[initTAddress("1.1.1.1", Port(53)), initTAddress("8.8.8.8", Port(53))]
    )
  )
  let node = builder.build().tryGet()

  node.mountMetadata(cfg.clusterId, cfg.shardId).expect("failed to mount waku metadata protocol")

  result = node


proc splitPeerIdAndAddr(maddr: string): (string, string) =
  let parts = maddr.split("/p2p/")
  if parts.len != 2:
    error "Invalid multiaddress format", maddr = maddr
    return ("", "")
  return (parts[0], parts[1])

proc parseMixNodes(nodeStrs: seq[string]): seq[MixNodePubInfo] =
  for nodeStr in nodeStrs:
    let elements = nodeStr.split(":")
    if elements.len != 2:
      error "Invalid mixnode format, expected multiaddr:mixPubKeyHex", node = nodeStr
      continue
    result.add(MixNodePubInfo(
      multiAddr: elements[0],
      pubKey: intoCurve25519Key(ncrutils.fromHex(elements[1]))
    ))

proc waitForMixPool(client: WakuClient) {.async.} =
  while client.node.getMixNodePoolSize() < client.cfg.minMixPoolSize:
    info "Waiting for mix node pool",
      current = client.node.getMixNodePoolSize(),
      required = client.cfg.minMixPoolSize
    await sleepAsync(1000.milliseconds)
  client.mixReady = true
  notice "Mix node pool ready", poolSize = client.node.getMixNodePoolSize()

proc getMixPoolSize*(client: WakuClient): int =
  if client.cfg.mixEnabled:
    return client.node.getMixNodePoolSize()
  return 0

proc subscribeAllStaticPeers(client: WakuClient) {.async.} =
  ## Issues a fresh filter subscribe to every static peer for both
  ## FilterContentTopic and LibchatDeliveryAddress. Idempotent on the relay
  ## side. Called from start() (so the receiver is ready before any sender
  ## activity) and from taskKeepAlive (so subscriptions don't silently lapse
  ## on long-running clients — ping-then-subscribe was unreliable because
  ## a successful ping doesn't guarantee the content-topic subscription
  ## state is still live on the relay).
  for peerInfo in client.staticPeerList:
    let subscribeRes = await client.node.wakuFilterClient.subscribe(
      peerInfo, client.cfg.pubsubTopic, @[FilterContentTopic, LibchatDeliveryAddress]
    )
    if subscribeRes.isErr():
      warn "filter subscribe failed",
        peerId = $peerInfo.peerId, err = subscribeRes.error
    else:
      debug "filter subscribe ok", peerId = $peerInfo.peerId

proc taskKeepAlive(client: WakuClient) {.async.} =
  while true:
    await sleepAsync(60.seconds) # Subscription maintenance interval
    await client.subscribeAllStaticPeers()

proc getConnectedPeerCount*(client: WakuClient): int =
  var count = 0
  for peerId, peerInfo in client.node.peerManager.switch.peerStore.peers:
    if peerInfo.connectedness == Connected:
      inc count
  return count

proc start*(client: WakuClient) {.async.} =
  setupLog(logging.LogLevel.NOTICE, logging.LogFormat.TEXT)
  await client.node.mountFilter()
  await client.node.mountFilterClient()

  client.node.mountAutoSharding(client.cfg.clusterId, uint32(client.cfg.shardId.len)).isOkOr:
    error "failed to mount auto sharding", error = error

  if client.cfg.mixEnabled:
    let (mixPrivKey, mixPubKey) = mix_curve25519.generateKeyPair().valueOr:
      error "Failed to generate mix key pair", error = error
      quit(QuitFailure)
    let mixNodeInfos = parseMixNodes(client.cfg.mixNodes)
    client.node.mountLightPushClient()

    # Decouple the libp2p peerId from the RLN membership: the node keeps its own
    # (random) peerId, but loads the SELECTED membership credential. The mix-RLN
    # plugin looks up rln_keystore_<peerId>.json in cwd, so stage the chosen
    # credential under THIS node's peerId. The credential is peerId-independent (only
    # the filename is peerId-keyed), so many nodes can share a membership without
    # colliding on a peerId.
    if client.cfg.rlnKeystoreSource.len > 0:
      let pid = $client.node.peerManager.switch.peerInfo.peerId
      try:
        copyFile(client.cfg.rlnKeystoreSource, "rln_keystore_" & pid & ".json")
        info "Staged RLN membership under node peerId", peerId = pid
      except CatchableError as e:
        error "Failed to stage RLN credential",
          source = client.cfg.rlnKeystoreSource, err = e.msg

    (await client.node.mountMix(client.cfg.clusterId, mixPrivKey, mixNodeInfos,
                                disableSpamProtection = false)).isOkOr:
      error "Failed to mount mix protocol", error = $error
      quit(QuitFailure)

    # Fleet mode: discover the mix nodes (and their curve25519 pubkeys) via libp2p
    # Kademlia service discovery instead of a static mixNodes list. The discovery
    # logic lives in nwaku (waku_kademlia) — we only mount it with the bootstrap
    # nodes, because the chat builds its WakuNode by hand and bypasses the
    # conf-driven factory that would otherwise auto-mount it (mirrors apps/chat2mix).
    # Discovered mix peers land in the peerManager and fill the pool waitForMixPool
    # waits on.
    if client.cfg.kadBootstrapNodes.len > 0:
      var kadBootstrapPeers: seq[(PeerId, seq[MultiAddress])]
      for nodeStr in client.cfg.kadBootstrapNodes:
        let pInfo = parsePeerInfo(nodeStr).valueOr:
          warn "Failed to parse kad bootstrap node", node = nodeStr, err = error
          continue
        kadBootstrapPeers.add((pInfo.peerId, pInfo.addrs))
      if kadBootstrapPeers.len > 0:
        client.node.mountKademlia(
          KademliaDiscoveryConf(
            bootstrapNodes: kadBootstrapPeers,
            servicesToDiscover: toHashSet(@[mix_proto.MixProtocolID]),
            randomLookupInterval: chronos.seconds(15),
            serviceLookupInterval: chronos.seconds(15),
            # Don't block node startup on the initial DHT bootstrap (an iterative
            # self-lookup + per-bucket refresh). With it on, KadDHT.start() ->
            # await bootstrap() runs inside switch.start(), so the whole node start
            # (and the UI "Starting...") waits for discovery to converge. Disabled,
            # the node comes up immediately and the mix pool fills in the background
            # via maintainBuckets + runServiceLookupLoop + runServicePeerTopUp.
            kadDhtConfig: KadDHTConfig.new(disableBootstrapping = true),
            discoConfig: sd_types.ServiceDiscoveryConfig.new(),
            clientMode: false,
            xprPublishing: true,
          )
        ).isOkOr:
          error "Failed to mount kademlia mix discovery", error = error
          quit(QuitFailure)
        info "Kademlia mix discovery mounted",
          bootstrapPeers = kadBootstrapPeers.len

    asyncSpawn client.waitForMixPool()

  await client.node.start()

  client.node.peerManager.start()

  # Register filter push handler for incoming messages (no relay/gossipsub needed)
  proc filterHandler(pubsubTopic: PubsubTopic, msg: WakuMessage) {.async, gcsafe.} =
    debug "filter message received",
      pubsubTopic = pubsubTopic,
      contentTopic = msg.contentTopic

    let payload = msg.toChatPayload(pubsubTopic)
    for queueRef in client.dispatchQueues:
      await queueRef.queue.put(payload)

  client.node.wakuFilterClient.registerPushHandler(filterHandler)

  # Connect to all configured static peers
  if client.staticPeerList.len > 0:
    info "Connecting to static peers", peerCount = client.staticPeerList.len
    await client.node.connectToNodes(client.staticPeerList)
    info "Connected to static peers"
  else:
    warn "No valid static peers configured"

  # Subscribe to every static peer SYNCHRONOUSLY before start() returns so
  # the receiver has live content-topic subscriptions in place before any
  # sender mix-publish fires. taskKeepAlive then re-subscribes every 60s
  # to defend against silent server-side subscription expiry.
  await client.subscribeAllStaticPeers()
  asyncSpawn taskKeepAlive(client)

  info "Waku client started",
    relayMounted = not client.node.wakuRelay.isNil,
    mixMounted = not client.node.wakuMix.isNil,
    connectedPeers = client.getConnectedPeerCount()

  # Debug: periodically log relay/mesh status
  proc meshStatusTask(client: WakuClient) {.async.} =
    while true:
      await sleepAsync(15.seconds)
      let connPeers = client.getConnectedPeerCount()
      info "Peer status",
        pubsubTopic = client.cfg.pubsubTopic,
        connectedPeers = connPeers,
        mixReady = client.mixReady,
        mixPoolSize = (if client.cfg.mixEnabled and not client.node.wakuMix.isNil: client.node.getMixNodePoolSize() else: 0)

  asyncSpawn meshStatusTask(client)

proc initWakuClient*(cfg: WakuConfig): WakuClient =
  var peerInfos: seq[RemotePeerInfo] = @[]
  for peerStr in cfg.staticPeers:
    if peerStr.startsWith("/"):
      let peerInfo = parsePeerInfo(peerStr).valueOr:
        error "Failed to parse multiaddr peer", peer = peerStr, err = error
        continue
      peerInfos.add(peerInfo)
    else:
      let enrRecord = eth_enr.Record.fromURI(peerStr).valueOr:
        error "Failed to parse ENR", enr = peerStr, err = error
        continue
      let peerInfo = enrRecord.toRemotePeerInfo().valueOr:
        error "Failed to convert ENR to PeerInfo", enr = peerStr, err = error
        continue
      peerInfos.add(peerInfo)

  result = WakuClient(cfg: cfg, node: buildWakuNode(cfg), dispatchQueues: @[],
      staticPeerList: peerInfos)

proc addDispatchQueue*(client: var WakuClient, queue: QueueRef) =
  client.dispatchQueues.add(queue)

proc stop*(client: WakuClient) {.async.} =
  await client.node.stop()
