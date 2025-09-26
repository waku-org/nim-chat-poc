import chronos
import chronicles
import strformat

import chat_sdk/client
import chat_sdk/identity
import chat_sdk/conversations
import chat_sdk/delivery/waku_client
import chat_sdk/utils
import chat_sdk/proto_types

import content_types/all
import libp2p/crypto/crypto
# import libp2p/crypto/secp256k1
import os
import std/sequtils
import strutils
import tables
import std/parseopt

import std/json
import std/jsonutils except distinctBase
import std/marshal
import std/streams

import std/base64



import tui/persistence


const SELF_DEFINED = 99


#################################################
# Command Line Args
#################################################

type CmdArgs = object
  username*: string
  invite*: string

proc getCmdArgs(): CmdArgs =
  var username = ""
  var invite = ""
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      discard
    of cmdLongOption, cmdShortOption:
      case key
      of "name", "n":
        username = val
      of "invite", "i":
        invite = val
    of cmdEnd:
      break
  if username == "":
    username = "<anonymous>"

  result = CmdArgs(username: username, invite: invite)



#################################################
# Link Generation
#################################################

proc toBundle*(link: string): Result[IntroBundle, string] =
  # Check scheme
  if not link.startsWith("wap://"):
    return err("InvalidScheme")

  # Remove scheme
  let path = link[6..^1] # Remove "waku://"

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


proc toLink(intro: IntroBundle): string =
  let ident = encode(intro.ident, safe = true)
  let ephemeral = intro.ephemeral.toHex()
  result = fmt"wap://ident/{ident}/ephemeral/{ephemeral}/eid/{intro.ephemeral_id}"


proc createChatClient(name: string): Future[Client] {.async.} =
  try:
    var cfg = await getCfg(name)
    for key, val in fetchRegistrations():
      if key != name:
        cfg.waku.staticPeers.add(val)

    result = newClient(name, cfg.waku, cfg.ident)
  except Exception as e:
    echo "Failed to create client: ", e.msg

proc main() {.async.} =

  let args = getCmdArgs()
  var client = await createChatClient(args.username)

  echo "Identity: ", client.getId()
  echo "Key: ", client.identity.getAddr()
  echo "NodeAaddr:", client.ds.cfg.getMultiAddr() 

  client.onNewMessage(proc(convo: Conversation, msg: ContentFrame) {.async.} =
    echo "           ------>  Raya :: "
    await sleepAsync(10000)
    await convo.sendMessage(client.ds, initTextFrame("Pong").toContentFrame())
  )

  client.onNewConversation(proc(convo: Conversation) {.async.} =
    echo "           ------>  Raya :: New Conversation: " & convo.id()
    await convo.sendMessage(client.ds, initTextFrame("Hello").toContentFrame())
  )

  client.onDeliveryAck(proc(convo: Conversation, msgId: string) {.async.} =
    echo "    raya -- Read Receipt for " & msgId
  )

  await client.start()




  # Perform OOB Introduction: Raya -> Saro
  let x = proc() {.async.} =
    while true:
      await sleepAsync(5000)
      notice "Heartbeat - PeerCount: ", peerCount = client.ds.getConnectedPeerCount()
  asyncSpawn x()


  warn "==== arg Invite ", arg= args.invite, peers = client.ds.getConnectedPeerCount()
  if args.invite != "":
    let invite = toBundle(args.invite).get()
    await sleepAsync(20000)
    discard await client.newPrivateConversation(invite)
  else:
    let bundle = client.createIntroBundle()
    echo "Link: ", toLink(bundle)
#


  # let link = toLink(raya_bundle)
  # echo "Raya Intro Link: ", link

  # let parsed = toBundle(link).get()
  # echo repr(parsed)

  await sleepAsync(400000)

  client.stop()

when isMainModule:
  setLogLevel(LogLevel.Debug)
  waitFor main()
  notice "Shutdown"
