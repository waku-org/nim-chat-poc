import chronos
import chronicles
import strformat
import tables

import sds

import std/typetraits
import sequtils

logScope:
  topics = "dev"

type A = ref object
  asg: string

proc dir*[T](obj: T) =
  echo "Object of type: ", T
  for name, value in fieldPairs(obj):
    if type(value) is string:
      echo "  ", name, ": ", value
    if type(value) is Table:
      echo "hmmmm"

proc `$`(rm: ReliabilityManager): string =
  result = "RM"



type Msg = object
  id*: string
  shouldDrop: bool
  data*: seq[byte]




proc send(rm: ReliabilityManager, channel: string, id: string, msg: seq[
    byte]): seq[byte] =
  result = rm.wrapOutgoingMessage(msg, id, channel).valueOr:
    raise newException(ValueError, "Bad outgoing message")

proc recv(rm: ReliabilityManager, bytes: seq[byte]) =
  let (unwrapped, missingDeps, channelId) = rm.unwrapReceivedMessage(bytes).valueOr:
    raise newException(ValueError, "Bad unwrap")
  info "RECV", channel = channelId, data = unwrapped, mdeps = missingDeps



proc main() {.async.} =

  var messageSentCount = 0
  let CHANNEL = "CHANNEL"
  let msg = @[byte(1), 2, 3]
  let msgId = "test-msg-1"

  var rm = newReliabilityManager().valueOr:
    raise newException(ValueError, fmt"SDS InitializationError")

  rm.setCallbacks(
      proc(messageId: SdsMessageID, channelId: SdsChannelID) {.gcsafe.} =
    echo "OnMsgReady"
    discard,
      proc(messageId: SdsMessageID, channelId: SdsChannelID) {.gcsafe.} =
    echo "OnMsgSent"
    messageSentCount += 1,
      proc(messageId: SdsMessageID, missingDeps: seq[SdsMessageID],
          channelId: SdsChannelID) {.gcsafe.} =
    echo "OnMissing"
    discard,
  )


  let sourceMsgs = @[Msg(id: "1", shouldDrop: false, data: @[byte(1), 2, 3]),
                Msg(id: "2", shouldDrop: true, data: @[byte(0), 5, 6]),
                Msg(id: "3", shouldDrop: false, data: @[byte(7), 8, 9]),
  ]
  rm.ensureChannel(CHANNEL).isOkOr:
    raise newException(ValueError, "Bad channel")


  let encodedMessage = sourceMsgs.map(proc(m: Msg): seq[byte] =
    rm.wrapOutgoingMessage(m.data, m.id, CHANNEL).valueOr:
      raise newException(ValueError, "Bad outgoing message"))

  var i = 0
  var droppedMessages: seq[seq[byte]] = @[]
  for x in encodedMessage:
    if i mod 2 == 0:
      droppedMessages.add(x)
    inc(i)



  # let droppedMessages = encodedMessage.keepIf(proc(item: seq[
  #     byte]): bool =
  #   items.find(item) mod 2 == 0
  # )
  # let droppedMessages = enumerate(encodedMessage).filter(proc(x: seq[
  #     byte]): bool = x[0] mod 2 == 0)

  for s in droppedMessages:
    info "DROPPED", len = len(s)

  for m in droppedMessages:
    let (unwrapped, missingDeps, channelId) = rm.unwrapReceivedMessage(m).valueOr:
      raise newException(ValueError, "Bad unwrap")

    info "RECV", channel = channelId, data = unwrapped, mdeps = missingDeps


proc messageSequence(){.async.} =
  var messageSentCount = 0
  let CHANNEL = "CHANNEL"


  var raya = newReliabilityManager().valueOr:
    raise newException(ValueError, fmt"SDS InitializationError")

  var saro = newReliabilityManager().valueOr:
    raise newException(ValueError, fmt"SDS InitializationError")

  raya.setCallbacks(
      proc(messageId: SdsMessageID, channelId: SdsChannelID) {.gcsafe.} =
    debug "OnMsgReady", client = "raya", id = messageId
    discard,
      proc(messageId: SdsMessageID, channelId: SdsChannelID) {.gcsafe.} =
    debug "OnMsgSent", client = "raya", id = messageId
    messageSentCount += 1,
      proc(messageId: SdsMessageID, missingDeps: seq[SdsMessageID],
          channelId: SdsChannelID) {.gcsafe.} =
    info "OnMissing", client = "raya", id = messageId
    discard,
  )

  saro.setCallbacks(
      proc(messageId: SdsMessageID, channelId: SdsChannelID) {.gcsafe.} =
    debug "OnMsgReady", client = "saro", id = messageId
    discard,
      proc(messageId: SdsMessageID, channelId: SdsChannelID) {.gcsafe.} =
    debug "OnMsgSent", client = "saro", id = messageId
    messageSentCount += 1,
      proc(messageId: SdsMessageID, missingDeps: seq[SdsMessageID],
          channelId: SdsChannelID) {.gcsafe.} =
    info "OnMissing", client = "saro", id = messageId
    discard,
  )

  raya.ensureChannel(CHANNEL).isOkOr:
    raise newException(ValueError, "Bad channel")

  saro.ensureChannel(CHANNEL).isOkOr:
    raise newException(ValueError, "Bad channel")


  let s1 = saro.send(CHANNEL, "s1", @[byte(1), 1, 1])
  raya.recv(s1)

  let r1 = raya.send(CHANNEL, "r1", @[byte(2), 1, 2])
  saro.recv(r1)

  let r2 = raya.send(CHANNEL, "r2", @[byte(2), 2, 2])
  # saro.recv(r2)

  let r3 = raya.send(CHANNEL, "r3", @[byte(2), 3, 2])
  saro.recv(r3)

  let s2 = saro.send(CHANNEL, "s2", @[byte(1), 2, 1])
  raya.recv(s2)

  let s3 = saro.send(CHANNEL, "s3", @[byte(1), 3, 1])
  raya.recv(s3)


  let r4 = raya.send(CHANNEL, "r4", @[byte(2), 4, 2])
  saro.recv(r4)
  saro.recv(r2)

  let r5 = raya.send(CHANNEL, "r5", @[byte(2), 5, 2])
  saro.recv(r5)

  let r6 = raya.send(CHANNEL, "r6", @[byte(2), 6, 2])
  saro.recv(r6)

  saro.recv(r4)
  saro.recv(r3)

  saro.recv(r4)
when isMainModule:
  waitFor messageSequence()
  echo ">>>"
