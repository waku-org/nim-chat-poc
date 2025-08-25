# Nim Chat POC

This is a technical proof of consuming the [chat_proto](https://github.com/waku-org/chat_proto/tree/base_types?tab=readme-ov-file) in nim.


## Message Flow

To establish a secure conversation, Saro and Raya need to:
1. Exchange key material
2. Agree on a secret key, and location to communicate

For this technical proof, recipient identity keys are exchanged out of bound via an invite link. More complex identity systems will be explored in the future. 

Key derivation and message framing is defined by Inbox spec


 ```mermaid
sequenceDiagram
    actor S as Saro 
    participant SI as Saro Inbox 
    participant C as Convo 
    participant RI as Raya Inbox 
    actor R as Raya 


    Note over SI,RI: All clients subscribe to their default Inbox

    SI ->> S: Subscribe
    RI ->> R: Subscribe

    Note over R: Key Information is exchanged OOB 
    
    Note over S: Conversation is created
    C ->> S : Subscribe
    S ->> RI : Send Invite `I1`
    S ->> C : Send Message `M1`

    RI --) R : Recv `I1`
    Note over R: Conversation is joined
    C ->> R : Subscribe
    C --) R: Recv `M1`

    R ->> C: Send M2
    C -->> S: Recv M2
 ```

## Running



```
# Run the default binary
nimble run
```


## Limitations

1. `.proto` files are included in this repo due to complications in importing nested packages using `?subdir=`. Once resolved there will be a single definition of protocol types.
1. Currently messages are not sent over the wire. They are simulated using a `TransportMessage`.


## License

[MIT](https://choosealicense.com/licenses/mit/)