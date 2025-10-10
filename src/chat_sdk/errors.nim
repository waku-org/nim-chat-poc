import strformat

type
  ChatError* = object of CatchableError
    code*: ErrorCode
    context*: string
  
  ErrorCode* = enum
    errTypeError
    errWrapped


proc `$`*(x: ChatError): string =
  fmt"ChatError(code={$x.code}, context: {x.context})"
