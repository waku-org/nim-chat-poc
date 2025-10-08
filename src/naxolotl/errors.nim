
type
  NaxolotlError* = object of CatchableError
    code*: ErrorCode
    context*: string
  
  ErrorCode* = enum
    errDecryption
    errMessageAuthentication
    errInvalidInput
    errProgram