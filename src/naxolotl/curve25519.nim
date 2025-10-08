# See https://github.com/vacp2p/nim-libp2p/blob/master/libp2p/crypto/curve25519.nim

import bearssl/[ec, rand]
import results
from stew/assign2 import assign
export results

const Curve25519KeySize* = 32

type
  Curve25519* = object
  Curve25519Key* = array[Curve25519KeySize, byte]
  Curve25519Error* = enum
    Curver25519GenError

proc intoCurve25519Key*(s: openArray[byte]): Curve25519Key =
  assert s.len == Curve25519KeySize
  assign(result, s)

proc getBytes*(key: Curve25519Key): seq[byte] =
  @key

proc byteswap(buf: var Curve25519Key) {.inline.} =
  for i in 0 ..< 16:
    let x = buf[i]
    buf[i] = buf[31 - i]
    buf[31 - i] = x

proc mul*(_: type[Curve25519], point: var Curve25519Key, multiplier: Curve25519Key) =
  let defaultBrEc = ecGetDefault()

  # multiplier needs to be big-endian
  var multiplierBs = multiplier
  multiplierBs.byteswap()
  let res = defaultBrEc.mul(
    addr point[0],
    Curve25519KeySize,
    addr multiplierBs[0],
    Curve25519KeySize,
    EC_curve25519,
  )
  assert res == 1

proc mulgen(_: type[Curve25519], dst: var Curve25519Key, point: Curve25519Key) =
  let defaultBrEc = ecGetDefault()

  var rpoint = point
  rpoint.byteswap()

  let size =
    defaultBrEc.mulgen(addr dst[0], addr rpoint[0], Curve25519KeySize, EC_curve25519)

  assert size == Curve25519KeySize

proc public*(private: Curve25519Key): Curve25519Key =
  Curve25519.mulgen(result, private)

proc random*(_: type[Curve25519Key], rng: var HmacDrbgContext): Curve25519Key =
  var res: Curve25519Key
  let defaultBrEc = ecGetDefault()
  let len = ecKeygen(
    PrngClassPointerConst(addr rng.vtable), defaultBrEc, nil, addr res[0], EC_curve25519
  )
  # Per bearssl documentation, the keygen only fails if the curve is
  # unrecognised -
  doAssert len == Curve25519KeySize, "Could not generate curve"

  res

const FieldElementSize* = Curve25519KeySize

type FieldElement* = Curve25519Key

# Convert bytes to FieldElement
proc bytesToFieldElement*(bytes: openArray[byte]): Result[FieldElement, string] =
  if bytes.len != FieldElementSize:
    return err("Field element size must be 32 bytes")
  ok(intoCurve25519Key(bytes))

# Convert FieldElement to bytes
proc fieldElementToBytes*(fe: FieldElement): seq[byte] =
  fe.getBytes()

# Generate a random FieldElement
proc generateRandomFieldElement*(): Result[FieldElement, string] =
  let rng = HmacDrbgContext.new()
  if rng.isNil:
    return err("Failed to creat HmacDrbgContext with system randomness")
  ok(Curve25519Key.random(rng[]))

# Generate a key pair (private key and public key are both FieldElements)
proc generateKeyPair*(): Result[tuple[privateKey, publicKey: FieldElement], string] =
  let privateKeyRes = generateRandomFieldElement()
  if privateKeyRes.isErr:
    return err(privateKeyRes.error)
  let privateKey = privateKeyRes.get()

  let publicKey = public(privateKey)
  ok((privateKey, publicKey))

# # Multiply a given Curve25519 point with a set of scalars
# proc multiplyPointWithScalars*(
#     point: FieldElement, scalars: openArray[FieldElement]
# ): FieldElement =
#   var res = point
#   for scalar in scalars:
#     Curve25519.mul(res, scalar)
#   res

# # Multiply the Curve25519 base point with a set of scalars
# proc multiplyBasePointWithScalars*(
#     scalars: openArray[FieldElement]
# ): Result[FieldElement, string] =
#   if scalars.len <= 0:
#     return err("Atleast one scalar must be provided")
#   var res: FieldElement = public(scalars[0]) # Use the predefined base point
#   for i in 1 ..< scalars.len:
#     Curve25519.mul(res, scalars[i]) # Multiply with each scalar
#   ok(res)

# # Compare two FieldElements
# proc compareFieldElements*(a, b: FieldElement): bool =
#   a == b
