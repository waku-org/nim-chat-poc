import ../identity
import ../crypto
import ../utils

import std/[sequtils, strutils]
import std/algorithm
import blake2
import sugar

type
  PrivateV1* = object
    # Placeholder for PrivateV1 conversation type
    owner: Identity
    topic: string
    participants: seq[PublicKey]
    discriminator: string

proc get_topic*(self: PrivateV1): string =
  ## Returns the topic for the PrivateV1 conversation.
  return self.topic

proc derive_topic(participants: seq[PublicKey], discriminator: string): string =
  ## Derives a topic from the participants' public keys.
  # This is a placeholder implementation.
  var addrs = participants.map(x => x.get_addr());
  addrs.sort()
  addrs.add(discriminator)
  let raw = addrs.join("|")

  return "/convo/private/" & getBlake2b(raw, 18, "")




proc initPrivateV1*(owner: Identity, participant: PublicKey,
    discriminator: string = "default"): PrivateV1 =

  var participants = @[owner.getPubkey(), participant];

  return PrivateV1(
    owner: owner,
    topic: derive_topic(participants, discriminator),
    participants: participants,
    discriminator: discriminator
  )


