# Package

version = "0.1.0"
author = "jazzz"
description = "An example of the chat sdk in Nim"
license = "MIT"
srcDir = "src"
bin = @["nim_chat_poc"]

# Dependencies

requires "nim >= 2.2.4"

requires "protobuf_serialization"
requires "secp256k1"
requires "blake2"
requires "chronicles"
requires "libp2p"
requires "nimchacha20poly1305" # TODO: remove
requires "confutils"
requires "eth"
requires "regex"
requires "web3"
requires "https://github.com/jazzz/nim-sds#exports"
requires "naawaku"

proc buildBinary(name: string, srcDir = "./", params = "", lang = "c") =
  if not dirExists "build":
    mkDir "build"
  # allow something like "nim nimbus --verbosity:0 --hints:off nimbus.nims"
  var extra_params = params
  for i in 2 ..< paramCount():
    extra_params &= " " & paramStr(i)

  exec "nim " & lang & " --out:build/" & name & " --mm:refc " & extra_params & " " &
    srcDir & name & ".nim"

task waku_example, "Build Waku based simple example":
  let name = "waku_example"
  buildBinary name, "examples/", " -d:chronicles_log_level='TRACE' "
