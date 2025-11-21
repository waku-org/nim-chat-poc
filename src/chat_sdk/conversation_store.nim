import ./conversations/[convo_type, message]
import identity
import types

type ConvoId = string

type
  ConversationStore* = concept
    proc addConversation(self: Self, convo: Conversation)
    proc getConversation(self: Self, convoId: string): Conversation
    proc identity(self: Self): Identity
    proc getId(self: Self): string

    proc notifyNewMessage(self: Self, convo: Conversation, msg: ReceivedMessage)
    proc notifyDeliveryAck(self: Self, convo: Conversation,
        msgId: MessageId)
