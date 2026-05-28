import
  chronicles,
  chronos,
  confutils,
  eth/common/addresses as eth_addresses,
  eth/common/keys as eth_keys,
  eth/p2p/discoveryv5/enr as eth_enr,
  libp2p/crypto/crypto,
  libp2p/crypto/curve25519,
  libp2p/peerid,
  libp2p/protocols/mix,
  libp2p/protocols/mix/curve25519 as mix_curve25519,
  libp2p/protocols/mix/entry_connection,
  libp2p/protocols/mix/mix_protocol as mix_proto,
  nimcrypto/utils as ncrutils,
  std/[random, strutils],
  stew/byteutils,
  strformat,
  waku/[
    common/logging,
    common/enr as common_enr,
    node/peer_manager,
    waku_core,
    waku_core/codecs,
    waku_node,
    waku_enr,
    waku_mix/protocol as waku_mix_protocol,
    waku_mix/logos_core_client as mix_lez_client,
    waku_lightpush/client as lightpush_client,
    discovery/waku_discv5,
    discovery/waku_dnsdisc,
    factory/builder,
    waku_filter_v2/client,
    waku_rln_relay/rln_gifter/client as rln_gifter_client,
    waku_rln_relay/rln_gifter/protocol as rln_gifter_protocol,
  ],
  mix_rln_spam_protection/onchain_group_manager,
  mix_rln_spam_protection/rln_interface as mix_rln_interface,
  mix_rln_spam_protection/spam_protection


logScope:
  topics = "chat waku"

type ChatPayload* = object
  pubsubTopic*: PubsubTopic
  contentTopic*: string
  timestamp*: Timestamp
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
  destPeerAddr*: string
  minMixPoolSize*: int
  gifterNodeAddr*: string
  gifterAuthKey*: string

type
  WakuClient* = ref object
    cfg*: WakuConfig
    node*: WakuNode
    dispatchQueues: seq[QueueRef]
    staticPeerList: seq[RemotePeerInfo]
    mixReady*: bool
    destPeerId: PeerId


proc DefaultConfig*(): WakuConfig =
  let nodeKey = crypto.PrivateKey.random(Secp256k1, crypto.newRng()[])[]
  let clusterId = 2'u16
  let shardId = 1'u16
  var port: uint16 = 50000'u16 + uint16(rand(200))

  result = WakuConfig(nodeKey: nodeKey, port: port, clusterId: clusterId,
      shardId: @[shardId], pubsubTopic: &"/waku/2/rs/{clusterId}/{shardId}",
          staticPeers: LogosDevStaticPeers,
          mixEnabled: false, mixNodes: @[], destPeerAddr: "", minMixPoolSize: 4,
          gifterNodeAddr: "",
          gifterAuthKey: "")


proc sendBytes*(client: WakuClient, contentTopic: string,
    bytes: seq[byte]) {.async.} =
  let msg = WakuMessage(contentTopic: contentTopic, payload: bytes)

  if client.cfg.mixEnabled:
    # Wait for mix pool to be ready before sending
    while not client.mixReady:
      info "Waiting for mix pool before sending..."
      await sleepAsync(2.seconds)

    # Wait for RLN spam protection to be ready (roots + proofs fetched from LEZ)
    if not client.node.wakuMix.isNil:
      var attempts = 0
      while not client.node.wakuMix.mixRlnSpamProtection.isReady() and attempts < 45:
        if attempts mod 5 == 0:
          info "Waiting for RLN spam protection readiness...", attempt = attempts
        await sleepAsync(2.seconds)
        attempts += 1
      if client.node.wakuMix.mixRlnSpamProtection.isReady():
        let gm = client.node.wakuMix.mixRlnSpamProtection.groupManager
        if gm of OnchainLEZGroupManager:
          let lezGm = OnchainLEZGroupManager(gm)
          let pollMs = lezGm.getPollInterval().milliseconds
          let stableMs = max(pollMs * 2, 5000)
          let probeMs = max(pollMs div 4, 1000)
          # The gifter serializes registrations through a worker; on slow
          # chains the chat sender may sit at the tail of a queue of up to
          # ~6 other registrations, each waiting up to confirmDeadlineMs
          # (300s) for chain commit. Budget enough headroom that we don't
          # publish against an un-corrected optimistic leaf.
          let deadlineMs = 1_500_000

          # Phase 1: wait for the watcher to confirm our registration on
          # chain plus a cushion of 2 poll intervals, so peers have had
          # time to fetch the post-registration root. Without this, a
          # first publish issued right after the gifter's optimistic
          # response can carry a root mix peers haven't seen yet.
          let cushionMs = max(pollMs * 2, 10_000)
          let confirmDeadline = Moment.now() + chronos.milliseconds(deadlineMs)
          info "Waiting for membership confirmation + propagation cushion",
            cushionMs = cushionMs, pollMs = pollMs
          var confirmedSeen = false
          while Moment.now() < confirmDeadline:
            let confirmedAt = lezGm.membershipConfirmedAt()
            if confirmedAt.isSome:
              let elapsedMs = (Moment.now() - confirmedAt.get()).milliseconds
              if elapsedMs >= cushionMs:
                confirmedSeen = true
                break
            await sleepAsync(chronos.milliseconds(probeMs))
          if confirmedSeen:
            info "Membership confirmed + cushion elapsed"
          else:
            warn "Membership confirmation did not arrive within deadline, publishing anyway",
              deadlineMs = deadlineMs

          # Phase 2: defensive — wait until our proof's merkle root has
          # been in our own validRoots window for 2 full poll cycles.
          # Catches the rare case where the watcher confirmed but the
          # poll loop hasn't yet caught up to the matching proof root.
          info "Waiting for proof root to stabilize in valid_roots",
            pollMs = pollMs, stableMs = stableMs
          var lastRoot = lezGm.proofRoot()
          var stableSince = Moment.now()
          let deadline = Moment.now() + chronos.milliseconds(deadlineMs)
          var settled = false
          while Moment.now() < deadline:
            await sleepAsync(chronos.milliseconds(probeMs))
            let cur = lezGm.proofRoot()
            if cur != lastRoot:
              lastRoot = cur
              stableSince = Moment.now()
              continue
            if cur.isSome and lezGm.rootTracker.containsRoot(cur.get()):
              if Moment.now() - stableSince >= chronos.milliseconds(stableMs):
                settled = true
                break
          if settled:
            info "Proof root stable in valid_roots, proceeding to publish"
          else:
            warn "Proof root did not stabilize within deadline, publishing anyway",
              deadlineMs = deadlineMs
        else:
          info "RLN spam protection ready (non-LEZ), waiting 30s for root convergence"
          await sleepAsync(30.seconds)
      else:
        warn "RLN spam protection not ready after timeout, sending anyway"

  if client.cfg.mixEnabled and client.mixReady:
    info "Sending via mix (lightpushPublish)", contentTopic = contentTopic, mixPoolSize = client.node.getMixNodePoolSize()
    let publishFut = client.node.lightpushPublish(
      some(PubsubTopic(client.cfg.pubsubTopic)), msg, none(RemotePeerInfo), mixify = true
    )
    if not await publishFut.withTimeout(15.seconds):
      await publishFut.cancelAndWait()
      error "Mix lightpush timed out (no SURB reply within deadline)"
    else:
      let res = publishFut.read()
      if res.isErr:
        error "Failed to publish via mix", err = $res.error
      else:
        info "Message sent via mix successfully"
  else:
    warn "Sending via relay fallback (mix not ready or not enabled)",
      mixEnabled = client.cfg.mixEnabled, mixReady = client.mixReady
    let res = await client.node.publish(some(PubsubTopic(client.cfg.pubsubTopic)), msg)
    if res.isErr:
      error "Failed to Publish", err = res.error,
          pubsubTopic = client.cfg.pubsubTopic

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

proc taskKeepAlive(client: WakuClient) {.async.} =
  while true:
    for peerInfo in client.staticPeerList:
      debug "maintaining subscription", peerId = $peerInfo.peerId
      # First use filter-ping to check if we have an active subscription
      let pingRes = await client.node.wakuFilterClient.ping(peerInfo)
      if pingRes.isErr():
        # No subscription found. Let's subscribe.
        warn "no subscription found. Sending subscribe request"

        # TODO: Use filter. Removing this stops relay from working so keeping for now
        let subscribeRes = await client.node.wakuFilterClient.subscribe(
          peerInfo, client.cfg.pubsubTopic, @[FilterContentTopic, LibchatDeliveryAddress]
        )

        if subscribeRes.isErr():
          error "subscribe request failed. Skipping.", err = subscribeRes.error
          continue
        else:
          debug "subscribe request successful."
      else:
        debug "subscription found."

    await sleepAsync(60.seconds) # Subscription maintenance interval

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
    (await client.node.mountMix(client.cfg.clusterId, mixPrivKey, mixNodeInfos,
                                useOnchainLEZ = true)).isOkOr:
      error "Failed to mount mix protocol", error = $error
      quit(QuitFailure)

  # Wire LEZ callbacks BEFORE node.start() so spam protection can initialize
  if client.cfg.mixEnabled and not client.node.wakuMix.isNil:
    let gm = client.node.wakuMix.mixRlnSpamProtection.groupManager
    if gm of OnchainLEZGroupManager:
      let lezGm = OnchainLEZGroupManager(gm)
      let clientFetchRoots = mix_lez_client.makeFetchLatestRoots()
      let clientFetchProof = mix_lez_client.makeFetchMerkleProof()
      let fetchRoots: onchain_group_manager.FetchRootsCallback = clientFetchRoots
      let fetchProof: onchain_group_manager.FetchProofCallback = clientFetchProof
      lezGm.setFetchCallbacks(fetchRoots, fetchProof)
      mix_lez_client.setGroupManagerRef(lezGm)
      info "Wired LEZ callbacks for mix RLN spam protection"

    let (_, destId) = splitPeerIdAndAddr(client.cfg.destPeerAddr)
    client.destPeerId = PeerId.init(destId).valueOr:
      error "Failed to parse destination peer ID", error = error
      quit(QuitFailure)
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

  if client.cfg.mixEnabled and client.cfg.gifterNodeAddr.len > 0 and
      not client.node.wakuMix.isNil:
    let gm = client.node.wakuMix.mixRlnSpamProtection.groupManager
    if gm of OnchainLEZGroupManager:
      let lezGm = OnchainLEZGroupManager(gm)
      let gifterClient = rln_gifter_client.WakuRlnGifterClient.new(
        client.node.peerManager, client.node.rng
      )
      let gifterPeer = parsePeerInfo(client.cfg.gifterNodeAddr).valueOr:
        error "Failed to parse gifter peer", error = error
        quit(QuitFailure)
      client.node.peerManager.addServicePeer(gifterPeer, WakuRlnGifterCodec)

      let idCred =
        if lezGm.credentials.isSome:
          lezGm.credentials.get()
        else:
          mix_rln_interface.membershipKeyGen().valueOr:
            error "Failed to generate RLN identity", error = $error
            quit(QuitFailure)
      let idCommitmentBytes = @(idCred.idCommitment)

      info "Registering via RLN gifter",
        gifterPeer = client.cfg.gifterNodeAddr,
        identityCommitmentLen = idCommitmentBytes.len

      var authType: seq[byte]
      var authPayload: seq[byte]
      if client.cfg.gifterAuthKey.len > 0:
        let seckey = eth_keys.PrivateKey.fromHex(client.cfg.gifterAuthKey).valueOr:
          error "Failed to parse gifter auth key", error = $error
          quit(QuitFailure)
        let sig = seckey.sign(rln_gifter_protocol.eip191Message(idCommitmentBytes))
        authPayload = @(sig.toRaw())
        for c in rln_gifter_protocol.EthAllowlistAuthType:
          authType.add(byte(c))
        info "Signing gifter request with EIP-191 auth key",
          signer = seckey.toPublicKey().to(eth_addresses.Address).to0xHex()

      let regRes = await gifterClient.requestMembership(
        idCommitmentBytes,
        some(uint64(lezGm.userMessageLimit)),
        gifterPeer,
        authType,
        authPayload,
      )
      if regRes.isErr:
        error "Failed to register via gifter", error = regRes.error
        quit(QuitFailure)
      let success = regRes.get()

      let configAccountId = success.configAccountId.valueOr:
        error "Gifter response missing configAccountId extension"
        quit(QuitFailure)

      lezGm.credentials = some(idCred)
      lezGm.membershipIndex = some(onchain_group_manager.MembershipIndex(success.leafIndex))
      mix_lez_client.setRlnConfig(configAccountId, success.leafIndex.int)

      info "Registered via RLN gifter",
        leafIndex = success.leafIndex,
        configAccount = configAccountId

      # Correct the optimistic leaf via the status codec if a concurrent
      # registration tx beat ours to the slot. Pre-publish self-verify drops
      # bad proofs in the meantime.
      let watcherLezGm = lezGm
      let watcherConfigAccount = configAccountId
      asyncSpawn gifterClient.watchMembershipConfirmation(
        gifterPeer, configAccountId, idCommitmentBytes, success.leafIndex,
        "Chat-client",
        proc(authLeaf: uint64) {.gcsafe, raises: [].} =
          if some(onchain_group_manager.MembershipIndex(authLeaf)) !=
              watcherLezGm.membershipIndex:
            watcherLezGm.membershipIndex =
              some(onchain_group_manager.MembershipIndex(authLeaf))
            mix_lez_client.setRlnConfig(watcherConfigAccount, authLeaf.int)
          watcherLezGm.markMembershipConfirmed(),
      )

  asyncSpawn taskKeepAlive(client)

  if client.cfg.mixEnabled and not client.node.wakuMix.isNil:
    let gm = client.node.wakuMix.mixRlnSpamProtection.groupManager
    if gm of OnchainLEZGroupManager:
      OnchainLEZGroupManager(gm).startPolling()

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
