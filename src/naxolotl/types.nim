import curve25519

type PrivateKey* = Curve25519Key
type PublicKey* = Curve25519Key

type RootKey* =  array[32, byte]
type ChainKey* =  array[32, byte]
type MessageKey* =  array[32, byte]
type DhDerivedKey* = array[32, byte]

type GenericArray* = array[32, byte]

type CipherText* = seq[byte]

type MsgCount* = uint32
type KeyId* = (PublicKey, MsgCount)

const KeyLen* = 32