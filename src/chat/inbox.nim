import std/[strutils]

import
  chronicles,
  chronos,
  results,
  strformat

import
  conversations/convo_type,
  conversations,
  conversation_store,
  crypto,
  delivery/waku_client,
  errors,
  identity,
  proto_types,
  types,
  utils

logScope:
  topics = "chat inbox"

type
  Inbox* = ref object of Conversation
    identity: Identity
    inbox_addr: string

const
  TopicPrefixInbox = "/inbox/"

proc `$`*(conv: Inbox): string =
  fmt"Inbox: addr->{conv.inbox_addr}"


proc initInbox*(ident: Identity): Inbox =
  ## Initializes an Inbox object with the given address and invite callback.
  return Inbox(identity: ident)

proc encrypt*(frame: InboxV1Frame): EncryptedPayload =
  return encrypt_plain(frame)

proc decrypt*(inbox: Inbox, encbytes: EncryptedPayload): Result[InboxV1Frame, string] =
  let res_frame = decrypt_plain(encbytes.plaintext, InboxV1Frame)
  if res_frame.isErr:
    error "Failed to decrypt frame: ", err = res_frame.error
    return err("Failed to decrypt frame: " & res_frame.error)
  result = res_frame

proc wrap_env*(payload: EncryptedPayload, convo_id: string): WapEnvelopeV1 =
  let bytes = encode(payload)
  let salt = generateSalt()

  return WapEnvelopeV1(
    payload: bytes,
    salt: salt,
    conversation_hint: convo_id,
  )

proc conversation_id_for*(pubkey: PublicKey): string =
  ## Generates a conversation ID based on the public key.
  return "/convo/inbox/v1/" & pubkey.get_addr()

# TODO derive this from instance of Inbox
proc topic_inbox*(client_addr: string): string =
  return TopicPrefixInbox & client_addr

proc parseTopic*(topic: string): Result[string, ChatError] =
  if not topic.startsWith(TopicPrefixInbox):
    return err(ChatError(code: errTopic, context: "Invalid inbox topic prefix"))
  
  let id = topic.split('/')[^1]
  if id == "":
    return err(ChatError(code: errTopic, context: "Empty inbox id"))
  
  return ok(id)

method id*(convo: Inbox): string =
  return conversation_id_for(convo.identity.getPubkey())

## Encrypt and Send a frame to the remote account
proc sendFrame(ds: WakuClient, remote: PublicKey, frame: InboxV1Frame ): Future[void] {.async.} =
    let env = wrapEnv(encrypt(frame),conversation_id_for(remote) )
    await ds.sendPayload(topic_inbox(remote.get_addr()), env)


proc newPrivateInvite(initator_static: PublicKey, 
                      initator_ephemeral: PublicKey, 
                      recipient_static: PublicKey, 
                      recipient_ephemeral: uint32, 
                      payload: EncryptedPayload) : InboxV1Frame =

  let invite = InvitePrivateV1(
    initiator: @(initator_static.bytes()),
    initiatorEphemeral: @(initator_ephemeral.bytes()),
    participant: @(recipient_static.bytes()),
    participantEphemeralId: 0,
    discriminator: "",
    initial_message: payload
  )
  result = InboxV1Frame(invitePrivateV1: invite, recipient: "")

#################################################
# Conversation Creation
#################################################

## Establish a PrivateConversation with a remote client
proc inviteToPrivateConversation*(self: Inbox, ds: Wakuclient, remote_static: PublicKey, remote_ephemeral: PublicKey, content: Content ) : Future[PrivateV1] {.async.} =
  # Create SeedKey
  # TODO: Update key derivations when noise is integrated
  var local_ephemeral = generateKey()
  var sk{.noInit.} : array[32, byte] = default(array[32, byte])

  # Initialize PrivateConversation
  let (convo, encPayload) = initPrivateV1Sender(self.identity, ds, remote_static, sk, content, nil)
  result = convo

  # # Build Invite
  let frame = newPrivateInvite(self.identity.getPubkey(), local_ephemeral.getPublicKey(), remote_static, 0, encPayload)
  
  # Send
  await sendFrame(ds, remote_static, frame)

## Receive am Invitation to create a new private conversation
proc createPrivateV1FromInvite*[T: ConversationStore](client: T,
    invite: InvitePrivateV1) =

  let destPubkey = loadPublicKeyFromBytes(invite.initiator).valueOr:
    raise newException(ValueError, "Invalid public key in intro bundle.")

  let deliveryAckCb = proc(
        conversation: Conversation,
      msgId: string): Future[void] {.async.} =
    client.notifyDeliveryAck(conversation, msgId)

  # TODO: remove placeholder key
  var key : array[32, byte] = default(array[32,byte])

  let convo = initPrivateV1Recipient(client.identity(), client.ds, destPubkey, key, deliveryAckCb)
  notice "Creating PrivateV1 conversation", client = client.getId(),
      convoId = convo.getConvoId()
  
  convo.handleFrame(client, invite.initial_message)

  # Calling `addConversation` must only occur after the conversation is completely configured.
  # The client calls the OnNewConversation callback, which returns execution to the application.
  client.addConversation(convo) 

proc handleFrame*[T: ConversationStore](convo: Inbox, client: T, bytes: seq[
    byte]) =
  ## Dispatcher for Incoming `InboxV1Frames`.
  ## Calls further processing depending on the kind of frame.

  let enc = decode(bytes, EncryptedPayload).valueOr:
    raise newException(ValueError, "Failed to decode payload")

  let frame = convo.decrypt(enc).valueOr:
    error "Decrypt failed", client = client.getId(), error = error
    raise newException(ValueError, "Failed to Decrypt MEssage: " &
        error)

  case getKind(frame):
  of typeInvitePrivateV1:
    createPrivateV1FromInvite(client, frame.invitePrivateV1)

  of typeNote:
    notice "Receive Note", client = client.getId(), text = frame.note.text


method sendMessage*(convo: Inbox, content_frame: Content) : Future[MessageId] {.async.} =
  warn "Cannot send message to Inbox"
  result = "program_error"
