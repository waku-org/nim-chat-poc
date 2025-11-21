import base64
import chronos
import strformat
import strutils

import libp2p/crypto/crypto

import ../content_types/all
import proto_types
import utils


#################################################
# Link Generation
#################################################

proc toBundle*(link: string): Result[IntroBundle, string] =
  # Check scheme
  if not link.startsWith("wap://"):
    return err("InvalidScheme")

  # Remove scheme
  let path = link[6..^1]

  # Split by '/'
  let parts = path.split('/')

  # Expected format: ident/{ident}/ephemeral/{ephemeral}/eid/{eid}
  if parts.len != 6:
    return err("InvalidFormat")

  # Validate structure
  if parts[0] != "ident" or parts[2] != "ephemeral" or parts[4] != "eid":
    return err("InvalidFormat")

  # Extract values
  let ident = decode(parts[1]).toBytes()
  let ephemeral = decode(parts[3]).toBytes()

  let eid = int32(parseInt(parts[5])) # TODO: catch parse error

  # Validate non-empty
  if ident.len == 0:
    return err("MissingIdent")
  if ephemeral.len == 0:
    return err("MissingEphemeral")

  return ok(IntroBundle(
    ident: ident,
    ephemeral: ephemeral,
    ephemeral_id: eid
  ))


proc toLink*(intro: IntroBundle): string =
  let ident = encode(intro.ident, safe = true)
  let ephemeral = intro.ephemeral.toHex()
  result = fmt"wap://ident/{ident}/ephemeral/{ephemeral}/eid/{intro.ephemeral_id}"
