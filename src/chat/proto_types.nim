# Can this be an external package? It would be preferable to have these types
# easy to import and use.

import protobuf_serialization # This import is needed or th macro will not work
import protobuf_serialization/proto_parser
import results
import std/random

export protobuf_serialization

import_proto3 "../../protos/inbox.proto"
# import_proto3 "../protos/invite.proto"    // Import3 follows protobuf includes so this will result in a redefinition error
import_proto3 "../../protos/envelope.proto"

import_proto3 "../../protos/private_v1.proto"

type EncryptableTypes = InboxV1Frame | EncryptedPayload

export EncryptedPayload
export InboxV1Frame
export PrivateV1Frame

export EncryptableTypes




proc encode*(frame: object): seq[byte] =
  ## Encodes the frame into a byte sequence using Protobuf serialization.
  result = Protobuf.encode(frame)


proc decode*[T: object] (bytes: seq[byte], proto: typedesc[
    T]): Result[T, string] =
  ## Encodes the frame into a byte sequence using Protobuf serialization.

  try:
    result = ok(Protobuf.decode(bytes, proto))
  except ProtobufError as e:
    result = err("Failed to decode payload: " & e.msg)

type
  IntroBundle {.proto3.} = object
    ident* {.fieldNumber: 1.}: seq[byte]
    ephemeral* {.fieldNumber: 2.}: seq[byte]
    ephemeral_id* {.fieldNumber: 3.}: int32


export IntroBundle

proc generateSalt*(): uint64 =
  randomize()
  result = 0
  for i in 0 ..< 8:
    result = result or (uint64(rand(255)) shl (i * 8))


proc toEnvelope*(payload: EncryptedPayload, convo_id: string): WapEnvelopeV1 =
  let bytes = encode(payload)
  let salt = generateSalt()

  # TODO: Implement hinting
  return WapEnvelopeV1(
    payload: bytes,
    salt: salt,
    conversation_hint: convo_id,
  )

###########################################################
# nim-serialize-protobuf does not support oneof fields.
# As a stop gap each object using oneof fields, needs
# a implementation to look up the type.
#
# The valid field is determined by the fields which
# is not set to the default value
###########################################################

type
  InboxV1FrameType* = enum
    type_InvitePrivateV1, type_Note

proc getKind*(obj: InboxV1Frame): InboxV1FrameType =

  if obj.invite_private_v1 != InvitePrivateV1():
    return type_InvitePrivateV1

  if obj.note != Note():
    return type_Note

  raise newException(ValueError, "Un handled one of type")

type
  PrivateV1FrameType* = enum
    type_Content, type_Placeholder

proc getKind*(obj: PrivateV1Frame): PrivateV1FrameType =

  if obj.content != @[]:
    return type_Content

  if obj.placeholder != Placeholder():
    return type_Placeholder

  raise newException(ValueError, "Un handled one of type")
