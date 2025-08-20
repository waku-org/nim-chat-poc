import conversation_store
import conversation

import inbox
import conversations/private_v1


proc getType(convo: Conversation): ConvoTypes =
  if convo of Inbox:
    return InboxV1Type

  elif convo of PrivateV1:
    return PrivateV1Type

  else:
    raise newException(Defect, "Conversation Type not processed")

proc handleFrame*[T: ConversationStore](convo: Conversation, client: T,
  bytes: seq[byte]) =

  case convo.getType():
  of InboxV1Type:
    let inbox = Inbox(convo)
    inbox.handleFrame(client, bytes)

  of PrivateV1Type:
    let priv = PrivateV1(convo)
    priv.handleFrame(client, bytes)


