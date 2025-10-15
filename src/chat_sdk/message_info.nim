import crypto

type
  VerifabilityProp* = enum
    Verified, Unverified

type Property*[T] = object
  value*: T
  verifiability*: VerifabilityProp

type MessageInfo* = object
  sender*: Property[PublicKey]
  timestamp*: Property[uint64]