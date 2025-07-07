# Can this be an external package? It would be preferable to have these types
# easy to import and use.

import protobuf_serialization # This import is needed or th macro will not work
import protobuf_serialization/proto_parser
import results

export protobuf_serialization

import_proto3 "../protos/inbox.proto"
# import_proto3 "../protos/invite.proto"    // Import3 follows protobuf includes so this will result in a redefinition error
import_proto3 "../protos/encryption.proto"
import_proto3 "../protos/envelope.proto"

type EncryptableTypes = InboxV1Frame | EncryptedPayload

export EncryptedPayload
export InboxV1Frame

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


type
  TransportMessage {.proto3.} = object
    topic* {.fieldNumber: 1.}: string
    payload* {.fieldNumber: 2.}: seq[byte]

# Place holder for a transport channel
proc sendTo*(topic: string, payload: seq[byte]): TransportMessage =
  result = TransportMessage(topic: topic, payload: payload)

export TransportMessage
