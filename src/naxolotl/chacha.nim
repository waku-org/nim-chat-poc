import nim_chacha20_poly1305/[common, chacha20_poly1305, streaming, helpers, poly1305]
import std/[sysrand]
import results
import strformat
import chronicles

import types
import errors


proc encryptWithChaCha20Poly1305*(msgKey: MessageKey, plaintext: var openArray[byte], associatedData: openArray[byte]) : (Nonce, CipherText) = 

  var nonce : Nonce
  discard urandom(nonce)

  var tag: Tag
  var ciphertext = newSeq[byte](plaintext.len + tag.len)

  var counter : Counter = 0

  # TODO: check plaintext mutability requirement
  chacha20_aead_poly1305_encrypt(
    Key(msgKey), 
    nonce,
    counter,
    associatedData, 
    plaintext,
    ciphertext.toOpenArray(0, plaintext.high),
    tag
  )
  
  # Combine tag with cipherkey for ease of transport and consistency with other implementations
  copyMem(addr ciphertext[plaintext.len], unsafeAddr tag[0], tag.len)
  (nonce, ciphertext)
  

proc decryptWithChaCha20Poly1305*(msgKey: MessageKey, nonce: Nonce, ciphertext: var openArray[byte], associatedData: openArray[byte]) : Result[seq[byte], NaxolotlError] = 
  var tag : Tag
  if ciphertext.len <= tag.len:
    return err(NaxolotlError(code: errInvalidInput, context: fmt"ciphertext is less than {tag.len} bytes. Expected `ciphertext || tag`" ))
  
  copyMem(addr tag[0], unsafeAddr ciphertext[^tag.len], tag.len)

  var plaintext = newSeq[byte](ciphertext.len - tag.len)

  var computedTag: Tag
  var counter : Counter = 0

  chacha20_aead_poly1305_decrypt(
    Key(msgKey), 
    nonce,
    counter,
    associatedData, 
    plaintext,
    ciphertext.toOpenArray(0,ciphertext.high - tag.len),
    computedTag
  )

  if not poly1305_verify(tag, computedTag):
    return err(NaxolotlError(code: errMessageAuthentication, context: fmt"Got Tag: {tag} expected: {computedTag}"))


  ok(plaintext)
  