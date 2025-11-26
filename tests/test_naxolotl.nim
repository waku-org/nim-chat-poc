
import unittest
import results
import random
import sequtils
import std/md5
import strformat
import strutils

import ../src/naxolotl
import ../src/naxolotl/utils
import ../src/naxolotl/types



# Key share test from RFC-7748:
const ks7748_a_priv = "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a"
const ks7748_a_pub = "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a" # Public key point (x co-ord)

const ks7748_b_priv = "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb"
const ks7748_b_pub = "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f" # Public key point (x co-ord)s

const ks7748_shared_key = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"

# import parseutils

proc hexToArray*[N: static[int]](hexStr: string): array[N, byte] =
  ## Converts hex string to fixed-size byte array
  if hexStr.len != N * 2:
    raise newException(ValueError,
      "Hex string length (" & $hexStr.len & ") doesn't match array size (" & $(
          N*2) & ")")
          
  var result: array[N, byte]
  for i in 0..<N:
    result[i] = byte(parseHexInt(hexStr[2*i .. 2*i+1]))


func loadTestKeys() : (array[32,byte],array[32,byte],array[32,byte],array[32,byte]) =

    let a_priv = hexToArray[32](ks7748_a_priv)
    let a_pub = hexToArray[32](ks7748_a_pub)

    let b_priv = hexToArray[32](ks7748_b_priv)
    let b_pub = hexToArray[32](ks7748_b_pub)

    (a_priv, a_pub, b_priv, b_pub)

func createTestInstances(a: array[32, byte], apub: array[32, byte], b: array[32, byte], bpub: array[32, byte],sk: array[32, byte]) : (Doubleratchet, Doubleratchet) =
    let adr = initDoubleratchet(sk, a, bpub, true)
    let bdr = initDoubleratchet(sk, b, apub, false)
    (adr,bdr)



suite "Doubleratchet":
  test "roundtrip":

    let (a_priv, a_pub, b_priv, b_pub) = loadTestKeys()

    let sk = hexToArray[32](ks7748_shared_key)

    var adr = initDoubleratchet(sk, a_priv, b_pub, true)
    var bdr = initDoubleratchet(sk, b_priv, a_pub, true)

    var msg :seq[byte] = @[1,2,3,4,5,6,7,8,9,10]

    let (header, ciphertext) = adr.encrypt(msg)
    let r = bdr.decrypt(header, ciphertext, @[])

    assert r.isOk()
    assert r.get()  == msg

  test "skipped_msg":

    let (a_priv, a_pub, b_priv, b_pub) = loadTestKeys()

    let sk = hexToArray[32](ks7748_shared_key)
    
    var adr = initDoubleratchet(sk, a_priv, b_pub, true)
    var bdr = initDoubleratchet(sk, b_priv, a_pub, true)

    var msg0 :seq[byte] = @[1,2,3,4,5,6,7,8,9,10]
    var msg1 :seq[byte] = @[6,7,8,9,10,1,2,3,4,5]
    var m :seq[byte] = @[9,10,1,2,3,4,5,6,7,8]
    discard adr.encrypt(msg0)
    discard adr.encrypt(msg1)
    let (header, ciphertext) = adr.encrypt(m)
    let r = bdr.decrypt(header, ciphertext, @[])
    assert r.isOk()
    let recv_msg = r.get()
    assert recv_msg  == m


  test "out of order":

    let (a_priv, a_pub, b_priv, b_pub) = loadTestKeys()

    let sk = hexToArray[32](ks7748_shared_key)
    
    var adr = initDoubleratchet(sk, a_priv, b_pub, true)
    var bdr = initDoubleratchet(sk, b_priv, a_pub, true)

    var msg : seq[ seq[byte]]= @[
      @[1,2,3,4,5,6,7,8,9,10],
      @[43,32,1,2],
      @[212,122,0,21,23,4,5,71,29,84,167,31,0,1,92,211,5,53,65],
      @[122,0,21,23,4,5,71,29,84,167,31,0,1,92,211,5,53,65,212],
      @[14,35,17,22,14,63,34,0,1,217,218,29,51,69,33],
    ]

    var ciphertexts : seq[(DrHeader, seq[byte])] = @[]

    for m in mitems(msg):
      ciphertexts.add(adr.encrypt(m))

    randomize(1233)    # make reproducible
    var indicies = toSeq(0..msg.high)
    shuffle(indicies)

    for i in indicies:
      var m = msg[i]
      var (header, ciphertext) = ciphertexts[i]
      let r = bdr.decrypt(header, ciphertext, @[])
      assert r.isOk()
      assert r.get() == m


  test "tag mismatch":


    let (a_priv, a_pub, b_priv, b_pub) = loadTestKeys()
    let sk = hexToArray[32](ks7748_shared_key)

    var adr = initDoubleratchet(sk, a_priv, b_pub, true)
    var bdr = initDoubleratchet(sk, b_priv, a_pub, true)
    
    var msg :seq[byte] = @[1,2,3,4,5,6,7,8,9,10]
  
    var (header, ciphertext) = adr.encrypt(msg)

    # Modify the tag
    ciphertext[^4] = ciphertext[^4] xor 1

    let r = bdr.decrypt(header, ciphertext, @[])
    assert r.isErr()


  test "decryption failure":
    let (a_priv, a_pub, b_priv, b_pub) = loadTestKeys()
    let sk = hexToArray[32](ks7748_shared_key)

    var adr = initDoubleratchet(sk, a_priv, b_pub, true)
    var bdr = initDoubleratchet(sk, b_priv, a_pub, true)
    
    var msg :seq[byte] = @[1,2,3,4,5,6,7,8,9,10]

    var (header, ciphertext) = adr.encrypt(msg)
    ciphertext[15] = ciphertext[15] xor 1

    let r = bdr.decrypt(header, ciphertext, @[])
    assert r.isErr()

  test "dh_key_updates":

    let (a_priv, a_pub, b_priv, b_pub) = loadTestKeys()

    let sk = hexToArray[32](ks7748_shared_key)
    
    var adr = initDoubleratchet(sk, a_priv, b_pub, true)
    var bdr = initDoubleratchet(sk, b_priv, a_pub, true)

    var last_dh_a : PublicKey
    var last_dh_b : PublicKey


    proc step(src: var DoubleRatchet, dst: var DoubleRatchet, m: var seq[byte], ) : PublicKey = 
      let (header, ciphertext) = src.encrypt(m)
      let r = dst.decrypt(header, ciphertext, @[])
      assert m == r.get()
      return header.dhPublic 

    for i in 0..10:
      var ma = toMD5(fmt"M{i}_a").toSeq()
      var mb = toMD5(fmt"M{i}_b").toSeq()

      let dh_a = step(adr, bdr, ma)
      let dh_b = step(bdr, adr, mb)

      assert dh_a != last_dh_a
      assert dh_b != last_dh_b
      assert dh_a != dh_b

      last_dh_a = dh_a
      last_dh_b = dh_b
