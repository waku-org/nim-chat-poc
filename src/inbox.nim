import
  chronicles,
  chronos,
  results

import
  crypto,
  proto_types,
  utils

type
  Inbox* = object
    inbox_addr: string

proc initInbox*(inbox_addr: string): Inbox =
  ## Initializes an Inbox object with the given address and invite callback.
  return Inbox(inbox_addr: inbox_addr)

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
