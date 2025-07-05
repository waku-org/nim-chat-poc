# Package

version       = "0.1.0"
author        = "jazzz"
description   = "An example of the chat sdk in Nim"
license       = "MIT"
srcDir        = "src"
bin           = @["nim_chat_poc"]


# Basic build task
task initialize, "Initialize the project after cloning":
  exec "./initialize.sh"


# Dependencies

requires "nim >= 2.2.4"

requires "protobuf_serialization >= 0.1.0"
requires "secp256k1 >= 0.6.0.3.2"
requires "blake2"
requires "chronicles"
requires "libp2p >= 1.11.0"
requires "nimchacha20poly1305" # TODO: remove
requires "confutils >= 0.1.0"
requires "eth >= 0.8.0"
requires "regex >= 0.26.3"
requires "web3 >= 0.7.0"
