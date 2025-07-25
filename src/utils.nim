import std/times
import waku/waku_core


proc getTimestamp*(): Timestamp =
    result = waku_core.getNanosecondTime(getTime().toUnix())
