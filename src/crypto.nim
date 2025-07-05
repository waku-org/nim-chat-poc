import proto_types

import secp256k1
import std/[sysrand]
export secp256k1


type KeyPair* = SkKeyPair



proc encrypt_plain*[T: EncryptableTypes](frame: T): EncryptedPayload =
  return EncryptedPayload(
    plaintext: Plaintext(payload: encode(frame)),
  )

proc decrypt_plain*[T: EncryptableTypes](ciphertext: Plaintext, t: typedesc[
    T]): Result[T, string] =

  let obj = decode(ciphertext.payload, T)
  if obj.isErr:
    return err("Protobuf decode failed: " & obj.error)

  result = ok(obj.get())

proc generate_keypair*(): KeyPair =
  var rng: Rng = urandom
  let res = SkKeyPair.random(rng)
  if res.isErr:
    raise newException(ValueError, "Failed to generate keypair: ")

  result = res.get()

