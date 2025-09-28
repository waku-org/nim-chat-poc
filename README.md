# Nim Chat POC

This is the technical proof of a modular e2ee chat protocol using Waku. You can find discussion and details [here](https://github.com/waku-org/specs/pull/73)

See [EchoBot](./examples/bot_echo.nim) for a minimal client side usage example.


## Quick Start

```
# Build Dependencies and link libraries
make update

# Build executables
make all

# Run the Text Interface
./build/tui --name=<unique_id>
```

## Details

### Message Flow

To establish a secure conversation, Saro and Raya need to:
1. Find each others identityKeys
2. Agree on a secret key, and location to communicate

For this technical proof, recipient identity keys are exchanged out of bound via an invite link. More complex identity systems will be explored in the future. ..


 ```mermaid
sequenceDiagram
    participant S as Saro
    participant R as Raya

    Note over R,S: Discovery
    R -->> S: Send Invite Link via established channel

    Note over R,S: Initialization
    S ->> R: PrivateV1 Invite

    Note over R,S: Operation
    loop
        par
            R->> S: Send Message
        and
            S->> R: Send Message
        end
    end
 ```


## Limitations

1. `.proto` files are included in this repo due to complications in importing nested packages using `?subdir=`. Once resolved there will be a single definition of protocol types.
1. Messages are sent using waku, however wakunode discovery has not been implemented. As a stopgap a manual discovery process based on staticpeers is used.


## License

[MIT](https://choosealicense.com/licenses/mit/)