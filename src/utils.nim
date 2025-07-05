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

proc get_addr*(pubkey: SkPublicKey): string =
    # TODO: Needs Spec
    result = getBlake2b(pubkey.toHexCompressed(), 4, "")

