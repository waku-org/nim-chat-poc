import ../crypto

# How to surface different verifability of properties across conversation types 


type ReceivedMessage* = ref object of RootObj
  sender*: PublicKey
  timestamp*: int64
  content*: seq[byte]


