

import chronicles
import chronos
import std/[sequtils, strutils]
import std/algorithm
import sugar

import ../[
  crypto,
  identity,
  proto_types,
  utils,
  waku_client
]

type
  PrivateV1* = object
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

proc sendMessage*(self: PrivateV1, ds: WakuClient,
    msg: PrivateV1Frame): Future[void]{.async.} =
  notice "SENDING MSG", fromm = self.owner.getId(),
      participants = self.participants, msg = msg

  let encryptedBytes = EncryptedPayload(plaintext: Plaintext(payload: encode(msg)))

  discard ds.sendPayload(self.getTopic(), encryptedBytes.toEnvelope(
      self.getConvoId()))
