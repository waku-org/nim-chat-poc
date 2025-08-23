

import chronicles
import chronos
import std/[sequtils, strutils, strformat]
import std/algorithm
import sugar

import ../conversation_store
import ../crypto
import ../delivery/waku_client

import ../[
  identity,
  proto_types,
  utils
]
import convo_type



type
  PrivateV1* = ref object of Conversation
    # Placeholder for PrivateV1 conversation type
    owner: Identity
    topic: string
    participants: seq[PublicKey]
    discriminator: string

proc getTopic*(self: PrivateV1): string =
  ## Returns the topic for the PrivateV1 conversation.
  return self.topic


proc getConvoIdRaw(participants: seq[PublicKey],
    discriminator: string): string =
  # This is a placeholder implementation.
  var addrs = participants.map(x => x.get_addr());
  addrs.sort()
  addrs.add(discriminator)
  let raw = addrs.join("|")
  return utils.hash_func(raw)

proc getConvoId*(self: PrivateV1): string =
  return getConvoIdRaw(self.participants, self.discriminator)

proc derive_topic(participants: seq[PublicKey], discriminator: string): string =
  ## Derives a topic from the participants' public keys.
  return "/convo/private/" & getConvoIdRaw(participants, discriminator)

proc encrypt*(convo: PrivateV1, frame: PrivateV1Frame): EncryptedPayload =
  result = EncryptedPayload(plaintext: Plaintext(payload: encode(frame)))

proc decrypt*(convo: PrivateV1, enc: EncryptedPayload): PrivateV1Frame =
  result = decode(enc.plaintext.payload, PrivateV1Frame).get()

proc initPrivateV1*(owner: Identity, participant: PublicKey,
    discriminator: string = "default"): PrivateV1 =

  var participants = @[owner.getPubkey(), participant];

  return PrivateV1(
    owner: owner,
    topic: derive_topic(participants, discriminator),
    participants: participants,
    discriminator: discriminator
  )

proc sendFrame(self: PrivateV1, ds: WakuClient,
    msg: PrivateV1Frame): Future[void]{.async.} =
  let encryptedBytes = EncryptedPayload(plaintext: Plaintext(payload: encode(msg)))

  discard ds.sendPayload(self.getTopic(), encryptedBytes.toEnvelope(
      self.getConvoId()))

method id*(self: PrivateV1): string =
  return getConvoIdRaw(self.participants, self.discriminator)

proc handleFrame*[T: ConversationStore](convo: PrivateV1, client: T,
    bytes: seq[byte]) =
  ## Dispatcher for Incoming `PrivateV1Frames`.
  ## Calls further processing depending on the kind of frame.

  let enc = decode(bytes, EncryptedPayload).get()       # TODO: handle result
  let frame = convo.decrypt(enc) # TODO: handle result

  if frame.sender == @(convo.owner.getPubkey().bytes()):
    notice "Self Message", convo = convo.id()
    return

  case frame.getKind():
  of typeContentFrame:
    # TODO: Using client.getId() results in an error in this context
    client.notifyNewMessage(convo, toUtfString(frame.content.bytes))

  of typePlaceholder:
    notice "Got Placeholder", text = frame.placeholder.counter


method sendMessage*(convo: PrivateV1, ds: WakuClient, text: string) {.async.} =

  try:
    let frame = PrivateV1Frame(sender: @(convo.owner.getPubkey().bytes()),
        content: ContentFrame(domain: 0, tag: 1, bytes: text.toBytes()))

    await convo.sendFrame(ds, frame)
  except Exception as e:
    error "Unknown error in PrivateV1:SendMessage"

