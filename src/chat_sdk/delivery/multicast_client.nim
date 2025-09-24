import std/net
import strformat
import chronos
import posix
import tables
import hashes


#################################################
# Multicast Utils
#################################################

const MSG_LEN = 1024
const MCAST_GRP = "239.18.0.10"
const MCAST_PORT = 18010


# These are the MacOS specific values for the multicast socket options names
const IP_ADD_MEMBERSHIP = 12
const IP_DROP_MEMBERSHIP = 13

type
  ip_mreq {.pure, final.} = object
    imr_multiaddr*: InAddrT
    imr_interface*: InAddrT

# This function creates the posix struct needed to join a multicast group.
# It is not defined in chronos so we define it here.
proc joinMulticast(socket: AsyncFD, groupAddr: string) =

  let mreq = ip_mreq(
    imr_multiaddr: inet_addr(groupAddr),
    imr_interface: INADDR_ANY  # INADDR_ANY - any interface
  )

  socket.setSockOpt2(IPPROTO_IP, IP_ADD_MEMBERSHIP, addr mreq, sizeof(mreq)).isOkOr:
    echo "Failed to join multicast group"
    quit(1) # TODO: Fail gracefully
  echo "Joined multicast group ", groupAddr

#################################################
# Types
#################################################

# TODO
type WapEnvelopeV1* = string

type MulticastConfig* = object
  mcast_port: int
  mcast_grp_start: string
  mcast_grp_count: int


proc DefaultConfig*(): MulticastConfig =
  result = MulticastConfig(
    mcast_port: 18010,
    mcast_grp_start: "239.18.0.10",
    mcast_grp_count: 5,
  )


type 
  MulticastClient* = object
    cfg: MulticastConfig
    sendSocket*: DatagramTransport
    listenSocket*: DatagramTransport

#################################################
# Accessors and Getters
#################################################


proc getListenAddress*(cfg: MulticastConfig): TransportAddress =
  result = initTAddress(fmt"0.0.0.0:{cfg.mcast_port}")

proc getBaseAddress*(cfg: MulticastConfig): TransportAddress =
  result = initTAddress(fmt"{cfg.mcast_grp_start}:{cfg.mcast_port}")

proc offsetAddress*(address: TransportAddress, offset: uint8): TransportAddress =
  var newAddress = address
  
  case newAddress.family
  of AddressFamily.IPv4:
    newAddress.address_v4[3] += offset # TODO: handle octet overflow
    return newAddress
  else:
    echo "currently only supports ipv4"


# TODO: Better name, theres no disitinction between group and TAddr
proc getGroupForDeliveryAddress*(client: MulticastClient, delivery_address: string): TransportAddress =
  var offset = hash(delivery_address) mod client.cfg.mcast_grp_count
  var offsetU8 = cast[uint8](offset) # TODO: Unsafe cast
  result = getBaseAddress(client.cfg).offsetAddress(offsetU8) 


#################################################
# Payload Handling
#################################################

proc inboundMessageHandler(transp: DatagramTransport,
               raddr: TransportAddress): Future[void] {.async: (raises: []).} =

  echo "Received payload"
  discard

#################################################
# Message Sending and Receiving
#################################################

proc subscribe*(client: MulticastClient, delivery_address: string): Future[void] {.async.} =
  let group = client.getGroupForDeliveryAddress(delivery_address).toIpAddress()
  joinMulticast(client.listenSocket.fd, $group)


proc sendPayload*(client: MulticastClient, delivery_address: string, env: WapEnvelopeV1): Future[void] {.async.} =

  var payload = env

  let group = client.getGroupForDeliveryAddress(delivery_address)

  await client.sendSocket.sendTo(group, addr payload[0], len(payload))
  echo "Sent message to ", group


#################################################
# Object Initialization
#################################################

proc initMulticastClient*(cfg: MulticastConfig): MulticastClient =

  let listen_addr = cfg.getListenAddress()

  let sendSocket = newDatagramTransport(inboundMessageHandler)
  let listenSocket = newDatagramTransport(inboundMessageHandler, local=listen_addr)

  result = MulticastClient(
    cfg: cfg,
    sendSocket: sendSocket,
    listenSocket: listenSocket
  )

proc main() {.async.} =


  let cfg = DefaultConfig()
  let m = initMulticastClient(cfg)
#   asyncSpawn m.start()

  await m.subscribe("cats")
  await sleepAsync(1000)
  await m.sendPayload("any_address", "Hello Multicast Group")
  await sleepAsync(1000)
  echo "Hello Multicast"





