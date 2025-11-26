
import algorithm
import chronicles
import chronos
import illwill
import libp2p/crypto/crypto
import times
import strformat
import strutils
import sugar
import tables

import chat
import content_types/all

import layout
import persistence
import utils

const charVert = "│"
const charHoriz = "─"
const charTopLeft = "┌"
const charTopRight = "┐"
const charBottomLeft = "└"
const charBottomRight = "┘"

type

  LogEntry = object
    level: string
    ts: DateTime
    msg: string

  Message = object
    sender: string
    content: string
    timestamp: DateTime
    id: string
    isAcknowledged: bool

  ConvoInfo = object
    name: string
    convo: Conversation
    messages: seq[Message] 
    lastMsgTime*: DateTime
    isTooLong*: bool

  ChatApp = ref object
    client: Client
    tb: TerminalBuffer
    conversations: Table[string, ConvoInfo]
    selectedConv: string
    inputBuffer: string
    inputInviteBuffer: string
    scrollOffset: int
    messageScrollOffset: int
    inviteModal: bool

    currentInviteLink: string
    isInviteReady: bool
    peerCount: int

    logMsgs: seq[LogEntry]

proc `==`(a,b: ConvoInfo):bool =
  if a.name==b.name:
    true
  else:
    false


#################################################
# Data Management
#################################################

proc addMessage(conv: var ConvoInfo, messageId: MessageId, sender: string, content: string) =

  let now = now()
  conv.messages.add(Message(
    sender: sender,
    id: messageId,
    content: content,
    timestamp: now,
    isAcknowledged: false
  ))
  conv.lastMsgTime = now


proc mostRecentConvos(app: ChatApp): seq[ConvoInfo] =
  var convos = collect(for v in app.conversations.values: v)
  convos.sort(proc(a, b: ConvoInfo): int = -cmp(a.lastMsgTime, b.lastMsgTime))

  return convos

proc getSelectedConvo(app: ChatApp): ptr ConvoInfo =
  if app.conversations.hasKey(app.selectedConv):
    return addr app.conversations[app.selectedConv]

  return addr app.conversations[app.mostRecentConvos()[0].name]



#################################################
# ChatSDK Setup
#################################################

proc createChatClient(name: string): Future[Client] {.async.} =
  var cfg = await getCfg(name)
  for key, val in fetchRegistrations():
    if key != name:
      cfg.waku.staticPeers.add(val)

  result = newClient(cfg.waku, cfg.ident)


proc createInviteLink(app: var ChatApp): string =
  app.client.createIntroBundle().toLink()


proc createConvo(app: ChatApp) {.async.} = 
  discard await app.client.newPrivateConversation(toBundle(app.inputInviteBuffer.strip()).get())

proc sendMessage(app: ChatApp, convoInfo: ptr ConvoInfo, msg: string) {.async.} = 

  var msgId = ""
  if convoInfo.convo != nil:
    msgId = await convoInfo.convo.sendMessage(app.client.ds, initTextFrame(msg).toContentFrame())

  convoInfo[].addMessage(msgId, "You", app.inputBuffer)


proc setupChatSdk(app: ChatApp) =

  let client = app.client

  app.client.onNewMessage(proc(convo: Conversation, msg: ReceivedMessage) {.async.} =
    info "New Message: ", convoId = convo.id(), msg= msg
    app.logMsgs.add(LogEntry(level: "info",ts: now(), msg: "NewMsg"))

    var contentStr = case msg.content.contentType
      of text: 
        decode(msg.content.bytes, TextFrame).get().text
      of unknown:
        "<Unhandled Message Type>"

    app.conversations[convo.id()].messages.add(Message(sender: msg.sender.toHex(), content: contentStr, timestamp: now())) 
  )

  app.client.onNewConversation(proc(convo: Conversation) {.async.} =
    app.logMsgs.add(LogEntry(level: "info",ts: now(), msg: fmt"Adding Convo: {convo.id()}"))
    info "New Conversation: ", convoId = convo.id()

    app.conversations[convo.id()] = ConvoInfo(name: convo.id(), convo: convo,  messages: @[], lastMsgTime: now(), isTooLong: false)
  )
  
  app.client.onDeliveryAck(proc(convo: Conversation, msgId: string) {.async.} =
    info "DeliveryAck", msgId=msgId
    app.logMsgs.add(LogEntry(level: "info",ts: now(), msg: fmt"Ack:{msgId}"))

    var s = ""
    var msgs = addr app.conversations[convo.id()].messages
    for i in countdown(msgs[].high, 0):
      s = fmt"{s},{msgs[i].id}"
      var m = addr msgs[i]

      if m.id == msgId:
          m.isAcknowledged = true
          break  # Stop after 
  )


#################################################
# Draw Funcs
#################################################

proc resetTuiCursor(tb: var TerminalBuffer) =
  tb.setForegroundColor(fgWhite)
  tb.setBackgroundColor(bgBlack)


proc drawOutline(tb: var TerminalBuffer, layout: Pane, color: ForegroundColor,
    bg: BackgroundColor = bgBlack) =

  for x in layout.xStart+1..<layout.xStart+layout.width:
    tb.write(x, layout.yStart, charHoriz, color, bg)
    tb.write(x, layout.yStart+layout.height-1, charHoriz, color, bg)

  for y in layout.yStart+1..<layout.yStart+layout.height:
    tb.write(layout.xStart, y, charVert, color, bg)
    tb.write(layout.xStart+layout.width-1, y, charVert, color, bg)

  tb.write(layout.xStart, layout.yStart, charTopLeft, color, bg)
  tb.write(layout.xStart+layout.width-1, layout.yStart, charTopRight, color, bg)
  tb.write(layout.xStart, layout.yStart+layout.height-1, charBottomLeft, color, bg)
  tb.write(layout.xStart+layout.width-1, layout.yStart+layout.height-1,
      charBottomRight, color, bgBlack)


proc drawStatusBar(app: ChatApp, layout: Pane , fg: ForegroundColor, bg: BackgroundColor) =
  var tb = app.tb
  tb.setForegroundColor(fg)
  tb.setBackgroundColor(bg)

  for x in layout.xStart..<layout.width:
    for y in layout.yStart..<layout.height:
      tb.write(x, y, " ")

  var i = layout.yStart + 1
  var chunk = layout.width - 9
  tb.write(1, i, "Name: " & app.client.getId())
  inc i
  tb.write(1, i, fmt"PeerCount: {app.peerCount}")
  inc i
  tb.write(1, i, "Link: ")
  for a in 0..(app.currentInviteLink.len div chunk) :
    tb.write(1+6 , i, app.currentInviteLink[a*chunk ..< min((a+1)*chunk, app.currentInviteLink.len)])
    inc i

  resetTuiCursor(tb)


proc drawConvoItem(app: ChatApp,
    layout: Pane, convo: ConvoInfo, isSelected: bool = false) =

  var tb = app.tb
  let xOffset = 3
  let yOffset = 1

  let dt = convo.lastMsgTime 

  let c = if isSelected: fgMagenta else: fgCyan
  if isSelected:
    tb.setForegroundColor(fgMagenta)
  else:
    tb.setForegroundColor(fgCyan)

  drawOutline(tb, layout, c)
  tb.write(layout.xStart+xOffset, layout.yStart+yOffset, convo.name)
  tb.write(layout.xStart+xOffset, layout.yStart+yOffset+1,dt.format("yyyy-MM-dd HH:mm:ss"))


proc drawConversationPane( app: ChatApp, layout: Pane) =
  var a = layout
  a.width -= 2
  a.height = 6
  for convo in app.mostRecentConvos():
    drawConvoItem(app, a, convo, app.selectedConv == convo.name)
    a.yStart = a.yStart + a.height


proc splitAt(s: string, index: int): (string, string) =
  let splitIndex = min(index, s.len)
  return (s[0..<splitIndex], s[splitIndex..^1])

# Eww
proc drawMsgPane( app: ChatApp, layout: Pane) =
  var tb = app.tb
  drawOutline(tb, layout, fgYellow)

  var convo = app.getSelectedConvo()

  let xStart = layout.xStart+1
  let yStart = layout.yStart+1


  let w = layout.width
  let h = layout.height

  let maxContentWidth = w - 10

  let xEnd = layout.xStart + maxContentWidth
  let yEnd = layout.yStart + layout.height - 2


  tb.setForegroundColor(fgGreen)

  let x = xStart + 2

  if not convo.isTooLong:
    var y = yStart
    for i in 0..convo.messages.len-1:

      let m = convo.messages[i]
      let timeStr = m.timestamp.format("HH:mm:ss")
      var deliveryIcon = " "
      var remainingText = m.content
      
      if m.sender == "You":
        tb.setForegroundColor(fgYellow)
        deliveryIcon = if m.isAcknowledged: "✔" else: "◯"
      else:
        tb.setForegroundColor(fgGreen)

      if y > yEnd:
          convo.isTooLong = true
          app.logMsgs.add(LogEntry(level: "info",ts: now(), msg: fmt" TOO LONG: {convo.name}"))

          return
      tb.write(x, y, fmt"[{timeStr}]  {deliveryIcon}  {m.sender}")
      y = y + 1

      while remainingText.len > 0:
        if y > yEnd:
          convo.isTooLong = true
          app.logMsgs.add(LogEntry(level: "info",ts: now(), msg: fmt" TOO LON2: {convo.name}"))

          return

        let (line, remain) = remainingText.splitAt(maxContentWidth)
        remainingText = remain

        tb.write(x+3, y, line)
        y = y + 1
      y = y + 1
  else:
    var y = yEnd
    for i in countdown(convo.messages.len-1, 0):

      let m = convo.messages[i]
      let timeStr = m.timestamp.format("HH:mm:ss")
      var deliveryIcon = " "
      var remainingText = m.content

      if m.sender == "You":
        tb.setForegroundColor(fgYellow)
        deliveryIcon = if m.isAcknowledged: "✔" else: "◯"
      else:
        tb.setForegroundColor(fgGreen)

      # Print lines in reverse order
      while remainingText.len > 0:
        if (y <= yStart + 1):
            return
        var lineLen = remainingText.len mod maxContentWidth
        if lineLen == 0:
          lineLen = maxContentWidth

        let line = remainingText[^lineLen..^1]
        remainingText = remainingText[0..^lineLen+1] 

        tb.write(x+3, y, line)
        y = y - 1
      
      tb.write(x, y, fmt"[{timeStr}]  {deliveryIcon}  {m.sender}")
      y = y - 2

proc drawMsgInput( app: ChatApp, layout: Pane) =
  var tb = app.tb
  drawOutline(tb, layout, fgCyan)


  let inputY = layout.yStart + 2
  let paneStart = layout.xStart

  # Draw input prompt
  tb.write(paneStart + 1, inputY, " > " & app.inputBuffer, fgWhite)

  # Draw cursor
  let cursorX = paneStart + 3 + app.inputBuffer.len + 1
  if cursorX < paneStart + layout.width - 1:
    tb.write(cursorX, inputY, "_", fgYellow)

  discard

proc drawFooter( app: ChatApp, layout: Pane) =
  var tb = app.tb
  drawOutline(tb, layout, fgBlue)

  let xStart = layout.xStart + 3
  let yStart = layout.yStart + 2

  for i in countdown(app.logMsgs.len - 1, 0):
    let o = app.logMsgs[i]
    let timeStr = o.ts.format("HH:mm:ss")
    let s = fmt"[{timeStr}] {o.level} - {o.msg}"
    app.tb.write( xStart, yStart+i*2, s )
  discard


proc drawModal(app: ChatApp, layout: Pane,
    color: ForegroundColor, bg: BackgroundColor = bgBlack) =

  var tb = app.tb  
  tb.setForegroundColor(color)
  tb.setBackgroundColor(bg)
  for x in layout.xStart..<layout.xStart+layout.width:
    for y in layout.yStart..<layout.yStart+layout.height:
      tb.write(x, y, " ", color)
      
  tb.setForegroundColor(fgBlack)
  tb.setBackgroundColor(bgGreen)
  tb.write(layout.xStart + 2, layout.yStart + 2, "Paste Invite")

  tb.setForegroundColor(fgWhite)
  tb.setBackgroundColor(bgBlack)
  let inputLine = 5

  for i in layout.xStart+3..<layout.xStart+layout.width-3:
    for y in (layout.yStart + inputLine - 1)..<(layout.yStart+inputLine + 2):
      tb.write(i, y, " ")

    # Draw input prompt
  tb.write(layout.xStart+5, layout.yStart+inputLine, "> " & app.inputInviteBuffer)

  # Draw cursor 
  let cursorX = layout.xStart+5+1 + app.inputInviteBuffer.len
  if cursorX < terminalWidth() - 1:
    tb.write(cursorX, layout.yStart+inputLine, "_", fgYellow)

  tb.setForegroundColor(fgBlack)
  tb.setBackgroundColor(bgGreen)
  tb.write(layout.xStart+5, layout.yStart+inputLine+3, "InviteLink: " & app.currentInviteLink)

  resetTuiCursor(tb)

#################################################
# Input Handling
#################################################

proc gePreviousConv(app: ChatApp): string =
  let convos = app.mostRecentConvos()
  let i = convos.find(app.getSelectedConvo()[])

  return convos[max(i-1, 0)].name


proc getNextConv(app: ChatApp): string =
  let convos = app.mostRecentConvos()
  var s = ""
  for c in convos:
    s = s & c.name

  let i = convos.find(app.getSelectedConvo()[])
  app.logMsgs.add(LogEntry(level: "info",ts: now(), msg: fmt"i:{convos[min(i+1, convos.len-1)].isTooLong}"))

  return convos[min(i+1, convos.len-1)].name


proc handleInput(app:  ChatApp, key: Key) {.async.} =
  case key
  of Key.Up:
    app.selectedConv = app.gePreviousConv()
  of Key.Down:
    app.selectedConv = app.getNextConv()

  of Key.PageUp:
    app.messageScrollOffset = min(app.messageScrollOffset + 5, 0)
  of Key.PageDown:
    app.messageScrollOffset = max(app.messageScrollOffset - 5,
      -(max(0, app.getSelectedConvo().messages.len - 10)))
  of Key.Enter:

    if app.inviteModal:
      notice "Enter Invite", link= app.inputInviteBuffer
      app.inviteModal = false
      app.isInviteReady = true
    else:
      if app.inputBuffer.len > 0 and app.conversations.len > 0:

        let sc = app.getSelectedConvo() 
        await app.sendMessage(sc, app.inputBuffer)

        app.inputBuffer = ""
        app.messageScrollOffset = 0 # Auto-scroll to bottom
  of Key.Backspace:
    if app.inputBuffer.len > 0:
      app.inputBuffer.setLen(app.inputBuffer.len - 1)
  of Key.Tab:
    app.inviteModal = not app.inviteModal

    if app.inviteModal:
      app.currentInviteLink = app.client.createIntroBundle().toLink()
  of Key.Escape, Key.CtrlC:
    quit(0)
  else:
    # Handle regular character input
    let ch = char(key)
    if ch.isAlphaNumeric() or ch in " !@#$%^&*()_+-=[]{}|;':\",./<>?":
      if app.inviteModal:
        app.inputInviteBuffer.add(ch)
      else:
        app.inputBuffer.add(ch)


#################################################
# Tasks
#################################################

proc appLoop(app: ChatApp, panes: seq[Pane]) : Future[void] {.async.} =
  illwillInit(fullscreen = false)
  # Clear buffer
  while true:
    await sleepAsync(5.milliseconds)
    app.tb.clear()

    drawStatusBar(app, panes[0], fgBlack, getIdColor(app.client.getId()))
    drawConversationPane(app, panes[1])
    drawMsgPane(app, panes[2])

    if app.inviteModal:
      drawModal(app, panes[5], fgYellow, bgGreen)
    else:
      drawMsgInput(app, panes[3])

    drawFooter(app, panes[4])

    # Draw help text
    app.tb.write(1, terminalHeight()-1, "Tab: Invite Modal | ↑/↓: Select conversation | PgUp/PgDn: Scroll messages | Enter: Send | Esc: Quit", fgGreen)

    # Display buffer
    app.tb.display()

    # Handle input
    let key = getKey()
    await handleInput(app, key)

    if app.isInviteReady:

      try:
        let sanitized = app.inputInviteBuffer.replace(" ", "").replace("\r","")
        discard await app.client.newPrivateConversation(toBundle(app.inputInviteBuffer.strip()).get())

      except Exception as e:
        info "bad invite", invite = app.inputInviteBuffer
      app.inputInviteBuffer = ""
      app.isInviteReady = false

proc peerWatch(app: ChatApp): Future[void] {.async.} =
  while true:
    await sleepAsync(1.seconds)
    app.peerCount = app.client.ds.getConnectedPeerCount()


#################################################
# Main
#################################################  

proc initChatApp(client: Client): Future[ChatApp] {.async.} =

  var app = ChatApp(
    client: client,
    tb: newTerminalBuffer(terminalWidth(), terminalHeight()),
    conversations: initTable[string, ConvoInfo](),
    selectedConv: "Bob",
    inputBuffer: "",
    scrollOffset: 0,
    messageScrollOffset: 0,
    isInviteReady: false,
    peerCount: -1,
    logMsgs: @[]
  )

  app.setupChatSdk()
  await app.client.start()


  # Add some sample conversations with messages
  var sender = "Nobody"
  var conv1 = ConvoInfo(name: "ReadMe", messages: @[])
  conv1.addMessage("",sender, "First start multiple clients and ensure, that he PeerCount is correct (it's listed in the top left corner)")
  conv1.addMessage("",sender, "Once connected, The sender needs to get the recipients introduction link. The links contains the key material and information required to initialize a conversation. Press `Tab` to generate a link")
  conv1.addMessage("",sender, "Paste the link from one client into another. This will start the initialization protocol, which will send an invite to the recipient and negotiate a conversation")
  conv1.addMessage("",sender, "Once established, Applications are notified by a callback that a new conversation has been established, and participants can send messages")
    

  
  app.conversations[conv1.name] = conv1

  return app


proc main*() {.async.} =

  let args = getCmdArgs()
  let client = await createChatClient(args.username)
  var app = await initChatApp(client)

  let tasks: seq[Future[void]] = @[
    appLoop(app, getPanes()),
    peerWatch(app)
  ]

  discard await allFinished(tasks)

when isMainModule:
  waitFor main()

# this is not nim code