
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

import ../chat_sdk/client
import ../chat_sdk/conversations
import ../chat_sdk/delivery/waku_client
import ../chat_sdk/links
import ../chat_sdk/proto_types
import ../content_types/all

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

  ConvoInfo = object
    name: string
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
# ChatSDK Setup
#################################################

proc createChatClient(name: string): Future[Client] {.async.} =
  var cfg = await getCfg(name)
  for key, val in fetchRegistrations():
    if key != name:
      cfg.waku.staticPeers.add(val)

  result = newClient(name, cfg.waku, cfg.ident)


proc createInviteLink(app: var ChatApp): string =
  app.client.createIntroBundle().toLink()


proc createConvo(app: ChatApp) {.async.} = 
  discard await app.client.newPrivateConversation(toBundle(app.inputInviteBuffer.strip()).get())



proc setupChatSdk(app: ChatApp) =

  let client = app.client

  app.client.onNewMessage(proc(convo: Conversation, msg: ContentFrame) {.async.} =
    info "New Message: ", convoId = convo.id(), msg= msg
    app.logMsgs.add(LogEntry(level: "info",ts: now(), msg: "NewMsg"))

    var contentStr = case msg.contentType
      of text: 
        decode(msg.bytes, TextFrame).get().text
      of unknown:
        "<Unhandled Message Type>"

    app.conversations[convo.id()].messages.add(Message(sender: "???", content: contentStr, timestamp: now())) 

    # await sleepAsync(10000)
    # await convo.sendMessage(client.ds, initTextFrame("Pong").toContentFrame())
  )

  app.client.onNewConversation(proc(convo: Conversation) {.async.} =
    app.logMsgs.add(LogEntry(level: "info",ts: now(), msg: fmt"Adding Convo: {convo.id()}"))
    info "New Conversation: ", convoId = convo.id()

    app.conversations[convo.id()] = ConvoInfo(name: convo.id(), messages: @[], lastMsgTime: now(), isTooLong: false)
    # await convo.sendMessage(client.ds, initTextFrame("Hello").toContentFrame())
  )
  
  app.client.onDeliveryAck(proc(convo: Conversation, msgId: string) {.async.} =
    info "DeliveryAck", msgId=msgId
    app.logMsgs.add(LogEntry(level: "info",ts: now(), msg: fmt"Ack:{msgId}"))
  )


#################################################
# Data Management
#################################################

proc addMessage(conv: var ConvoInfo, sender: string, content: string) =

  let now = now()
  conv.messages.add(Message(
    sender: sender,
    content: content,
    timestamp: now
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
      
      var remainingText = m.content
      
      if m.sender == "You":
        tb.setForegroundColor(fgYellow)
      else:
        tb.setForegroundColor(fgGreen)

      if y > yEnd:
          convo.isTooLong = true
          app.logMsgs.add(LogEntry(level: "info",ts: now(), msg: fmt" TOO LONG: {convo.name}"))

          return
      tb.write(x, y, fmt"[{timeStr}] {m.sender}")
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

      var remainingText = m.content

      if m.sender == "You":
        tb.setForegroundColor(fgYellow)
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
      
      tb.write(x, y, fmt"[{timeStr}] {m.sender}")
      y = y - 2

proc drawMsgInput( app: ChatApp, layout: Pane) =
  var tb = app.tb
  drawOutline(tb, layout, fgCyan)


  let inputY = layout.yStart + 2
  let paneStart = layout.xStart

  # Draw input prompt
  tb.write(paneStart + 1, inputY, " > " & app.inputBuffer, fgWhite)

  # Draw cursor
  let cursorX = paneStart + 3 + app.inputBuffer.len
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
  # echo "Drawing modal at ", layout
  tb.setForegroundColor(color)
  tb.setBackgroundColor(bg)
  for x in layout.xStart..<layout.xStart+layout.width:
    for y in layout.yStart..<layout.yStart+layout.height:
      tb.write(x, y, " ", color)

  tb.write(layout.xStart + 2, layout.yStart + 2, "Paste Invite")

  tb.setForegroundColor(fgWhite)
  tb.setBackgroundColor(bgBlack)
  let inputLine = 5

  for i in layout.xStart+3..<layout.xStart+layout.width-3:
    for y in (layout.yStart + inputLine - 1)..<(layout.yStart+inputLine + 2):
      tb.write(i, y, " ")

    # Draw input prompt
  tb.write(layout.xStart+5, layout.yStart+inputLine, "> " & app.inputBuffer)

  # Draw cursor
  let cursorX = layout.xStart+5 + app.inputBuffer.len
  if cursorX < terminalWidth() - 1:
    tb.write(cursorX, layout.yStart+inputLine+2, "_", fgYellow)

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


proc handleInput(app:  ChatApp, key: Key) =
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
        var sc = app.getSelectedConvo()
        sc[].addMessage("You", app.inputBuffer)

        app.inputBuffer = ""
        app.messageScrollOffset = 0 # Auto-scroll to bottom
  of Key.Backspace:
    if app.inputBuffer.len > 0:
      app.inputBuffer.setLen(app.inputBuffer.len - 1)
  of Key.Tab:
    if app.conversations.len > 0:
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
    await sleepAsync(50)
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
    handleInput(app, key)

    if app.isInviteReady:
      discard await app.client.newPrivateConversation(toBundle(app.inputInviteBuffer.strip()).get())
      app.inputInviteBuffer = ""
      app.isInviteReady = false

proc peerWatch(app: ChatApp): Future[void] {.async.} =
  while true:
    await sleepAsync(1000)
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
  var conv1 = ConvoInfo(name: "Alice", messages: @[])
  conv1.addMessage("36Alice", "Hey there! How are you doing?")
  conv1.addMessage("35You", "I'm doing well, thanks! Working on a new project.")
  conv1.addMessage("34Alice", "That sounds exciting! What kind of project?")
  conv1.addMessage("33You", "A terminal-based chat application in Nim!")
  conv1.addMessage("32Alice", "Hey there! How are you doing?")
  conv1.addMessage("31You", "I'm doing well, thanks! Working on a new project.")
  conv1.addMessage("30Alice", "That sounds exciting! What kind of project?")
  conv1.addMessage("29You", "A terminal-based chat application in Nim!")
  conv1.addMessage("28Alice", "Hey there! How are you doing?")
  conv1.addMessage("27You", "I'm doing well, thanks! Working on a new project.")
  conv1.addMessage("26Alice", "That sounds exciting! What kind of project?")
  conv1.addMessage("25You", "A terminal-based chat application in Nim! A terminal-based chat application in Nim! A terminal-based chat application in Nim! A terminal-based chat application in Nim! A terminal-based chat application in Nim! A terminal-based chat application in Nim! A terminal-based chat application in Nim! A terminal-based chat application in Nim! A terminal-based chat application in Nim! A terminal-based chat application in Nim!")
  conv1.addMessage("24Alice", "Hey there! How are you doing?")
  conv1.addMessage("23You", "I'm doing well, thanks! Working on a new project.")
  conv1.addMessage("22Alice", "That sounds exciting! What kind of project?")
  conv1.addMessage("21You", "A terminal-based chat application in Nim!")
  conv1.addMessage("20Alice", "Hey there! How are you doing?")
  conv1.addMessage("19You", "I'm doing well, thanks! Working on a new project.")
  conv1.addMessage("18Alice", "That sounds exciting! What kind of project?")
  conv1.addMessage("17You", "A terminal-based chat application in Nim!")
  conv1.addMessage("16Alice", "Hey there! How are you doing?")
  conv1.addMessage("15You", "I'm doing well, thanks! Working on a new project.")
  conv1.addMessage("14Alice", "That sounds exciting! What kind of project?")
  conv1.addMessage("13You", "A terminal-based chat application in Nim!")
  conv1.addMessage("12Alice", "Hey there! How are you doing?")
  conv1.addMessage("11You", "I'm doing well, thanks! Working on a new project.")
  conv1.addMessage("10Alice", "That sounds exciting! What kind of project?")
  conv1.addMessage("9You", "The system architecture consists of three main components: the client interface, the processing engine, and the data storage layer. Each component communicates through well-defined APIs that ensure scalability and maintainability. The client interface handles user interactions and validates input data before forwarding requests to the processing engine.")
  conv1.addMessage("8Alice", "Hey there! How are you doing?")
  conv1.addMessage("7You", "I'm doing well, thanks! Working on a new project.")
  conv1.addMessage("6Alice", "That sounds exciting! What kind of project?")
  conv1.addMessage("5You", "A terminal-based chat application in Nim!")
  conv1.addMessage("4Alice", "Hey there! How are you doing?")
  conv1.addMessage("3You", "I'm doing well, thanks! Working on a new project.")
  conv1.addMessage("2Alice", "That sounds exciting! What kind of project?")
  conv1.addMessage("1You", "A terminal-based chat application in Nim!")
  app.conversations[conv1.name] = conv1

  var conv2 = ConvoInfo(name: "Bob", messages: @[])
  conv2.addMessage("Bob", "Did you see the game last night?")
  conv2.addMessage("You", "The system architecture consists of three main components: the client interface, the processing engine, and the data storage layer. Each component communicates through well-defined APIs that ensure scalability and maintainability. The client interface handles user interactions and validates input data before forwarding requests to the processing engine")
  conv2.addMessage("Bob", "The home team crushed it! 3-0")
  app.conversations[conv2.name] = conv2

  var conv3 = ConvoInfo(name: "Development Team", messages: @[])
  conv3.addMessage("Sarah", "Morning standup in 10 minutes")
  conv3.addMessage("Mike", "I'll be there. Just finishing up the last bug fix.")
  conv3.addMessage("You", "On my way!")
  conv3.addMessage("Sarah", "Great! Let's review the sprint progress today.")
  app.conversations[conv3.name] = conv3


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