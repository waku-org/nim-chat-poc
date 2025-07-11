import crypto
import proto_types
import utils
import dev

import chronicles


type InviteCallback* = proc(invite: InvitePrivateV1): void


type
  Inbox* = object
    inbox_addr: string
    invite_callback: InviteCallback

proc initInbox*(inbox_addr: string, invite_callback: InviteCallback): Inbox =
  ## Initializes an Inbox object with the given address and invite callback.
  return Inbox(inbox_addr: inbox_addr, invite_callback: invite_callback)


proc encrypt*(frame: InboxV1Frame): EncryptedPayload =
  return encrypt_plain(frame)

proc wrap_env*(payload: EncryptedPayload, convo_id: string): WapEnvelopeV1 =
  let bytes = encode(payload)
  let salt = generateSalt()

  return WapEnvelopeV1(
    payload: bytes,
    salt: salt,
    conversation_hint: convo_id,
  )

proc conversation_id_for*(pubkey: SkPublicKey): string =
  ## Generates a conversation ID based on the public key.
  return "/convo/inbox/v1" & pubkey.get_addr()

# TODO derive this from instance of Inbox
proc topic_inbox*(client_addr: string): string =
  return "/inbox/" & client_addr


proc handle_incomming_frame*(self: Inbox, topic: string, bytes: seq[
    byte]): Result[int, string] =
  # TODO: Can this fail?
  let res = decode(bytes, EncryptedPayload)
  if res.isErr:
    return err("Failed to decode payload: " & res.error)

  let encbytes = res.get()

  # NOTE! in nim_protobuf_serializaiton OneOf fields are not exclusive, and all fields are default initialized.
  if encbytes.plaintext == Plaintext():
    return err("Incorrect Encryption Type")

  let res_frame = decrypt_plain(encbytes.plaintext, InboxV1Frame)
  if res_frame.isErr:
    return err("Failed to decrypt frame: " & res_frame.error)
  let frame = res_frame.get()

  self.invite_callback(frame.invite_private_v1)
  ok(0)


