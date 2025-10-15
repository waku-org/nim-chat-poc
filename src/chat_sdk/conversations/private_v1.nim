
import blake2
import chronicles
import chronos
import sds
import std/[sequtils, strutils, strformat]
import std/algorithm
import sugar
import tables

import ../conversation_store
import ../crypto
import ../delivery/waku_client

import ../[
  identity,
  errors,
  proto_types,
  types,
  utils
]
import convo_type
import message

import ../../naxolotl as nax
 

type
  ReceivedPrivateV1Message* = ref object of ReceivedMessage 
    
proc initReceivedMessage(sender: PublicKey, timestamp: int64, content: ContentFrame) : ReceivedPrivateV1Message =
  ReceivedPrivateV1Message(sender:sender, timestamp:timestamp, content:content)


type
  PrivateV1* = ref object of Conversation
    # Placeholder for PrivateV1 conversation type
    sdsClient: ReliabilityManager
    owner: Identity
    topic: string
    participant: PublicKey
    discriminator: string
    doubleratchet: naxolotl.Doubleratchet

proc getTopic*(self: PrivateV1): string =
  ## Returns the topic for the PrivateV1 conversation.
  return self.topic

proc allParticipants(self: PrivateV1): seq[PublicKey] =
  return @[self.owner.getPubkey(), self.participant]

proc getConvoIdRaw(participants: seq[PublicKey],
    discriminator: string): string =
  # This is a placeholder implementation.
  var addrs = participants.map(x => x.get_addr());
  addrs.sort()
  addrs.add(discriminator)
  let raw = addrs.join("|")
  return utils.hash_func(raw)

proc getConvoId*(self: PrivateV1): string =
  return getConvoIdRaw(@[self.owner.getPubkey(), self.participant], self.discriminator)

proc derive_topic(participants: seq[PublicKey], discriminator: string): string =
  ## Derives a topic from the participants' public keys.
  return "/convo/private/" & getConvoIdRaw(participants, discriminator)

proc calcMsgId(self: PrivateV1, msgBytes: seq[byte]): string =
  let s = fmt"{self.getConvoId()}|{msgBytes}"
  result = getBlake2b(s, 16, "")


proc encrypt*(convo: PrivateV1, plaintext: var seq[byte]): EncryptedPayload =

  let (header, ciphertext) = convo.doubleratchet.encrypt(plaintext) #TODO: Associated Data

  result = EncryptedPayload(doubleratchet: proto_types.DoubleRatchet(
    dh: toSeq(header.dhPublic),
    msgNum: header.msgNumber,
    prevChainLen: header.prevChainLen,
    ciphertext: ciphertext)
  )

proc decrypt*(convo: PrivateV1, enc: EncryptedPayload): Result[seq[byte], ChatError]  =
  # Ensure correct type as received
  if enc.doubleratchet.ciphertext == @[]:
    return err(ChatError(code: errTypeError, context: "Expected doubleratchet encrypted payload got ???"))

  let dr = enc.doubleratchet

  var header = DrHeader(
    msgNumber: dr.msgNum,
    prevChainLen: dr.prevChainLen
  )
  copyMem(addr header.dhPublic[0], unsafeAddr dr.dh[0], dr.dh.len) # TODO: Avoid this copy

  convo.doubleratchet.decrypt(header, dr.ciphertext, @[]).mapErr(proc(e: NaxolotlError): ChatError = ChatError(code: errWrapped, context: repr(e) ))



proc wireCallbacks(convo: PrivateV1, deliveryAckCb: proc(
        conversation: Conversation,
      msgId: string): Future[void] {.async.} = nil) =
  ## Accepts lambdas/functions to be called from Reliability Manager callbacks.
  let funcMsg = proc(messageId: SdsMessageID,
      channelId: SdsChannelID) {.gcsafe.} =
    debug "sds message ready", messageId = messageId,
        channelId = channelId

  let funcDeliveryAck = proc(messageId: SdsMessageID,
      channelId: SdsChannelID) {.gcsafe.} =
    debug "sds message ack", messageId = messageId,
        channelId = channelId, cb = repr(deliveryAckCb)

    if deliveryAckCb != nil:
      asyncSpawn deliveryAckCb(convo, messageId)

  let funcDroppedMsg = proc(messageId: SdsMessageID, missingDeps: seq[
      SdsMessageID], channelId: SdsChannelID) {.gcsafe.} =
    debug "sds message missing", messageId = messageId,
        missingDeps = missingDeps, channelId = channelId

  convo.sdsClient.setCallbacks(
    funcMsg, funcDeliveryAck, funcDroppedMsg
  )



proc initPrivateV1*(owner: Identity, participant: PublicKey, seedKey: array[32, byte],
        discriminator: string = "default", isSender: bool, deliveryAckCb: proc(
        conversation: Conversation,
      msgId: string): Future[void] {.async.} = nil):
          PrivateV1 =

  var participants = @[owner.getPubkey(), participant];

  var rm = newReliabilityManager().valueOr:
    raise newException(ValueError, fmt"sds initialization: {repr(error)}")

  result = PrivateV1(
    sdsClient: rm,
    owner: owner,
    topic: derive_topic(participants, discriminator),
    participant: participant,
    discriminator: discriminator,
    doubleratchet: initDoubleratchet(seedKey, owner.privateKey.bytes, participant.bytes, isSender)
  )

  result.wireCallbacks(deliveryAckCb)

  result.sdsClient.ensureChannel(result.getConvoId()).isOkOr:
    raise newException(ValueError, "bad sds channel")


proc initPrivateV1Sender*(owner:Identity, participant: PublicKey, seedKey: array[32, byte], deliveryAckCb: proc(
        conversation: Conversation, msgId: string): Future[void] {.async.} = nil): PrivateV1 =
        initPrivateV1(owner, participant, seedKey, "default", true, deliveryAckCb)

proc initPrivateV1Recipient*(owner:Identity, participant: PublicKey, seedKey: array[32, byte], deliveryAckCb: proc(
        conversation: Conversation, msgId: string): Future[void] {.async.} = nil): PrivateV1 =
        initPrivateV1(owner, participant, seedKey, "default", false, deliveryAckCb)


proc sendFrame(self: PrivateV1, ds: WakuClient,
    msg: PrivateV1Frame):  Future[MessageId]{.async.} =

  let frameBytes = encode(msg)
  let msgId = self.calcMsgId(frameBytes)
  var sdsPayload = self.sdsClient.wrapOutgoingMessage(frameBytes, msgId,
      self.getConvoId()).valueOr:
    raise newException(ValueError, fmt"sds wrapOutgoingMessage failed: {repr(error)}")

  let encryptedPayload = self.encrypt(sdsPayload)

  discard ds.sendPayload(self.getTopic(), encryptedPayload.toEnvelope(
      self.getConvoId()))

  result = msgId
  

method id*(self: PrivateV1): string =
  return getConvoIdRaw(self.allParticipants(), self.discriminator)

proc handleFrame*[T: ConversationStore](convo: PrivateV1, client: T,
    bytes: seq[byte]) =
  ## Dispatcher for Incoming `PrivateV1Frames`.
  ## Calls further processing depending on the kind of frame.

  let enc = decode(bytes, EncryptedPayload).valueOr:
    raise newException(ValueError, fmt"Failed to decode EncryptedPayload: {repr(error)}")

  let plaintext = convo.decrypt(enc).valueOr:
    error "decryption failed", error = error
    return

  let (frameData, missingDeps, channelId) = convo.sdsClient.unwrapReceivedMessage(
      plaintext).valueOr:
    raise newException(ValueError, fmt"Failed to unwrap SDS message:{repr(error)}")

  debug "sds unwrap", convo = convo.id(), missingDeps = missingDeps,
      channelId = channelId

  let frame = decode(frameData, PrivateV1Frame).valueOr:
    raise newException(ValueError, "Failed to decode SdsM: " & error)

  if frame.sender == @(convo.owner.getPubkey().bytes()):
    notice "Self Message", convo = convo.id()
    return

  case frame.getKind():
  of typeContentFrame:
    # TODO: Using client.getId() results in an error in this context
    client.notifyNewMessage(convo, initReceivedMessage(convo.participant, frame.timestamp, frame.content))
    
  of typePlaceholder:
    notice "Got Placeholder", text = frame.placeholder.counter


method sendMessage*(convo: PrivateV1, ds: WakuClient,
    content_frame: ContentFrame) : Future[MessageId] {.async.} =

  try:
    let frame = PrivateV1Frame(sender: @(convo.owner.getPubkey().bytes()),
        timestamp: getCurrentTimestamp(), content: content_frame)

    result = await convo.sendFrame(ds, frame)
  except Exception as e:
    error "Unknown error in PrivateV1:SendMessage"

