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
  proto_types,
  utils

logScope:
  topics = "chat inbox"

type
  Inbox* = ref object of Conversation
    pubkey: PublicKey
    inbox_addr: string


proc `$`*(conv: Inbox): string =
  fmt"Inbox: addr->{conv.inbox_addr}"


proc initInbox*(pubkey: PublicKey): Inbox =
  ## Initializes an Inbox object with the given address and invite callback.
  return Inbox(pubkey: pubkey)

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
  return "/inbox/" & client_addr

method id*(convo: Inbox): string =
  return conversation_id_for(convo.pubkey)


#################################################
# Conversation Creation
#################################################

proc createPrivateV1FromInvite*[T: ConversationStore](client: T,
    invite: InvitePrivateV1) =

  let destPubkey = loadPublicKeyFromBytes(invite.initiator).valueOr:
    raise newException(ValueError, "Invalid public key in intro bundle.")

  let deliveryAckCb = proc(
        conversation: Conversation,
      msgId: string): Future[void] {.async.} =
    client.notifyReadReceipt(conversation, msgId)

  let convo = initPrivateV1(client.identity(), destPubkey, "default", deliveryAckCb)
  notice "Creating PrivateV1 conversation", client = client.getId(),
      topic = convo.getConvoId()
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


method sendMessage*(convo: Inbox, ds: WakuClient,
    content_frame: ContentFrame) {.async.} =
  warn "Cannot send message to Inbox"
