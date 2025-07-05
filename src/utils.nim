import std/[random]
import crypto
import blake2

proc generateSalt*(): uint64 =
  randomize()
  result = 0
  for i in 0 ..< 8:
    result = result or (uint64(rand(255)) shl (i * 8))



proc get_addr*(pubkey: SkPublicKey): string =
  # TODO: Needs Spec
  result = getBlake2b(pubkey.toHexCompressed(), 4, "")


