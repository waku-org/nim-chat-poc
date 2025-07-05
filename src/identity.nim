
import crypto
import utils


type
  Identity* = object
    name: string
    keypair: KeyPair


#################################################
# Constructors
#################################################

proc createIdentity*(name: string): Identity =
  let keypair = generate_keypair()
  result = Identity(name: name, keypair: keypair)


#################################################
# Parameter Access
#################################################

proc getAddr*(self: Identity): string =
  result = get_addr(self.keypair.pubkey)


proc getPubkey*(self: Identity): SkPublicKey =
  result = self.keypair.pubkey
