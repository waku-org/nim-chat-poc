## Main Entry point to the ChatSDK.
## Clients are the primary manager of sending and receiving 
## messages, and managing conversations.


import # Foreign
  chronicles,
  chronos,
  json,
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
  keytype: string
  privateKey: PrivateKey
  timestamp: int64


type
  SupportedConvoTypes* = Inbox | PrivateV1

  ConvoType* = enum
    InboxV1Type, PrivateV1Type

  ConvoWrapper* = object
    case convo_type*: ConvoType
    of InboxV1Type:
      inboxV1*: Inbox
    of PrivateV1Type:
      privateV1*: PrivateV1

type Client* = ref object
  ident: Identity
  ds*: WakuClient
  key_store: Table[string, KeyEntry]         # Keyed by HexEncoded Public Key
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
                 key_store: initTable[string, KeyEntry](),
                 conversations: initTable[string, ConvoWrapper](),
                 inboundQueue: q,
                 isRunning: false)

  let default_inbox = initInbox(c.ident.getAddr())
  c.conversations[conversation_id_for(c.ident.getPubkey(
    ))] = ConvoWrapper(convo_type: InboxV1Type, inboxV1: default_inbox)


  notice "Client started", client = c.ident.getId(),
      default_inbox = default_inbox
  result = c

#################################################
# Parameter Access
#################################################

proc getId(client: Client): string =
  result = client.ident.getId()

proc default_inbox_conversation_id*(self: Client): string =
  ## Returns the default inbox address for the client.
  result = conversation_id_for(self.ident.getPubkey())

proc getConversationFromHint(self: Client,
    conversation_hint: string): Result[Option[ConvoWrapper], string] =

  # TODO: Implementing Hinting
  if not self.conversations.hasKey(conversation_hint):
    ok(none(ConvoWrapper))
  else:
    ok(some(self.conversations[conversation_hint]))


#################################################
# Functional
#################################################

proc createIntroBundle*(self: var Client): IntroBundle =
  ## Generates an IntroBundle for the client, which includes
  ## the required information to send a message.

  # Create Ephemeral keypair, save it in the key store
  let ephemeral_key = generate_key()
  self.key_store[ephemeral_key.getPublickey().bytes().bytesToHex()] = KeyEntry(
    keytype: "ephemeral",
    privateKey: ephemeral_key,
    timestamp: getTimestamp()
  )

  result = IntroBundle(
    ident: @(self.ident.getPubkey().bytes()),
    ephemeral: @(ephemeral_key.getPublicKey().bytes()),
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
    convo_type: PrivateV1Type,
    privateV1: convo
  )

  return some(convo.getConvoId())

proc newPrivateConversation*(client: Client,
    intro_bundle: IntroBundle): Future[Option[ChatError]] {.async.} =
  ## Creates a private conversation with the given `IntroBundle`.
  ## `IntroBundles` are provided out-of-band.

  notice "New PRIVATE Convo ", clientId = client.getId(),
      fromm = intro_bundle.ident.mapIt(it.toHex(2)).join("")

  let res_pubkey = loadPublicKeyFromBytes(intro_bundle.ident)
  if res_pubkey.isErr:
    raise newException(ValueError, "Invalid public key in intro bundle.")
  let dest_pubkey = res_pubkey.get()

  let convo_id = conversation_id_for(dest_pubkey)
  let dst_convo_topic = topic_inbox(dest_pubkey.get_addr())

  let invite = InvitePrivateV1(
    initiator: @(client.ident.getPubkey().bytes()),
    initiator_ephemeral: @[0, 0], # TODO: Add ephemeral
    participant: @(dest_pubkey.bytes()),
    participant_ephemeral_id: intro_bundle.ephemeral_id,
    discriminator: "test"
  )
  let env = wrap_env(encrypt(InboxV1Frame(invite_private_v1: invite,
      recipient: "")), convo_id)

  let convo = createPrivateConversation(client, dest_pubkey)
  # TODO: Subscribe to new content topic

  await client.ds.sendPayload(dst_convo_topic, env)
  return none(ChatError)

proc acceptPrivateInvite(client: Client,
    invite: InvitePrivateV1): Option[ChatError] =
  ## Allows Recipients to join the conversation.

  notice "ACCEPT PRIVATE Convo ", clientId = client.getId(),
      fromm = invite.initiator.mapIt(it.toHex(2)).join("")

  let res_pubkey = loadPublicKeyFromBytes(invite.initiator)
  if res_pubkey.isErr:
    raise newException(ValueError, "Invalid public key in intro bundle.")
  let dest_pubkey = res_pubkey.get()

  let convo = createPrivateConversation(client, dest_pubkey)
  # TODO: Subscribe to new content topic

  result = none(ChatError)


#################################################
# Payload Handling
#################################################

proc handleInboxFrame(client: Client, frame: InboxV1Frame) =
  ## Dispatcher for Incoming `InboxV1Frames`.
  ## Calls further processing depending on the kind of frame.
  case getKind(frame):
  of type_InvitePrivateV1:
    notice "Receive PrivateInvite", client = client.getId(),
        frame = frame.invite_private_v1
    discard client.acceptPrivateInvite(frame.invite_private_v1)

  of type_Note:
    notice "Receive Note", text = frame.note.text

# TODO: These handle function need symmetry, currently have different signatures
proc handlePrivateFrame(client: Client, convo: PrivateV1, bytes: seq[byte]) =
  ## Dispatcher for Incoming `PrivateV1Frames`.
  ## Calls further processing depending on the kind of frame.
  let enc = decode(bytes, EncryptedPayload).get()       # TODO: handle result
  let frame = convo.decrypt(enc) # TODO: handle result

  case frame.getKind():
  of type_ContentFrame:
    notice "Got Mail", client = client.getId(),
        text = frame.content.bytes.toUtfString()
  of type_Placeholder:
    notice "Got Placeholder", client = client.getId(),
        text = frame.placeholder.counter

proc parseMessage(client: Client, msg: ChatPayload) =
  ## Receives a incoming payload, decodes it, and processes it.
  info "Parse", clientId = client.getId(), msg = msg,
      contentTopic = msg.contentTopic

  let res_env = decode(msg.bytes, WapEnvelopeV1)
  if res_env.isErr:
    raise newException(ValueError, "Failed to decode WapEnvelopeV1: " & res_env.error)
  let env = res_env.get()

  let res_convo = client.getConversationFromHint(env.conversation_hint)
  if res_convo.isErr:
    raise newException(ValueError, "Failed to get conversation: " &
        res_convo.error)

  let resWrappedConvo = res_convo.get()
  if not resWrappedConvo.isSome:
    let k = toSeq(client.conversations.keys()).join(", ")
    warn "No conversation found", client = client.getId(),
        hint = env.conversation_hint, knownIds = k
    return

  let wrappedConvo = resWrappedConvo.get()

  case wrappedConvo.convo_type:
    of InboxV1Type:
      let enc = decode(env.payload, EncryptedPayload).get() # TODO: handle result
      let resFrame = inbox.decrypt(enc) # TODO: handle result
      if resFrame.isErr:
        error "Decrypt failed", error = resFrame.error()
        raise newException(ValueError, "Failed to Decrypt MEssage: " &
            resFrame.error)

      client.handleInboxFrame(resFrame.get())

    of PrivateV1Type:
      client.handlePrivateFrame(wrapped_convo.private_v1, env.payload)

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
    await sleepAsync(4000)

  notice "Starting Message Simulation", client = client.getId()
  for a in 1..5:
    await sleepAsync(4000)

    for convoWrapper in client.conversations.values():
      if convoWrapper.convo_type == PrivateV1Type:
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
