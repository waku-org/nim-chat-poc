import constantine/hashes
import constantine/kdf/kdf_hkdf
import curve25519
import results

import errors
import types


func hkdfExtract*(key: openArray[byte], seed: openArray[byte]) : GenericArray = 

  assert GenericArray.len == sha256.digestSize()

  var ctx{.noInit.}: HKDF[sha256]
  var prk{.noInit.}: array[sha256.digestSize(), byte]
  ctx.hkdfExtract(prk, key, seed)

  return prk



func hkdfExtractExpand*(output: var openArray[byte], salt: openArray[byte], ikm: openArray[byte], info: openArray[byte] ) = 
  var ctx{.noInit.}: HKDF[sha256]
  var prk{.noInit.}: array[sha256.digestSize(), byte]
  ctx.hkdfExtract(prk, salt, ikm)
  ctx.hkdfExpand(output, prk, info, true)


func hkdfSplit*(salt: GenericArray, ikm: GenericArray, info: openArray[byte] ) : (RootKey, ChainKey) = 

  var output : array[KeyLen*2 , byte]

  hkdfExtractExpand(output, salt, ikm, info)

  var out1 : array[KeyLen, byte]
  var out2 : array[KeyLen, byte]

  # Unsafe memcopy
  copyMem(addr output[0],  unsafeAddr out1[0], KeyLen)
  copyMem(addr output[32], unsafeAddr out2[0], KeyLen)

  result = (out1,out2)



func dhExchange*(a: PrivateKey, b: PublicKey): Result[DhDerivedKey, NaxolotlError] =
  var dhOuput = b

  try:
    Curve25519.mul(dhOuput, a)
  except CatchableError as e:
    return err(NaxolotlError( code: errProgram, context: e.msg))
  ok(DhDerivedKey(dhOuput))


