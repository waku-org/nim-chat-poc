import client
import chronicles
import proto_types

proc log(transport_message: TransportMessage) =
  ## Log the transport message
  info "Transport Message:", topic = transport_message.topic,
      payload = transport_message.payload

proc demo() =

  # Initalize Clients
  var saro = initClient("Saro")
  var raya = initClient("Raya")

  # # Exchange Contact Info
  let raya_bundle = raya.createIntroBundle()

  # Create Conversation
  let invite = saro.handleIntro(raya_bundle)
  invite.log()
  let msgs = raya.recv(invite)

  # raya.convos()[0].sendText("Hello Saro, this is Raya!")


when isMainModule:
  echo("Starting ChatPOC...")

  try:
    demo()
  except Exception as e:
    error "Crashed ", error = e.msg

  echo("Finished...")
