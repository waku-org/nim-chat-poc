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
  conversation_store,
  conversations,
  conversations/convo_impl,
  crypto,
  delivery/waku_client,
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
  MessageCallback*[T] = proc(conversation: Conversation, msg: T): Future[void] {.async.}
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
  keyStore: Table[string, KeyEntry]          # Keyed by HexEncoded Public Key
  conversations: Table[string, Conversation] # Keyed by conversation ID
  inboundQueue: QueueRef
  isRunning: bool

  newMessageCallbacks: seq[MessageCallback[ContentFrame]]
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

    var q = QueueRef(queue: newAsyncQueue[ChatPayload](10))
    var c = Client(ident: ident,
                  ds: waku,
                  keyStore: initTable[string, KeyEntry](),
                  conversations: initTable[string, Conversation](),
                  inboundQueue: q,
                  isRunning: false,
                  newMessageCallbacks: @[],
                  newConvoCallbacks: @[])

    let defaultInbox = initInbox(c.ident.getPubkey())
    c.conversations[defaultInbox.id()] = defaultInbox

    notice "Client started", client = c.ident.getId(),
        defaultInbox = defaultInbox
    result = c
  except Exception as e:
    error "newCLient", err = e.msg

#################################################
# Parameter Access
#################################################

proc getId*(client: Client): string =
  result = client.ident.getId()

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

proc onNewMessage*(client: Client, callback: MessageCallback[ContentFrame]) =
  client.newMessageCallbacks.add(callback)

proc notifyNewMessage(client: Client, convo: Conversation,
    content: ContentFrame) =
  for cb in client.newMessageCallbacks:
    discard cb(convo, content)

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

proc createIntroBundle*(self: var Client): IntroBundle =
  ## Generates an IntroBundle for the client, which includes
  ## the required information to send a message.

  # Create Ephemeral keypair, save it in the key store
  let ephemeralKey = generateKey()

  self.keyStore[ephemeralKey.getPublicKey().bytes().bytesToHex()] = KeyEntry(
    keyType: "ephemeral",
    privateKey: ephemeralKey,
    timestamp: getCurrentTimestamp()
  )

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
  notice "Creating conversation", client = client.getId(), topic = convo.id()
  client.conversations[convo.id()] = convo
  client.notifyNewConversation(convo)

proc getConversation*(client: Client, convoId: string): Conversation =
  notice "Get conversation", client = client.getId(), convoId = convoId
  result = client.conversations[convoId]

proc newPrivateConversation*(client: Client,
    introBundle: IntroBundle): Future[Option[ChatError]] {.async.} =
  ## Creates a private conversation with the given `IntroBundle`.
  ## `IntroBundles` are provided out-of-band.

  notice "New PRIVATE Convo ", client = client.getId(),
      fromm = introBundle.ident.mapIt(it.toHex(2)).join("")

  let destPubkey = loadPublicKeyFromBytes(introBundle.ident).valueOr:
    raise newException(ValueError, "Invalid public key in intro bundle.")

  let convoId = conversationIdFor(destPubkey)
  let destConvoTopic = topicInbox(destPubkey.getAddr())

  let invite = InvitePrivateV1(
    initiator: @(client.ident.getPubkey().bytes()),
    initiatorEphemeral: @[0, 0], # TODO: Add ephemeral
    participant: @(destPubkey.bytes()),
    participantEphemeralId: introBundle.ephemeralId,
    discriminator: "test"
    )



  let env = wrapEnv(encrypt(InboxV1Frame(invitePrivateV1: invite,
      recipient: "")), convoId)

  let deliveryAckCb = proc(
        conversation: Conversation,
      msgId: string): Future[void] {.async.} =
    client.notifyDeliveryAck(conversation, msgId)

  let convo = initPrivateV1(client.identity(), destPubkey, "default", deliveryAckCb)
  client.addConversation(convo)

  # TODO: Subscribe to new content topic

  await client.ds.sendPayload(destConvoTopic, env)
  return none(ChatError)


#################################################
# Payload Handling
#################################################

proc parseMessage(client: Client, msg: ChatPayload) {.raises: [ValueError,
    SerializationError].} =
  ## Receives a incoming payload, decodes it, and processes it.

  let envelope = decode(msg.bytes, WapEnvelopeV1).valueOr:
    raise newException(ValueError, "Failed to decode WapEnvelopeV1: " & error)

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

proc stop*(client: Client) =
  ## Stop the client.
  client.isRunning = false
  notice "Client stopped", client = client.getId()
