import ../crypto
import ../proto_types

# How to surface different verifability of properties across conversation types 


type ReceivedMessage* = ref object of RootObj
  sender*: PublicKey
  timestamp*: int64
  content*: ContentFrame


