import waku/waku_core
import std/[random, times]
import crypto
import blake2

proc getTimestamp*(): Timestamp =
    result = waku_core.getNanosecondTime(getTime().toUnix())

proc generateSalt*(): uint64 =
    randomize()
    result = 0
    for i in 0 ..< 8:
        result = result or (uint64(rand(255)) shl (i * 8))

proc hash_func*(s: string): string =
    # This should be Blake2s but it does not exist so substituting with Blake2b
    result = getBlake2b(s, 4, "")

proc get_addr*(pubkey: SkPublicKey): string =
    # TODO: Needs Spec
    result = hash_func(pubkey.toHexCompressed())



