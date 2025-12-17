import waku/waku_core
import std/[macros, times]
import blake2
import strutils

proc getCurrentTimestamp*(): Timestamp =
    result = waku_core.getNanosecondTime(getTime().toUnix())


proc hash_func_bytes*(n: static range[1..64], s: string | seq[byte]): seq[uint8] =

    let key = ""
    var b: Blake2b
    blake2b_init(b, n, cstring(key), len(key))
    blake2b_update(b, s, len(s))
    result = blake2b_final(b)

proc hash_func_str*(n: static range[1..64], s: string | seq[byte]): string =
    result = $hash_func_bytes(n,s)

proc bytesToHex*[T](bytes: openarray[T], lowercase: bool = false): string =
    ## Convert bytes to hex string with case option
    result = ""
    for b in bytes:
        let hex = b.toHex(2)
        result.add(if lowercase: hex.toLower() else: hex)

proc toBytes*(s: string): seq[byte] =
    result = cast[seq[byte]](s)

proc toUtfString*(b: seq[byte]): string =
    result = cast[string](b)

macro panic*(reason: string): untyped =
    result = quote do:
        let pos = instantiationInfo()
        echo `reason` & " ($1:$2)" % [
          pos.filename, $pos.line]
        echo "traceback:\n", getStackTrace()
        quit(1)
