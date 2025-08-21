import strformat

type
  ConvoTypes* = enum
    InboxV1Type, PrivateV1Type

type
  Conversation* = ref object of RootObj
    name: string

proc `$`(conv: Conversation): string =
  fmt"Convo: {conv.name}"

method id*(self: Conversation): string {.raises: [Defect].} =
  raise newException(Defect, "Abstract function")

