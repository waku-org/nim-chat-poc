import std/[options, times]

import ./conversations/convo_type
import crypto
import identity
import proto_types

type ConvoId = string

type
  ConversationStore* = concept
    proc addConversation(self: Self, convo: Conversation)
    proc getConversation(self: Self, convoId: string): Conversation
    proc identity(self: Self): Identity
    proc getId(self: Self): string

    proc notifyNewMessage(self: Self, convo: Conversation,
        content: ContentFrame)
