import std/[options, times]
import conversation
import crypto
import identity

type ConvoId = string




type
  ConversationStore* = concept
    proc addConversation(self: Self, convo: Conversation)
    proc getConversation(self: Self, convoId: string): Conversation
    proc identity(self: Self): Identity
    proc getId(self: Self): string
