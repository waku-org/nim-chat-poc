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
  Client* = ref object
    ident: Identity
    key_store: Table[string, KeyEntry]         # Keyed by HexEncoded Public Key
    conversations: Table[string, ConvoWrapper] # Keyed by conversation ID


proc process_invite*(self: var Client, invite: InvitePrivateV1)


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


proc getConversations*(self: Client): Table[string, ConvoWrapper] =
  ## Returns the conversations table for the client.
  result = self.conversations

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

proc createPrivateConversation*(self: var Client, participant: PublicKey,
    discriminator: string = "default") =
  ## Creates a private conversation with the given participant and discriminator.
  let convo = initPrivateV1(self.ident, participant, discriminator)

  info "Creating PrivateV1 conversation", topic = convo.get_topic
  self.conversations[convo.get_topic()] = ConvoWrapper(
    convo_type: PrivateV1Type,
    privateV1: convo
  )


proc handleIntro*(self: var Client, intro_bundle: IntroBundle): TransportMessage =
  ## Creates a private conversation with the given Invitebundle.



  let res_pubkey = SkPublicKey.fromRaw(intro_bundle.ident)
  if res_pubkey.isErr:
    raise newException(ValueError, "Invalid public key in intro bundle.")
  let dest_pubkey = res_pubkey.get()
  let convo_id = "/convo/inbox/" & dest_pubkey.getAddr()

  let dst_convo_topic = topic_inbox(dest_pubkey.get_addr())

  let invite = InvitePrivateV1(
    initiator: @(self.ident.getPubkey().toRawCompressed()),
    initiator_ephemeral: @[0, 0], # TODO: Add ephemeral
    participant: @(dest_pubkey.toRawCompressed()),
    participant_ephemeral_id: intro_bundle.ephemeral_id,
    discriminator: "test"
  )
  let env = wrap_env(encrypt(InboxV1Frame(invite_private_v1: invite,
      recipient: "")), convo_id)

  createPrivateConversation(self, dest_pubkey)

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
  let res_env = decode(transport_message.payload, WapEnvelopeV1)
  if res_env.isErr:
    raise newException(ValueError, "Failed to decode WapEnvelopeV1: " & res_env.error)
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



proc processInvite*(self: var Client, invite: InvitePrivateV1) =
  debug "Callback Invoked", invite = invite

  createPrivateConversation(self, PublicKey.fromRaw(
      invite.initiator).get(),
    invite.discriminator)



