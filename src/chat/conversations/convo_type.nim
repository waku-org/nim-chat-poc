import chronos
import strformat
import strutils

import ../proto_types
import ../utils
import ../types

type
  ConvoTypes* = enum
    InboxV1Type, PrivateV1Type

type
  Conversation* = ref object of RootObj
    name: string

proc `$`(conv: Conversation): string =
  fmt"Convo: {conv.name}"

# TODO: Removing the raises clause and the exception raise causes this
# error -->     ...src/chat_sdk/client.nim(166, 9) Error: addConversation(client, convo) can raise an unlisted exception: Exception
# Need better understanding of NIMs Exception model
method id*(self: Conversation): string {.raises: [Defect, ValueError].} =
  # TODO: make this a compile time check
  panic("ProgramError: Missing concrete implementation")

method sendMessage*(convo: Conversation, content_frame: Content) : Future[MessageId] {.async, base, gcsafe.} =
  # TODO: make this a compile time check
  panic("ProgramError: Missing concrete implementation")
