## Main Entry point to the ChatSDK.
## Clients are the primary manager of sending and receiving 
## messages, and managing conversations.


import # Foreign
  chronicles,
  chronos,
  sds,
  sequtils,
  std/tables,
  std/sequtils,
  strformat,
  strutils,
  tables,
  types

import #local
  conversations,
  conversations/convo_impl,
  crypto,
  delivery/waku_client,
  errors,
  identity,
  inbox,
  proto_types,
  types,
  utils


logScope:
  topics = "chat client"
 
#################################################
# Definitions
#################################################

type
  MessageCallback* = proc(conversation: Conversation, msg: ReceivedMessage): Future[void] {.async.}
  NewConvoCallback* = proc(conversation: Conversation): Future[void] {.async.}
  DeliveryAckCallback* = proc(conversation: Conversation,
      msgId: MessageId): Future[void] {.async.}


type KeyEntry* = object
  keyType: string
  privateKey: PrivateKey
  timestamp: int64

type Client* = ref object
  ident: Identity
  ds*: WakuClient
  keyStore: Table[RemoteKeyIdentifier, seq[KeyEntry]]
  conversations: Table[string, Conversation] # Keyed by conversation ID
  inboundQueue: QueueRef
  isRunning: bool
  inbox: Inbox

  newMessageCallbacks: seq[MessageCallback]
  newConvoCallbacks: seq[NewConvoCallback]
  deliveryAckCallbacks: seq[DeliveryAckCallback]

#################################################
# Constructors
#################################################

proc newClient*(cfg: WakuConfig, ident: Identity): Client {.raises: [IOError,
    ValueError, SerializationError].} =
  ## Creates new instance of a `Client` with a given `WakuConfig`
  try:
    let waku = initWakuClient(cfg)
    let rm = newReliabilityManager().valueOr:
      raise newException(ValueError, fmt"SDS InitializationError")

    let defaultInbox = initInbox(ident)

    var q = QueueRef(queue: newAsyncQueue[ChatPayload](10))
    var c = Client(ident: ident,
                  ds: waku,
                  keyStore: initTable[RemoteKeyIdentifier, seq[KeyEntry]](),
                  conversations: initTable[string, Conversation](),
                  inboundQueue: q,
                  isRunning: false,
                  inbox: defaultInbox,
                  newMessageCallbacks: @[],
                  newConvoCallbacks: @[])

    c.conversations[defaultInbox.id()] = defaultInbox

    notice "Client started", client = c.ident.getName(),
        defaultInbox = defaultInbox, inTopic= topic_inbox(c.ident.get_addr())
    result = c
  except Exception as e:
    error "newCLient", err = e.msg

#################################################
# Parameter Access
#################################################

proc getId*(client: Client): string =
  result = client.ident.getName()

proc identity*(client: Client): Identity =
  result = client.ident

proc defaultInboxConversationId*(self: Client): string =
  ## Returns the default inbox address for the client.
  result = conversationIdFor(self.ident.getPubkey())

proc getConversationFromHint(self: Client,
    conversationHint: string): Result[Option[Conversation], string] =

  # TODO: Implementing Hinting
  if not self.conversations.hasKey(conversationHint):
    ok(none(Conversation))
  else:
    ok(some(self.conversations[conversationHint]))


proc listConversations*(client: Client): seq[Conversation] =
  result = toSeq(client.conversations.values())

#################################################
# Callback Handling
#################################################

proc onNewMessage*(client: Client, callback: MessageCallback) =
  client.newMessageCallbacks.add(callback)

proc notifyNewMessage*(client: Client,  convo: Conversation, msg: ReceivedMessage) =
  for cb in client.newMessageCallbacks:
    discard cb(convo, msg)

proc onNewConversation*(client: Client, callback: NewConvoCallback) =
  client.newConvoCallbacks.add(callback)

proc notifyNewConversation(client: Client, convo: Conversation) =
  for cb in client.newConvoCallbacks:
    discard cb(convo)

proc onDeliveryAck*(client: Client, callback: DeliveryAckCallback) =
  client.deliveryAckCallbacks.add(callback)

proc notifyDeliveryAck(client: Client, convo: Conversation,
    messageId: MessageId) =
  for cb in client.deliveryAckCallbacks:
    discard cb(convo, messageId)

#################################################
# Functional
#################################################

proc cacheInviteKey(self: var Client, key: PrivateKey) =

  let rki_ephemeral = generateRemoteKeyIdentifier(key.getPublicKey())

  self.keyStore[rki_ephemeral] = @[KeyEntry(
    keyType: "ephemeral",
    privateKey: key,
    timestamp: getCurrentTimestamp()
  )]

proc createIntroBundle*(self: var Client): IntroBundle =
  ## Generates an IntroBundle for the client, which includes
  ## the required information to send a message.

  # Create Ephemeral keypair, save it in the key store
  let ephemeralKey = generateKey()
  self.cacheInviteKey(ephemeralKey)

  result = IntroBundle(
    ident: @(self.ident.getPubkey().bytes()),
    ephemeral: @(ephemeralKey.getPublicKey().bytes()),
  )

  notice "IntroBundleCreated", client = self.getId(),
      pubBytes = result.ident


#################################################
# Conversation Initiation
#################################################

proc addConversation*(client: Client, convo: Conversation) =
  notice "Creating conversation", client = client.getId(), convoId = convo.id()
  client.conversations[convo.id()] = convo
  client.notifyNewConversation(convo)

proc getConversation*(client: Client, convoId: string): Conversation =
  notice "Get conversation", client = client.getId(), convoId = convoId
  result = client.conversations[convoId]

proc newPrivateConversation*(client: Client,
    introBundle: IntroBundle, content: Content): Future[Option[ChatError]] {.async.} =
  ## Creates a private conversation with the given `IntroBundle`.
  ## `IntroBundles` are provided out-of-band.
  let remote_pubkey = loadPublicKeyFromBytes(introBundle.ident).get()
  let remote_ephemeralkey = loadPublicKeyFromBytes(introBundle.ephemeral).get()

  let convo = await client.inbox.inviteToPrivateConversation(client.ds,remote_pubkey, remote_ephemeralkey, content )
  client.addConversation(convo)     # TODO: Fix re-entrantancy bug. Convo needs to be saved before payload is sent.

  return none(ChatError)


#################################################
# Payload Handling
# Receives a incoming payload, decodes it, and processes it.
#################################################

proc parseMessage(client: Client, msg: ChatPayload) {.raises: [ValueError,
    SerializationError].} =
  let envelopeRes = decode(msg.bytes, WapEnvelopeV1)
  if envelopeRes.isErr:
    debug "Failed to decode WapEnvelopeV1", client = client.getId(), err = envelopeRes.error
    return
  let envelope = envelopeRes.get()

  let convo = block:
    let opt = client.getConversationFromHint(envelope.conversationHint).valueOr:
      raise newException(ValueError, "Failed to get conversation: " & error)

    if opt.isSome():
      opt.get()
    else:
      let k = toSeq(client.conversations.keys()).join(", ")
      warn "No conversation found", client = client.getId(),
        hint = envelope.conversationHint, knownIds = k
      return

  try:
    convo.handleFrame(client, envelope.payload)
  except Exception as e:
    error "HandleFrame Failed", error = e.msg

#################################################
# Async Tasks
#################################################

proc messageQueueConsumer(client: Client) {.async.} =
  ## Main message processing loop
  info "Message listener started"

  while client.isRunning:
    let message = await client.inboundQueue.queue.get()

    let topicRes = inbox.parseTopic(message.contentTopic).or(private_v1.parseTopic(message.contentTopic))
    if topicRes.isErr:
      debug "Invalid content topic", client = client.getId(), err = topicRes.error, contentTopic = message.contentTopic
      continue

    notice "Inbound Message Received", client = client.getId(),
        contentTopic = message.contentTopic, len = message.bytes.len()
    try:
      client.parseMessage(message)

    except CatchableError as e:
      error "Error in message listener", err = e.msg,
          pubsub = message.pubsubTopic, contentTopic = message.contentTopic


#################################################
# Control Functions
#################################################

proc start*(client: Client) {.async.} =
  ## Start `Client` and listens for incoming messages.
  client.ds.addDispatchQueue(client.inboundQueue)
  asyncSpawn client.ds.start()

  client.isRunning = true

  asyncSpawn client.messageQueueConsumer()

  notice "Client start complete", client = client.getId()

proc stop*(client: Client) {.async.} =
  ## Stop the client.
  await client.ds.stop()
  client.isRunning = false
  notice "Client stopped", client = client.getId()
