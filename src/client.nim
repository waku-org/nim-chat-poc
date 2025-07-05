import tables
import identity
import crypto
import proto_types
import std/times
import utils
import dev
import inbox

import conversations/private_v1

import secp256k1
import chronicles

type KeyEntry* = object
  keytype: string
  keypair: SkKeyPair
  timestamp: int64


type SupportedConvoTypes* = Inbox | PrivateV1

type
  ConvoType* = enum
    InboxV1Type, PrivateV1Type

  ConvoWrapper* = object
    case convo_type*: ConvoType
    of InboxV1Type:
      inboxV1*: Inbox
    of PrivateV1Type:
      privateV1*: PrivateV1


type
  Client* = object
    ident: Identity
    key_store: Table[string, KeyEntry]         # Keyed by HexEncoded Public Key
    conversations: Table[string, ConvoWrapper] # Keyed by conversation ID


proc process_invite*(self: Client, invite: InvitePrivateV1)


#################################################
# Constructors
#################################################

proc initClient*(name: string): Client =


  var c = Client(ident: createIdentity(name),
                 key_store: initTable[string, KeyEntry](),
                 conversations: initTable[string, ConvoWrapper]())

  let default_inbox = initInbox(c.ident.getAddr(), proc(
        x: InvitePrivateV1) = c.process_invite(x))

  c.conversations[conversation_id_for(c.ident.getPubkey(
    ))] = ConvoWrapper(convo_type: InboxV1Type, inboxV1: default_inbox)

  result = c


#################################################
# Parameter Access
#################################################

proc getClientAddr*(self: Client): string =
  result = self.ident.getAddr()

proc default_inbox_conversation_id*(self: Client): string =
  ## Returns the default inbox address for the client.
  result = conversation_id_for(self.ident.getPubkey())

#################################################
# Methods
#################################################

# proc addConversation*(c: var Client, convo: Conversation) =
#   if not c.conversations.hasKey(convo.getConvoId()):
#     c.conversations[convo.getConvoId()] = convo
#   else:
#     echo "Conversation with ID ", convo.getConvoId(), " already exists."


proc createIntroBundle*(self: var Client): IntroBundle =
  ## Generates an IntroBundle for the client, which includes
  ## the required information to send a message.

  # Create Ephemeral keypair, save it in the key store
  let ephemeral_keypair = generate_keypair()
  self.key_store[ephemeral_keypair.pubkey.toHexCompressed()] = KeyEntry(
    keytype: "ephemeral",
    keypair: ephemeral_keypair,
    timestamp: getTime().toUnix(),
  )

  result = IntroBundle(
    ident: @(self.ident.getPubkey().toRawCompressed()),
    ephemeral: @(ephemeral_keypair.pubkey.toRawCompressed()),
  )

proc createPrivateConvo*(self: Client, intro_bundle: IntroBundle): TransportMessage =
  ## Creates a private conversation with the given Invitebundle.



  let res_pubkey = SkPublicKey.fromRaw(intro_bundle.ident)
  if res_pubkey.isErr:
    raise newException(ValueError, "Invalid public key in intro bundle.")
  let dest_pubkey = res_pubkey.get()
  let convo_id = "/convo/inbox/" & dest_pubkey.getAddr()

  let dst_convo_topic = topic_inbox(dest_pubkey.get_addr())

  let invite = InvitePrivateV1(
    participants: @[self.ident.getAddr(), dest_pubkey.get_addr()],
  )
  let env = wrap_env(encrypt(InboxV1Frame(invite_private_v1: invite,
      recipient: "")), convo_id)

  # Create a new conversation
  # let convo_id = self.ident.getAddr() & "-" & raya_bundle.ident.toHexCompressed()
  # let new_convo = Conversation(id: convo_id, participants: @[self.ident,
  #     Identity(name: "Raya", keypair: SkKeyPair.fromRawCompressed(
  #     raya_bundle.ident))])

  # Add the conversation to the client's store
  # self.addConversation(new_convo)

  # Return the invite (or any other relevant data)
  # return new_convo

  return sendTo(dst_convo_topic, encode(env))

proc get_conversation(self: Client,
    conversation_hint: string): Result[Option[ConvoWrapper], string] =

  # TODO: Implementing Hinting
  if not self.conversations.hasKey(conversation_hint):
    ok(none(ConvoWrapper))
  else:
    ok(some(self.conversations[conversation_hint]))


proc recv*(self: var Client, transport_message: TransportMessage): seq[
    TransportMessage] =
  ## Reveives a incomming payload, decodes it, and processes it.
  let res_env = decode(transport_message.payload, UmbraEnvelopeV1)
  if res_env.isErr:
    raise newException(ValueError, "Failed to decode UmbraEnvelopeV1: " & res_env.error)
  let env = res_env.get()

  let res_convo = self.get_conversation(env.conversation_hint)
  if res_convo.isErr:
    raise newException(ValueError, "Failed to get conversation: " &
        res_convo.error)

  let convo = res_convo.get()
  if not convo.isSome:
    debug "No conversation found", hint = env.conversation_hint
    return

  let inbox = convo.get().inboxV1

  let res = inbox.handle_incomming_frame(transport_message.topic, env.payload)
  if res.isErr:
    warn "Failed to handle incoming frame: ", error = res.error
  return @[]



proc process_invite*(self: Client, invite: InvitePrivateV1) =
  debug "Callback Invoked", invite = invite
