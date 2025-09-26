import std/parseopt
import illwill
import times

#################################################
# Command Line Args
#################################################

type CmdArgs* = object
  username*: string
  invite*: string

proc getCmdArgs*(): CmdArgs =
  var username = ""
  var invite = ""
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      discard
    of cmdLongOption, cmdShortOption:
      case key
      of "name", "n":
        username = val
      of "invite", "i":
        invite = val
    of cmdEnd:
      break
  if username == "":
    username = "<anonymous>"

  result = CmdArgs(username: username, invite:invite)


#################################################
# Utils
#################################################

proc getIdColor*(id: string): BackgroundColor  = 
    var i = ord(id[0])


    let colors = @[bgCyan,
      bgGreen,
      bgMagenta,         
      bgRed,                      
      bgYellow,                             
      bgBlue    
    ]     

    return colors[i mod colors.len]      

proc toStr*(ts: DateTime): string =
  ts.format("HH:mm:ss")