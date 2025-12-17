import crypto/ecdh
import results
import sequtils
import std/[endians,sysrand]
import strformat
import types
import utils

import proto_types

export PublicKey, PrivateKey, bytes, createRandomKey, loadPrivateKeyFromBytes, loadPublicKeyFromBytes,
       getPublicKey, Dh, Result, get_addr, `$`


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


proc toHex*(key: PublicKey): string =
  bytesToHex(key.bytes())
  
proc `$`*(key: PublicKey): string =
  let byteStr = toHex(key)
  fmt"{byteStr[0..3]}..{byteStr[^4 .. ^1]}"

proc generateRemoteKeyIdentifier*(publicKey: PublicKey): RemoteKeyIdentifier =
  let bytes = cast[seq[byte]]("WAP") & publicKey.bytes().toSeq()
  let hash = utils.hash_func_bytes(4,bytes)

  var result: uint32
  littleEndian32(addr result, unsafeAddr hash[0])