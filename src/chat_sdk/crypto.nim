import proto_types

import strformat
import crypto/ecdh
import std/[sysrand]
import results
import utils

export PublicKey, PrivateKey, bytes, createRandomKey, loadPrivateKeyFromBytes, loadPublicKeyFromBytes,
       getPublicKey, Dh, Result, get_addr


proc encrypt_plain*[T: EncryptableTypes](frame: T): EncryptedPayload =
  return EncryptedPayload(
    plaintext: Plaintext(payload: proto_types.encode(frame)),
  )

proc decrypt_plain*[T: EncryptableTypes](ciphertext: Plaintext, t: typedesc[
    T]): Result[T, string] =

  let obj = proto_types.decode(ciphertext.payload, T)
  if obj.isErr:
    return err("Protobuf decode failed: " & obj.error)
  result = ok(obj.get())

proc generate_key*(): PrivateKey =
  createRandomKey().get()


proc toHex*(key: PublicKey): string =
  bytesToHex(key.bytes())
  
proc `$`*(key: PublicKey): string =
  let byteStr = toHex(key)
  fmt"{byteStr[0..3]}..{byteStr[^4 .. ^1]}"
