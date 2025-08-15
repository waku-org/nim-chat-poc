## Main Entry point to the ChatSDK.
## Clients are the primary manager of sending and receiving 
## messages, and managing conversations.


import # Foreign
  chronicles,
  chronos,
  std/sequtils,
  strformat,
  strutils,
  tables

import #local
  conversations/private_v1,
  crypto,
  identity,
  inbox,
  proto_types,
  types,
  utils,
  waku_client


logScope:
  topics = "chat client"

#################################################
# Definitions
#################################################


type KeyEntry* = object
  keyType: string
  privateKey: PrivateKey
  timestamp: int64


type
  SupportedConvoTypes* = Inbox | PrivateV1

  ConvoType* = enum
    InboxV1Type, PrivateV1Type

  ConvoWrapper* = object
    case convoType*: ConvoType
    of InboxV1Type:
      inboxV1*: Inbox
    of PrivateV1Type:
      privateV1*: PrivateV1


type Client* = ref object
  ident: Identity
  ds*: WakuClient
  keyStore: Table[string, KeyEntry]          # Keyed by HexEncoded Public Key
  conversations: Table[string, ConvoWrapper] # Keyed by conversation ID
  inboundQueue: QueueRef
  isRunning: bool

#################################################
# Constructors
#################################################

proc newClient*(name: string, cfg: WakuConfig): Client =
  ## Creates new instance of a `Client` with a given `WakuConfig`
  let waku = initWakuClient(cfg)

  var q = QueueRef(queue: newAsyncQueue[ChatPayload](10))
  var c = Client(ident: createIdentity(name),
                 ds: waku,
                 keyStore: initTable[string, KeyEntry](),
                 conversations: initTable[string, ConvoWrapper](),
                 inboundQueue: q,
                 isRunning: false)

  let defaultInbox = initInbox(c.ident.getAddr())
  c.conversations[conversationIdFor(c.ident.getPubkey(
    ))] = ConvoWrapper(convoType: InboxV1Type, inboxV1: defaultInbox)


  notice "Client started", client = c.ident.getId(),
      defaultInbox = defaultInbox
  result = c

#################################################
# Parameter Access
#################################################

proc getId(client: Client): string =
  result = client.ident.getId()

proc defaultInboxConversationId*(self: Client): string =
  ## Returns the default inbox address for the client.
  result = conversationIdFor(self.ident.getPubkey())

proc getConversationFromHint(self: Client,
    conversationHint: string): Result[Option[ConvoWrapper], string] =

  # TODO: Implementing Hinting
  if not self.conversations.hasKey(conversationHint):
    ok(none(ConvoWrapper))
  else:
    ok(some(self.conversations[conversationHint]))


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
    timestamp: getTimestamp()
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

proc createPrivateConversation(client: Client, participant: PublicKey,
    discriminator: string = "default"): Option[ChatError] =
  ## Creates a private conversation with the given participant and discriminator.
  ## Discriminator allows multiple conversations to exist between the same
  ## participants.

  let convo = initPrivateV1(client.ident, participant, discriminator)

  notice "Creating PrivateV1 conversation", topic = convo.getConvoId()
  client.conversations[convo.getConvoId()] = ConvoWrapper(
    convoType: PrivateV1Type,
    privateV1: convo
  )

  return some(convo.getConvoId())

proc newPrivateConversation*(client: Client,
    introBundle: IntroBundle): Future[Option[ChatError]] {.async.} =
  ## Creates a private conversation with the given `IntroBundle`.
  ## `IntroBundles` are provided out-of-band.

  notice "New PRIVATE Convo ", clientId = client.getId(),
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

  discard createPrivateConversation(client, destPubkey)
  # TODO: Subscribe to new content topic

  await client.ds.sendPayload(destConvoTopic, env)
  return none(ChatError)

proc acceptPrivateInvite(client: Client,
    invite: InvitePrivateV1): Option[ChatError] =
  ## Allows Recipients to join the conversation.

  notice "ACCEPT PRIVATE Convo ", clientId = client.getId(),
      fromm = invite.initiator.mapIt(it.toHex(2)).join("")

  let destPubkey = loadPublicKeyFromBytes(invite.initiator).valueOr:
    raise newException(ValueError, "Invalid public key in intro bundle.")

  discard createPrivateConversation(client, destPubkey)
  # TODO: Subscribe to new content topic

  result = none(ChatError)


#################################################
# Payload Handling
#################################################

proc handleInboxFrame(client: Client, convo: Inbox, bytes: seq[byte]) =
  ## Dispatcher for Incoming `InboxV1Frames`.
  ## Calls further processing depending on the kind of frame.

  let enc = decode(bytes, EncryptedPayload).valueOr:
    raise newException(ValueError, "Failed to decode payload")

  let frame = convo.decrypt(enc).valueOr:
    error "Decrypt failed", error = error
    raise newException(ValueError, "Failed to Decrypt MEssage: " &
        error)

  case getKind(frame):
  of typeInvitePrivateV1:
    notice "Receive PrivateInvite", client = client.getId(),
        frame = frame.invitePrivateV1
    discard client.acceptPrivateInvite(frame.invitePrivateV1)

  of typeNote:
    notice "Receive Note", text = frame.note.text

proc handlePrivateFrame(client: Client, convo: PrivateV1, bytes: seq[byte]) =
  ## Dispatcher for Incoming `PrivateV1Frames`.
  ## Calls further processing depending on the kind of frame.
  let enc = decode(bytes, EncryptedPayload).get()       # TODO: handle result
  let frame = convo.decrypt(enc) # TODO: handle result

  case frame.getKind():
  of typeContentFrame:
    notice "Got Mail", client = client.getId(),
        text = frame.content.bytes.toUtfString()
  of typePlaceholder:
    notice "Got Placeholder", client = client.getId(),
        text = frame.placeholder.counter

proc parseMessage(client: Client, msg: ChatPayload) =
  ## Receives a incoming payload, decodes it, and processes it.
  info "Parse", clientId = client.getId(), msg = msg,
      contentTopic = msg.contentTopic

  let envelope = decode(msg.bytes, WapEnvelopeV1).valueOr:
    raise newException(ValueError, "Failed to decode WapEnvelopeV1: " & error)

  let wrappedConvo = block:
    let opt = client.getConversationFromHint(envelope.conversationHint).valueOr:
      raise newException(ValueError, "Failed to get conversation: " & error)

    if opt.isSome():
      opt.get()
    else:
      let k = toSeq(client.conversations.keys()).join(", ")
      warn "No conversation found", client = client.getId(),
        hint = envelope.conversationHint, knownIds = k
      return

  case wrappedConvo.convoType:
    of InboxV1Type:
      client.handleInboxFrame(wrappedConvo.inboxV1, envelope.payload)

    of PrivateV1Type:
      client.handlePrivateFrame(wrappedConvo.privateV1, envelope.payload)

proc addMessage*(client: Client, convo: PrivateV1,
    text: string = "") {.async.} =
  ## Test Function to send automatic messages. to be removed.
  let message = PrivateV1Frame(content: ContentFrame(domain: 0, tag: 1,
      bytes: text.toBytes()))

  await convo.sendMessage(client.ds, message)


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


proc simulateMessages(client: Client){.async.} =
  ## Test Task to generate messages after initialization. To be removed.

  # TODO: FutureBug - This should wait for a privateV1 conversation.
  while client.conversations.len() <= 1:
    await sleepAsync(4.seconds)

  notice "Starting Message Simulation", client = client.getId()
  for a in 1..5:
    await sleepAsync(4.seconds)

    for convoWrapper in client.conversations.values():
      if convoWrapper.convoType == PrivateV1Type:
        await client.addMessage(convoWrapper.privateV1, fmt"message: {a}")

#################################################
# Control Functions
#################################################

proc start*(client: Client) {.async.} =
  ## Start `Client` and listens for incoming messages.
  client.ds.addDispatchQueue(client.inboundQueue)
  asyncSpawn client.ds.start()

  client.isRunning = true

  asyncSpawn client.messageQueueConsumer()
  asyncSpawn client.simulateMessages()

  notice "Client start complete"

proc stop*(client: Client) =
  ## Stop the client.
  client.isRunning = false
  notice "Client stopped"
