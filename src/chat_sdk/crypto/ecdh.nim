import results
import libp2p/crypto/curve25519
import bearssl/rand

type PrivateKey* = object
  bytes: Curve25519Key

type PublicKey* = object
  bytes: Curve25519Key


proc bytes*(key: PrivateKey): Curve25519Key =
  return key.bytes

proc bytes*(key: PublicKey): Curve25519Key =
  return key.bytes

proc createRandomKey*(): Result[PrivateKey, string] =
  let rng = HmacDrbgContext.new()
  if rng.isNil:
    return err("Failed to create HmacDrbgContext with system randomness")
  ok(PrivateKey(bytes: Curve25519Key.random(rng[])))

proc loadPrivateKeyFromBytes*(bytes: openArray[byte]): Result[PrivateKey, string] =
  if bytes.len != Curve25519KeySize:
    return err("Private key size must be 32 bytes")
  ok(PrivateKey(bytes: intoCurve25519Key(bytes)))

proc loadPublicKeyFromBytes*(bytes: openArray[byte]): Result[PublicKey, string] =
  if bytes.len != Curve25519KeySize:
    return err("Public key size must be 32 bytes")
  ok(PublicKey(bytes: intoCurve25519Key(bytes)))


proc getPublicKey*(privateKey: PrivateKey): PublicKey =
  PublicKey(bytes: public(privateKey.bytes))


proc Dh*(privateKey: PrivateKey, publicKey: PublicKey): Result[seq[
    byte], string] =

  var outputKey = publicKey.bytes
  try:
    Curve25519.mul(outputKey, privateKey.bytes)
  except CatchableError as e:
    return err("Failed to compute shared secret: " & e.msg)

  return ok(outputKey.getBytes())
