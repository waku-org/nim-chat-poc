# run with `./build/bot_echo`

import chronicles
import chronos

import chat_sdk
import content_types

import ./tui/persistence # Temporary Workaround for PeerDiscovery

proc main() {.async.} =

  let cfg = await getCfg("EchoBot")
  # let dsConfig = DefaultConfig()
  # let ident = createIdentity("EchoBot")
  var chatClient = newClient(dsConfig, ident)

  chatClient.onNewMessage(proc(convo: Conversation, msg: ContentFrame) {.async.} =
    info "New Message: ", convoId = convo.id(), msg= msg
    await convo.sendMessage(chatClient.ds, msg)
  )

  chatClient.onNewConversation(proc(convo: Conversation) {.async.} =
    info "New Conversation Initiated: ", convoId = convo.id()
    await convo.sendMessage(chatClient.ds, initTextFrame("Hello!").toContentFrame())
  )

  await chatClient.start()
  
  info "EchoBot started"
  info "Invite", link=chatClient.createIntroBundle().toLink()

when isMainModule:
  waitFor main()
  runForever()