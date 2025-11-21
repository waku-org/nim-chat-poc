import curve25519
import results
import chronicles
import nim_chacha20_poly1305/[common,helpers]
import strformat
import strutils
import sequtils
import tables

import chacha
import types
import utils
import errors

const maxSkip = 10


type Doubleratchet* = object
  dhSelf*: PrivateKey
  dhRemote*: PublicKey

  rootKey: RootKey
  chainKeySend: ChainKey
  chainKeyRecv: ChainKey

  msgCountSend: MsgCount
  msgCountRecv: MsgCount
  prevChainLen: MsgCount

  # TODO: SkippedKeys
  skippedMessageKeys: Table[(PublicKey,MsgCount), MessageKey]

const DomainSepKdfRoot = "DoubleRatchet"
const DomainSepKdfMsg = "MessageKey"
const DomainSepKdfChain = "ChainKey"



type DrHeader* = object
  dhPublic*: PublicKey
  msgNumber*: uint32
  prevChainLen*: uint32



func keyId(dh:PublicKey, recvCount: MsgCount ): KeyId = 
  (dh, recvCount)

func hex(a: openArray[byte]) : string =
  a.mapIt(&"{it:02X}").join("")

proc `$`*(x: DrHeader): string =
  "DrHeader(pubKey=" & hex(x.dhPublic) & ", msgNum=" & $x.msgNumber & ", msgNum=" & $x.prevChainLen & ")"


#################################################
# Kdf
#################################################


func kdfRoot(self: var Doubleratchet, rootKey: RootKey, dhOutput:DhDerivedKey): (RootKey, ChainKey) =

  var salt = rootKey
  var ikm = dhOutput
  let info = cast[seq[byte]](DomainSepKdfRoot)

  hkdfSplit(salt, ikm, info)

func kdfChain(self: Doubleratchet, chainKey: ChainKey): (MessageKey, ChainKey) =

  let msgKey   = hkdfExtract(chainKey, [0x01u8], cast[seq[byte]](DomainSepKdfMsg))
  let chainKey = hkdfExtract(chainKey, [0x02u8], cast[seq[byte]](DomainSepKdfChain))

  return(msgKey, chainKey)

proc dhRatchetSend(self: var Doubleratchet) =
  # Perform DH Ratchet step when receiving a new peer key.
  info "dhRatchetSend DH Self: ", dhSelf = self.dhSelf
  self.dhSelf = generateKeypair().get()[0]
  info "dhRatchetSend new DH Self: ", dhSelf = self.dhSelf
  let dhOutput : DhDerivedKey = dhExchange(self.dhSelf, self.dhRemote).get()
  let (newRootKey, newChainKeySend) = kdfRoot(self, self.rootKey, dhOutput)
  self.rootKey = newRootKey
  self.chainKeySend = newChainKeySend
  self.msgCountSend = 0

proc dhRatchetRecv(self: var Doubleratchet, remotePublickey: PublicKey ) = 
  info "dh ratchet happens"
  info "dhRatchetRecv DH Remote: ", dhRemote = remotePublickey
  self.prevChainLen = self.msgCountSend
  self.msgCountSend = 0
  self.msgCountRecv = 0

  self.dhRemote = remotePublickey

  let dhOutputPre = self.dhSelf.dhExchange(self.dhRemote).get()
  let (newRootKey, newChainKeyRecv) = kdfRoot(self, self.rootKey, dhOutputPre)
  self.rootKey = newRootKey
  self.chainKeyRecv = newChainKeyRecv

  self.dhSelf = generateKeypair().get()[0]

  let dhOutputPost = self.dhSelf.dhExchange(self.dhRemote).get()
  (self.rootKey, self.chainKeySend) = kdfRoot(self, self.rootKey, dhOutputPost)


proc skipMessageKeys(self: var Doubleratchet, until: MsgCount): Result[(), string] =

  if self.msgCountRecv + maxSkip < until:
    return err("Too many skipped messages")

  while self.msgCountRecv < until:
    let (msgKey, chainKey) = self.kdfChain(self.chainKeyRecv)
    self.chainKeyRecv = chainKey

    let keyId = keyId(self.dhRemote, self.msgCountRecv)
    self.skippedMessageKeys[keyId] = msgKey
    inc self.msgCountRecv

  ok(())

proc encrypt(self: var Doubleratchet, plaintext: var seq[byte], associatedData: openArray[byte]): (DrHeader, CipherText) = 

  let (msgKey, chainKey) = self.kdfChain(self.chainKeySend)

  let header = DrHeader(  
                dhPublic: self.dhSelf.public, #TODO Serialize
                msgNumber: self.msgCountSend,
                prevChainLen: self.prevChainLen)

  self.msgCountSend = self.msgCountSend + 1


  var (nonce, ciphertext) = encryptWithChaCha20Poly1305(msgKey, plaintext, associatedData)

  # TODO: optimize copies
  var output : seq[byte]
  output.add(nonce)
  output.add(ciphertext)


  (header, output)


proc decrypt*(self: var Doubleratchet, header: DrHeader, ciphertext: CipherText, associatedData: openArray[byte] ) : Result[seq[byte], NaxolotlError] =
  info "double ratchet decrypt", header = $header
  info "dhRemote: ", dhRemote = self.dhRemote
  info "dhSelf: ", dhSelf = self.dhSelf
  info "dhSelf public: ", dhSelf = self.dhSelf.public

  let peerPublic = header.dhPublic

  info "peerPublic: ", peerPublic = peerPublic

  var msgKey : MessageKey

  # Check Skipped Keys
  let keyId = keyId(header.dhPublic, header.msgNumber)
  if self.skippedMessageKeys.hasKey(keyId):
    debug "detected skipped message", keyId = keyId
    msgKey = self.skippedMessageKeys[keyId]
  else:
    if (peerPublic != self.dhRemote):
      let r = self.skipMessageKeys(header.prevChainLen)
      if r.isErr:
        error "skipMessages", error = r.error()
      self.dhRatchetRecv(peerPublic)
    let r = self.skipMessageKeys(header.msgNumber)
    if r.isErr:
       error "skipMessages", error = r.error()

    (msgKey, self.chainKeyRecv) = self.kdfChain(self.chainKeyRecv)
    inc self.msgCountRecv

  var nonce : Nonce
  copyMem(addr nonce[0], unsafeAddr ciphertext[0], Nonce.len)
  var cipherTag = ciphertext[Nonce.len .. ^1]

  result = decryptWithChaCha20Poly1305(msgKey,nonce, cipherTag, associatedData )

  if result.isOk:
    # TODO: persist chainKey state changes
    self.skippedMessageKeys.del(keyId)
    

proc encrypt*(self: var Doubleratchet, plaintext: var seq[byte]) : (DrHeader, CipherText) =
  encrypt(self, plaintext,@[])


proc initDoubleratchet*(sharedSecret: array[32, byte], dhSelf: PrivateKey, dhRemote: PublicKey, inviter: bool = true): Doubleratchet =

  info "Initializing Double Ratchet"
  info "DH Self: ", dhSelf = dhSelf
  info "DH Self public: ", dhSelf = dhSelf.public
  info "DH Remote: ", dhRemote = dhRemote
  result = Doubleratchet(
      dhSelf: dhSelf,
      dhRemote: dhRemote,
      rootKey: RootKey(sharedSecret),
      msgCountSend: 0,
      msgCountRecv: 0,
      prevChainLen: 0,
      skippedMessageKeys: initTable[(PublicKey, MsgCount), MessageKey]()
  )

  if not inviter:
    result.dhRatchetSend()
