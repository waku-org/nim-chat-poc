import illwill


type
  Pane* = object
    xStart*: int
    yStart*: int
    width*: int
    height*: int

proc getPanes*(): seq[Pane] =

  let statusBarHeight = 6
  let convoWidth = 40
  let inboxHeight = 5
  let footerHeight = 14
  let modalXOffset = 10
  let modalHeight = 10

  result = @[]
  let statusBar = Pane(
    xStart: 0,
    yStart: 0,
    width: terminalWidth(),
    height: statusBarHeight
  )
  result.add(statusBar)

  let convoPane = Pane(
    xStart: 0,
    yStart: statusBar.yStart + statusBar.height,
    width: convoWidth,
    height: terminalHeight() - statusBar.height - footerHeight - 1
  )
  result.add(convoPane)


  let msgPane = Pane(
    xStart: convoPane.width,
    yStart: statusBar.yStart + statusBar.height,
    width: terminalWidth() - convoPane.width,
    height: convoPane.height - inboxHeight
  )
  result.add(msgPane)

  let msgInputPane = Pane(
    xStart: convoPane.width,
    yStart: msgPane.yStart + msgPane.height,
    width: msgPane.width,
    height: inboxHeight
  )
  result.add(msgInputPane)

  let footerPane = Pane(
    xStart: 0,
    yStart: convoPane.yStart + convoPane.height,
    width: int(terminalWidth()),
    height: footerHeight
  )
  result.add(footerPane)


  let modalPane = Pane(
    xStart: modalXOffset,
    yStart: int(terminalHeight()/2 - modalHeight/2),
    width: int(terminalWidth() - 2*modalXOffset),
    height: int(modalHeight)
  )
  result.add(modalPane)


proc offsetPane(pane: Pane): Pane =
  result = Pane(
    xStart: pane.xStart ,
    yStart: pane.yStart + 1,
    width: pane.width ,
    height: pane.height - 2
  )
