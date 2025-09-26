import chronicles
import chronos
import libp2p/crypto/crypto
import sequtils
import std/json
import std/jsonutils except distinctBase
import std/marshal
import std/options
import std/os
import std/streams
import strformat
import strutils
import tables

import chat_sdk/crypto/ecdh
import chat_sdk/delivery/waku_client
import chat_sdk/identity


const REGISTRATION_DIR = ".registry"
const KEY_DIR = ".savedkeys"


type Config* = object
  ident*: Identity
  waku*: WakuConfig

type SavedConfig* = object
  name*: string
  idkey*: seq[byte]
  nodekey*: seq[byte]
  port*: uint16
  clusterId*: uint16
  shardId*: seq[uint16] 
  pubsubTopic*: string
  staticPeers*: seq[string]


proc toWakuConfig(s: SavedConfig): WakuConfig =
  result = WakuConfig(
    nodekey: crypto.PrivateKey.init(s.nodekey).get(),
    port: s.port,
    clusterId: s.clusterId,
    shardId: s.shardId,
    pubsubTopic: s.pubsubTopic,
    staticPeers: s.staticPeers
  )


proc toIdent(s: SavedConfig): Identity =
  result = Identity(
    name: s.name,
    privateKey: loadPrivateKeyFromBytes(s.idkey).get()
  )


proc register(name: string, multiAddr: string) {.async.} =

  notice "Registering Account", name=name, maddr=multiAddr
  try:
    writeFile(joinPath(".registry", fmt"{name.toLower()}.maddr"), multiAddr)
  except IOError as e:
    echo "Failed to write registration file: ", e.msg
    raise e


proc fetchRegistrations*(): Table[string, string] =

  let allFiles = toSeq(walkFiles(fmt"{REGISTRATION_DIR}/*"))
  result = allFiles.mapIt((splitFile(it)[1], readFile(it).strip())).toTable()


proc loadCfg(file: string): Option[Config] =
  let data = parseFile(file)

  let cfg = Config(
    ident: toIdent(data.to(SavedConfig)),
    waku: toWakuConfig(data.to(SavedConfig))
  )

  result = some(cfg)


proc fetchCfg(name: string): Option[Config ] =
  let allFiles = toSeq(walkFiles(fmt"{KEY_DIR}/*"))

  for file in allFiles:
    if name == splitFile(file)[1]:
      return loadCfg(file)
  return none(Config)


proc saveCfg(name:string, cfg: Config) =

  let s = SavedConfig(
    name: name,
    idkey: cfg.ident.privatekey.bytes().toSeq(),
    nodekey: cfg.waku.nodekey.getBytes().get(),
    port: cfg.waku.port,
    clusterId: cfg.waku.clusterId,
    shardId: cfg.waku.shardId,
    pubsubTopic: cfg.waku.pubsubTopic,
    staticPeers: cfg.waku.staticPeers
  )

  let json = jsonutils.toJson(s)

  try:
    writeFile(joinPath(KEY_DIR, fmt"{name.toLower()}.cfg"), $json)
  except IOError as e:
    echo "Failed to write cfg file: ", e.msg
    raise e


proc getCfg*(name: string): Future[Config] {.async.} =
  let cfgOpt = fetchCfg(name)
  if cfgOpt.isSome:
    result = cfgOpt.get()
  else:
    let newCfg = Config(
      ident: createIdentity(name),
      waku: DefaultConfig()
    )
    saveCfg(name, newCfg)
    await register(name, newCfg.waku.getMultiAddr())

    result = newCfg
