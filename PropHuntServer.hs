{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent (MVar, forkIO, modifyMVar, modifyMVar_, newMVar, readMVar, threadDelay)
import Control.Exception (finally)
import Control.Monad (forever, forM_, void)
import Data.Aeson
import Data.Aeson.Types (parseMaybe)
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as M
import Network.WebSockets
import PropHuntv2

data Server = Server
  { serverGame :: Game
  , serverClients :: M.Map PlayerId Connection
  }

main :: IO ()
main = do
  state <- newMVar (Server (startLobby 2026 []) M.empty)
  void (forkIO (tickLoop state))
  putStrLn "Prop Hunt server listening on ws://0.0.0.0:9160"
  runServer "0.0.0.0" 9160 (application state)

tickLoop :: MVar Server -> IO ()
tickLoop state = forever $ do
  threadDelay (130 * 1000)
  broadcastState state $ \server -> server { serverGame = stepGame (serverGame server) }

application :: MVar Server -> PendingConnection -> IO ()
application state pending = do
  connection <- acceptRequest pending
  playerId <- joinPlayer state connection
  sendState state playerId connection
  let disconnect = modifyMVar_ state $ \server ->
        pure server { serverClients = M.delete playerId (serverClients server) }
  (forever (receiveDataMessage connection >>= handleMessage state playerId connection))
    `finally` disconnect

joinPlayer :: MVar Server -> Connection -> IO PlayerId
joinPlayer state connection = modifyMVar state $ \server -> do
  let used = M.keys (serverClients server)
      newId = PlayerId (1 + maximum (0 : map playerIdToInt used))
      game' = addHumanPlayer newId (serverGame server)
  pure (server { serverGame = game'
               , serverClients = M.insert newId connection (serverClients server) }, newId)

handleMessage :: MVar Server -> PlayerId -> Connection -> DataMessage -> IO ()
handleMessage state playerId connection message = case message of
  Text payload _ -> case eitherDecode payload of
    Left err -> sendTextData connection (encode (object ["type" .= ("error" :: String), "message" .= err]))
    Right value -> case parseAction value of
      Nothing -> sendTextData connection (encode (object ["type" .= ("error" :: String), "message" .= ("unknown action" :: String)]))
      Just action -> do
        modifyMVar_ state $ \server ->
          pure server { serverGame = applyAction (PlayerAction playerId action) (serverGame server) }
        sendState state playerId connection
  Binary _ -> pure ()

parseAction :: Value -> Maybe Act
parseAction = parseMaybe $ withObject "action" $ \o -> do
  actionType <- o .:? "action" .!= ("idle" :: String)
  case actionType of
    "move" -> Move <$> ((,) <$> o .:? "dx" .!= 0 <*> o .:? "dy" .!= 0)
    "morph" -> pure Morph
    "swapMorph" -> pure SwapMorph
    "duplicate" -> pure Duplicate
    "revert" -> pure Revert
    "attack" -> pure Attack
    "vote" -> Vote <$> o .: "map"
    _ -> pure Idle

broadcastState :: MVar Server -> (Server -> Server) -> IO ()
broadcastState state update = do
  clients <- modifyMVar state $ \server ->
    let updated = update server in pure (updated, serverClients updated)
  current <- readMVar state
  forM_ (M.toList clients) $ \(playerId, connection) ->
    sendTextData connection (encodeState playerId (serverGame current))

sendState :: MVar Server -> PlayerId -> Connection -> IO ()
sendState state playerId connection = do
  server <- readMVar state
  sendTextData connection (encodeState playerId (serverGame server))

encodeState :: PlayerId -> Game -> BL.ByteString
encodeState viewerId game = encode $ object
  [ "type" .= ("state" :: String)
  , "playerId" .= playerIdToInt viewerId
  , "phase" .= show (phase game)
  , "tick" .= tick game
  , "timeLimit" .= timeLimit game
  , "note" .= note game
  , "players" .= map encodePlayer (visiblePlayers viewerId game)
  , "fakes" .= map encodeFake (visibleFakes viewerId game)
  ]
  where
    encodePlayer p = object
      [ "id" .= playerIdToInt (pvId p)
      , "role" .= show (pvRole p)
      , "pos" .= posValue (pvPos p)
      , "form" .= fmap propName (pvForm p)
      , "alive" .= pvAlive p
      ]
    encodeFake f = object
      [ "owner" .= playerIdToInt (fpOwner f)
      , "prop" .= propName (fpProp f)
      , "pos" .= posValue (fpPos f)
      ]
    posValue (x, y) = [toJSON x, toJSON y]
