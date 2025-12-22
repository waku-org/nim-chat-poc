## Utility functions for C-bindings
## Provides C-string helpers and JSON event serialization

import std/json
import ffi

# Re-export common FFI types
export ffi

#################################################
# C-String Helpers
#################################################

proc toCString*(s: string): cstring =
  ## Convert Nim string to C string (caller must manage memory)
  result = s.cstring

proc fromCString*(cs: cstring): string =
  ## Convert C string to Nim string (makes a copy)
  if cs.isNil:
    result = ""
  else:
    result = $cs

proc toBytes*(data: ptr byte, len: csize_t): seq[byte] =
  ## Convert C byte array to Nim seq[byte]
  if data.isNil or len == 0:
    result = @[]
  else:
    result = newSeq[byte](len)
    copyMem(addr result[0], data, len)

#################################################
# JSON Event Types
#################################################

type
  JsonEventType* = enum
    EventNewMessage = "new_message"
    EventNewConversation = "new_conversation"
    EventDeliveryAck = "delivery_ack"
    EventError = "error"

type
  JsonMessageEvent* = object
    eventType*: string
    conversationId*: string
    messageId*: string
    content*: string
    timestamp*: int64

  JsonConversationEvent* = object
    eventType*: string
    conversationId*: string
    conversationType*: string

  JsonDeliveryAckEvent* = object
    eventType*: string
    conversationId*: string
    messageId*: string

  JsonErrorEvent* = object
    eventType*: string
    error*: string

#################################################
# JSON Event Constructors
#################################################

proc newJsonMessageEvent*(convoId, msgId, content: string, timestamp: int64): JsonMessageEvent =
  result = JsonMessageEvent(
    eventType: $EventNewMessage,
    conversationId: convoId,
    messageId: msgId,
    content: content,
    timestamp: timestamp
  )

proc newJsonConversationEvent*(convoId, convoType: string): JsonConversationEvent =
  result = JsonConversationEvent(
    eventType: $EventNewConversation,
    conversationId: convoId,
    conversationType: convoType
  )

proc newJsonDeliveryAckEvent*(convoId, msgId: string): JsonDeliveryAckEvent =
  result = JsonDeliveryAckEvent(
    eventType: $EventDeliveryAck,
    conversationId: convoId,
    messageId: msgId
  )

proc newJsonErrorEvent*(error: string): JsonErrorEvent =
  result = JsonErrorEvent(
    eventType: $EventError,
    error: error
  )

#################################################
# JSON Serialization
#################################################

proc `$`*(event: JsonMessageEvent): string =
  $(%*event)

proc `$`*(event: JsonConversationEvent): string =
  $(%*event)

proc `$`*(event: JsonDeliveryAckEvent): string =
  $(%*event)

proc `$`*(event: JsonErrorEvent): string =
  $(%*event)

