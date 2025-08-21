import proto_types

import crypto/ecdh
import std/[sysrand]
import results

export PublicKey, PrivateKey, bytes, createRandomKey, loadPrivateKeyFromBytes, loadPublicKeyFromBytes,
       getPublicKey, Dh, Result


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

proc generate_key*(): PrivateKey =
  createRandomKey().get()

