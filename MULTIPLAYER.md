# Multiplayer deployment

## Local server

```powershell
cabal build prophunt-server
cabal exec prophunt-server
```

The server listens on `0.0.0.0:9160`. A browser connects with WebSocket to:

```text
ws://SERVER_IP:9160
```

## Internet deployment

Deploy the executable to a VPS or cloud VM, allow TCP port `9160`, and put it behind a TLS reverse proxy for production:

```text
wss://game.example.com/ws
```

The server is authoritative. Clients send actions only:

```json
{"action":"move","dx":1,"dy":0}
{"action":"morph"}
{"action":"revert"}
{"action":"attack"}
```

The server returns `state` messages containing the player's visible players and fake props. Hidden hiders are omitted by `visiblePlayers`, so the client cannot discover them by inspecting the full game state.

The frontend must use the WebSocket URL instead of its local simulation before players can join from different networks. The existing frontend folder is not present in the current workspace snapshot, so that client-side wiring remains a separate step.
