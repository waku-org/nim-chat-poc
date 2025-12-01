import results
import unittest

import ../src/chat/crypto/ecdh # TODO use config.nims
import ../src/chat/utils

# Key share test from RFC-7748:
const ks7748_a_priv = "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a"
const ks7748_a_pub = "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a" # Public key point (x co-ord)

const ks7748_b_priv = "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb"
const ks7748_b_pub = "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f" # Public key point (x co-ord)s

const ks7748_shared_key = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"

import parseutils

proc hexToArray*[N: static[int]](hexStr: string): array[N, byte] =
  ## Converts hex string to fixed-size byte array
  if hexStr.len != N * 2:
    raise newException(ValueError,
      "Hex string length (" & $hexStr.len & ") doesn't match array size (" & $(
          N*2) & ")")

  for i in 0..<N:
    if parseHex(hexStr[i*2..i*2+1], result[i]) == 0:
      raise newException(ValueError, "Invalid hex pair: " & hexStr[i*2..i*2+1])


suite "X25519":
  test "Key Loading":

    let a_priv = loadPrivateKeyFromBytes(hexToArray[32](ks7748_a_priv)).get()
    let a_pub = a_priv.getPublicKey()

    check bytesToHex(a_pub.bytes, lowercase = true) == ks7748_a_pub
    check bytesToHex(a_pub.bytes, lowercase = true) != ks7748_b_pub

    let b_priv = loadPrivateKeyFromBytes(hexToArray[32](ks7748_b_priv)).get()
    let b_pub = b_priv.getPublicKey()

    check bytesToHex(b_pub.bytes, lowercase = true) != ks7748_a_pub
    check bytesToHex(b_pub.bytes, lowercase = true) == ks7748_b_pub

  test "ECDH":

    let a_priv = loadPrivateKeyFromBytes(hexToArray[32](ks7748_a_priv)).get()
    let a_pub = a_priv.getPublicKey()

    let b_priv = loadPrivateKeyFromBytes(hexToArray[32](ks7748_b_priv)).get()
    let b_pub = b_priv.getPublicKey()


    let sk1 = Dh(a_priv, b_pub)
    if sk1.isErr:
      raise newException(ValueError, "ECDH1 failed: " & sk1.error)

    let sk2 = Dh(b_priv, a_pub)
    if sk2.isErr:
      raise newException(ValueError, "ECDH2 failed: " & sk2.error)

    check bytesToHex(sk1.get(), lowercase = true) == ks7748_shared_key
    check bytesToHex(sk2.get(), lowercase = true) == ks7748_shared_key

# Run with: nim c -r test_example.nim
