# Package

version       = "0.1.0"
author        = "jazzz"
description   = "An example of the chat sdk in Nim"
license       = "MIT"
srcDir        = "src"
bin           = @["nim_chat_poc"]


# Dependencies

requires "nim >= 2.2.4"

requires "protobuf_serialization >= 0.1.0"
requires "secp256k1 >= 0.6.0.3.2"
requires "blake2"
requires "chronicles"
# requires "waku"