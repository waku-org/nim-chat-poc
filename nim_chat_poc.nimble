# Package

version       = "0.1.0"
author        = "jazzz"
description   = "An example of the chat sdk in Nim"
license       = "MIT"
srcDir        = "src"
bin           = @["nim_chat_poc", "dev"]


# Basic build task
task initialize, "Initialize the project after cloning":
  exec "./initialize.sh"

# # Clean 
# task cleandeps, "Remove and refresh dependencies":
#   rm -rf ~/.nimble/pkgs2/sds-*
#   rm -rf ~/.nimble/pkgcache/githubcom_jazzznimsds*


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
requires "file:///Users/jazzz/dev/nim-sds#dev"
