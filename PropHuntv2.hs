module PropHuntv2
  ( Pos, Prop(..), Role(..), Control(..), Mode(..), Act(..), PlayerId(..)
  , Player(..), FakeProp(..), World(..), Phase(..), Game(..), PlayerAction(..)
  , maps, worlds
  , startLobby, startLobbyWithPlayers, startGame, stepGame, applyAction
  , addHumanPlayer, castVote, chooseMap, visiblePlayers, visibleFakes, PlayerView(..)
  , visibleTo, knifeHits, propName
  , findPlayer, playerIdFromInt, playerIdToInt
  , playerSpeed, hunterSpeed, knifeHitbox, knifeCooldown, swapMorphCooldown
  , timeBonusTicks, lobbyTicks, prepareTicks, sightRange, bushRevealRange
  , hunterSlots, minHiderSlots, maxHiderSlots
  , randomizeRoles
  ) where

import Data.List (minimumBy, nub)
import Data.Ord (comparing)
import qualified Data.Map.Strict as M
import qualified Data.Set as S

type Pos = (Int, Int)

data Prop = Crate | Barrel | Plant | Stool | Vase | Lamp | Sack | Rock
  deriving (Eq, Ord, Show)

data Role = Hunter | Hider
  deriving (Eq, Show)

data Control = Human | Bot
  deriving (Eq, Show)

data Mode = Patrol Pos | Chase Pos | Search Int Pos
  deriving (Eq, Show)

data Act
  = Move Pos
  | Morph
  | SwapMorph
  | Duplicate
  | Revert
  | Attack
  | Vote Int
  | Idle
  deriving (Eq, Show)

newtype PlayerId = PlayerId Int
  deriving (Eq, Ord, Show)

data PlayerAction = PlayerAction PlayerId Act
  deriving (Eq, Show)

data FakeProp = FakeProp
  { fpOwner :: PlayerId
  , fpProp  :: Prop
  , fpPos   :: Pos
  } deriving (Eq, Show)

data Player = Player
  { pId       :: PlayerId
  , pRole     :: Role
  , pControl  :: Control
  , pPos      :: Pos
  , pForm     :: Maybe Prop
  , pMoved    :: Bool
  , pMode     :: Mode
  , pKnifeCd  :: Int
  , pSwapCd   :: Int
  , pFakeCount :: Int
  , pAlive    :: Bool
  , pNote     :: String
  } deriving (Eq, Show)

data World = World
  { wName   :: String
  , wWalls  :: S.Set Pos
  , wProps  :: M.Map Pos Prop
  , wBushes :: S.Set Pos
  , wFloors :: [Pos]
  , wNear   :: [Pos]
  , wSize   :: Pos
  , wPlayer :: Pos
  , wSeeker :: Pos
  } deriving (Eq, Show)

data Phase
  = Lobby
  | HiderPrepare
  | Playing
  | GameOver
  deriving (Eq, Show)

data Game = Game
  { world          :: World
  , mapNo          :: Int
  , phase          :: Phase
  , phaseTicks     :: Int
  , players        :: [Player]
  , mapOptions     :: [Int]
  , mapVotes       :: M.Map PlayerId Int
  , tick            :: Int
  , rng             :: Int
  , over            :: Maybe Bool
  , note            :: String
  , whistle         :: Int
  , bell            :: Bool
  , fakeProps       :: [FakeProp]
  , timeLimit       :: Int
  , hunterStreak    :: M.Map PlayerId Int
  } deriving (Eq, Show)

-- Game constants.
tickMs :: Int
tickMs = 130

matchSecs :: Int
matchSecs = 480

viewR :: Int
viewR = 6

sightRange :: Int
sightRange = viewR

bushRevealRange :: Int
bushRevealRange = 2

playerSpeed, hunterSpeed :: Int
playerSpeed = 1
hunterSpeed = 2

knifeHitbox :: Double
knifeHitbox = 1.5

knifeCooldown :: Int
knifeCooldown = 8

swapMorphCooldown :: Int
swapMorphCooldown = 35 * 1000 `div` tickMs

timeBonusTicks :: Int
timeBonusTicks = 20 * 1000 `div` tickMs

lobbyTicks, prepareTicks :: Int
lobbyTicks = 120 * 1000 `div` tickMs
prepareTicks = 20 * 1000 `div` tickMs

hunterSlots, minHiderSlots, maxHiderSlots :: Int
hunterSlots = 3
minHiderSlots = 8
maxHiderSlots = 12

winTicks :: Int
winTicks = matchSecs * 1000 `div` tickMs

-- Pseudo-random generator.
nextRng :: Int -> Int
nextRng s = (s * 1103515245 + 12345) `mod` 2147483648

roll :: Int -> Int -> Bool
roll r pct = (r `div` 65536) `mod` 100 < pct

pick :: Int -> [a] -> a
pick r xs = xs !! ((r `div` 65536) `mod` length xs)

playerIdFromInt :: Int -> PlayerId
playerIdFromInt = PlayerId

playerIdToInt :: PlayerId -> Int
playerIdToInt (PlayerId n) = n

maps :: [(String, [String])]
maps =
  [ ( "Kho hàng"
    , [ "########################################################"
      , "#.................B..............KKK...................#"
      , "#.LL..L...........B..................K.....K.........X.#"
      , "#...L.LSS.....B...B.......K.......KK...................#"
      , "#...SLSS...................KKK.............K.KK........#"
      , "#..############.....############.....############.S.S..#"
      , "#....KK.....K...K................................S.S...#"
      , "#....K..K....KKK..................LL............S......#"
      , "#.....K.KK...........................LL................#"
      , "#.................................L..LL................#"
      , "#....B.O############.....############.....###########..#"
      , "#..BKKKO..B........S.S.....OO.OO.......................#"
      , "#.BBKKOO.BB.......SSSOO.O..LL.........B.KKK............#"
      , "#...KK.B.BBB.......BOB..OLL............BKK.K...........#"
      , "#...................BBO.OLL..........B.................#"
      , "#..############.....############K....############......#"
      , "#....SS..OOKKOK..KKK...O.KK.KKKKK...........K..........#"
      , "#.........OKOO.....K.K...OK.KKK.K..........K......K..K.#"
      , "#....S.S.BB........KK..KKKO...............K......K...K.#"
      , "#......BBB..........KK..K..........................K.K.#"
      , "#.......############..K..############.....###########..#"
      , "#...........BK.B...K...........SS......................#"
      , "#........K.KK..BB.............S.............KKK.L.LLL..#"
      , "#.....OOBOKKB...B......O......S........................#"
      , "#.....OO.OOO........S.OOS.......PP...............K.....#"
      , "#.@....O.OBO.........O.SO.......P.............O.OK.....#"
      , "#.......................S...................O.K.OK.....#"
      , "########################################################" ] )
  , ( "Biệt thự"
    , [ "########################################################"
      , "#.................#PP................#..B..............#"
      , "#.................#KPPP........B..BB.#...B...........X.#"
      , "#.............S..S#KKKK.......P..BBB.#O..BB............#"
      , "#...K..........S..#...K......P...PBV.OV................#"
      , "#.......K.....S..S#................VVOV..P.PP..........#"
      , "#...KK.K..................###....SS..#...P.P...SSSS....#"
      , "#.......LL................###...B.B.S#....P.P###S.SO...#"
      , "#L..L..L..........#.......###...B....#.......###...S...#"
      , "#L...L..OS.OS.....#.........L...BB...#.......###O.VOV.V#"
      , "#.L......O..S.....#..........LL.L....#BBB..........V..V#"
      , "#........SSS................L.L......#B.......VVVVV....#"
      , "#.................#....L..L..........#.........VVVV.VV.#"
      , "#.................#.....LLLL.........#.........VVVV...V#"
      , "########..#################L.################..#########"
      , "#...PK.KS.........#.V................#.............S...#"
      , "#PP.....S.........#....VV............#....OO.OSS.....S.#"
      , "#....K...S.......S#OOOVOV..........SS#S..........VVV.V.#"
      , "#....KKKVV.SS.LS..#..V.O.............#S...OOOOLL.SLVVVL#"
      , "#...KVV.KV.......LS.SO......###....S.#S.....###.LVVOLVL#"
      , "#....VV.###......L..........###......#......###...OOL..#"
      , "#.......###.......#.........###..................VVOVV.#"
      , "#.......###.......#.............O........P..P..........#"
      , "#.................#...........O......#...P.VP.V........#"
      , "#.............B...#.S..........OV....#..P.PP...........#"
      , "#..@........BBB..S#..S...........VVV.#.....VV.V........#"
      , "#............B....#.SS............V..#.................#"
      , "########################################################" ] )
  , ( "Vườn cây"
    , [ "########################################################"
      , "#.........PP...........................................#"
      , "#..LL..PP.........RPPP.P.............................X.#"
      , "#..OL..##............RPP.....P..P########O#.#..........#"
      , "#.LOO.O##P.P.....RRRRR..........O.O.RR#RO##.#....L.....#"
      , "#.....###PPP......#R...#....#.P...O...#RO##.##.LL......#"
      , "#.....###PPS.S...R#..R.#.R..#..OOP..R.#.###.##.........#"
      , "#.....###....S...P#P...#RR.R#O.PP.P...#.###.##.........#"
      , "#...#.###..P...S.P#P...##R.R#O.OO.....#.######.........#"
      , "#...#.##..P..P....#....##...#O.....R....######.PR..R...#"
      , "#..L#L###########......##...#######R.RR.######.RR.PR..R#"
      , "#...#..L.........R.RRR.##..R...#....R...##P###.PPPR..RR#"
      , "#...#.LL.........P.RPR.##RR....#......P.P#.##.PP.......#"
      , "#...#............P.PPLLRR..R...#.....P.....##..P.......#"
      , "#...#.RR#R..........P..LLL.L...#...SSSSP.#.##P...V.....#"
      , "#....R..#R#..........L.LLL.....#..S#####.#.##R..V.RR...#"
      , "#....R.R#.#.............LL.L.#.#...PPP...#.R#..RS.RRV..#"
      , "#..P....#.#.........######.L.#.#...PPPLL.#.R#.S....RR..#"
      , "#P.PP.P.#.#..P.B.........BLL.#........LLL#...S..SS.....#"
      , "#..PP.PR#.#P.BPBB.......BL.LL#......VLL##########......#"
      , "#PPPP..R#.#BPPB########BBB...#...VV.##########......RR.#"
      , "#P.P.P..#.#..B...............#.#####V...R...........R..#"
      , "#.....S...#...BB..PPOP.O....#########.P...RR#######R...#"
      , "#....S.SSS#........PP..O......B.....P.....RR...P...R..R#"
      , "#..........#####VVPPPPP.........BBPP.........PPSP....RR#"
      , "#.@...........V....PP..P........#####........SS.S...R..#"
      , "#................................................S.....#"
      , "########################################################" ] )
  , ( "Mê cung"
    , [ "########################################################"
      , "#..#...OO#.....#....................K........KKK#K...X.#"
      , "#..#.....#..O..#.................KK...RRRRR.KKK.#K.....#"
      , "#..#..#.O#O.#O.#..#######..#PP#.O#O.####RR####..#..#..##"
      , "#.B#B.#..#..#.....#.....RR.P..#..#.O#........#.B#B.#..##"
      , "#..#B.#..#..#.B.B.#....RR..P.P#PS#..#.O.O....#.B#BB#..##"
      , "#.B#B.#..#..#..####..####..#..#S.#S.####..#..#..####..##"
      , "#.....#.....#.BB.....#....BB..#R.#R...O...#K.K...OB..B##"
      , "#.....#.....#.......R#R....B..#R.#R......K#....O......##"
      , "#######..#######..#.R#R.#..#..#..#R.#..#.K#B.####O.#BB##"
      , "#............B.B..R..#.....#..#..#.....#..#B....#K.#..##"
      , "#..............BBB...#.....#..#..#.....#.B#.OOO.#..#.K##"
      , "#OO#O.#..##########..#..#..#..#..#######..#.O#O.#.K#.O##"
      , "#O.#O..........#.....#O.O........#.....#....B#B.#....O##"
      , "#O.#O..........#.....#O..........#.....#....B#BB#..O.O##"
      , "#..##########..#O.#..#######..####..#..#..#.B#######..##"
      , "#..#..BB....PP.#O.#O.....P.#P.............#........#..##"
      , "#..#.BBB..P....#O.#O.....P.#P.......K.O...#....BBB.#..##"
      , "#..#.B##########K.#######..#P.#..#KS#.S#.O####..#BV#.L##"
      , "#........#..#.KKK.KKKK..#.KKK...K..S#.SS.OOB.BB.VKK#..##"
      , "#.......V#.V#...........#...........#SSS.RRB.BB..VK#.L##"
      , "#..#..#..#..#..##########..#..#P.#.S#SS####..#..####.S##"
      , "#........#.....#K...K...#..#..P.P#...KP..P#.....#.....##"
      , "#........#.....#..KK....#..#.....#......PP#.....#..SS.##"
      , "#..####..#######.K#..#..#..#BB####.O#.P#P.####.B#B.#####"
      , "#...................V.VVV.B#B.B....O#.OO.....#.BB.....##"
      , "#@.........................#........#........#.B......##"
      , "########################################################" ] )
  , ( "Đấu trường"
    , [ "########################################################"
      , "#.........RR...O.......................................#"
      , "#K......RRRR.O.OO...K...............................X..#"
      , "#..KK.....SS......K.KK.................................#"
      , "#.......##################...B##################.......#"
      , "#.......#............O...RR..R.BBB...........KK#.......#"
      , "#.......#...............K.KRRB.B.B..........KKK#.......#"
      , "#..BBRB.#..........OO.K...R.................K..#B.BB...#"
      , "#..SSBB.#.....##......KKOOK..........RR.##.....#.......#"
      , "#.RRS.SB#.....##.......O.OO....LLL.L..R.##.....#.......#"
      , "#.......#..............O..OKK.KK..PK.RR..RR.R..#.......#"
      , "#.......#.................##.....P.......R.RR..#.......#"
      , "#LL..L....................##..KPPKK.K..PPR...R.........#"
      , "#...L........KKKK...####........####..........L.L.L....#"
      , "#....LO..OO.B..BK...####........####...PP.....LL.......#"
      , "#.......OO.KB.BBK..SRS..R.......................LL.....#"
      , "#.....OO#...K..BB....SR...##......L.L..........#L.L.L..#"
      , "#.......#K....KK..SSRS.R..##.....LL.........PPP#L......#"
      , "#.......#...K.##L.L...........S..LLL..OO##.....#L......#"
      , "#.......#..K..##O..OO.....S...S......O..##.....#.......#"
      , "#.......#.B..B.LOLLOO.....S...............K...L#.LL....#"
      , "#.......#.B.................L.LL.......KK.B....#L......#"
      , "#.......#....B................L............BB.L#LLL....#"
      , "#.......##################..LL##################.......#"
      , "#...........R.RR.OOO.OK......S.........................#"
      , "#..@.......KR.OR.....KKKKK..P...S......................#"
      , "#.............ROOOOO.......P..P..S.....................#"
      , "########################################################" ] )
  , ( "Hầm rượu"
    , [ "########################################################"
      , "#.........O......................O...L.................#"
      , "#.......OK............O......OOO.....L...............X.#"
      , "#.......OKKKKK.KOO.O.O..OO...OO..O.....L...............#"
      , "#.OO..OLKKKK..KKK..O.O.V......V..OO....................#"
      , "#.OO.....LLK..KKKKO...VVV...KKV.V.....V................#"
      , "#......L............V.......KK..K.VV...................#"
      , "########################...######################......#"
      , "#.......B.............OO..............OOOOOOO..........#"
      , "#OOO.BB..B..........OOOO..............O.OOOOO..........#"
      , "#....OB.BB..........OOO.O.............O.O.O............#"
      , "#O..OO.............................O......LL...........#"
      , "#OOOO...................O..OOO..O..OO.....L..L.........#"
      , "#.O.O...................OOOOOO...O.OO......L.LL........#"
      , "#...O..#################O.O#############################"
      , "#..........OO..VVL.....O..O....L..KKK...KKKKV..O..O....#"
      , "#........OO.O..VVLVV....O...OL..L.K.K.K.BO..BV.O..OVV..#"
      , "#.........O.O.............OO.LL.........O..OOV.V.VV.V..#"
      , "#....V.............VVVV..B.K.OK.V.......OB.B...........#"
      , "#V.VBV.V.V..........V..V.B...K..V.V....................#"
      , "#....BVB...........V.......B.BK........................#"
      , "########################..V######################......#"
      , "#........V..KKVKV.B.BBKKVKKVK.....LL.LL......BB........#"
      , "#...........KVV.K....BK.KK.V.O.....L.L........B........#"
      , "#.......VVV.V........KK.K.....OO.O.....................#"
      , "#.@.............................O......................#"
      , "#......................................................#"
      , "########################################################" ] )
  , ( "Quán ăn"
    , [ "########################################################"
      , "#...............................................SS.....#"
      , "#...........SSS................................SSSS..X.#"
      , "#...SSS.....S.S..............V..VVO.O..........S.......#"
      , "#..SS....S.S......S.........S....VOO..SS...............#"
      , "#..S.S.S##.......S##S......S##.VOO..O.##.......S##S....#"
      , "#......S##S.....LS##.......S##V..V...S##.......S##S....#"
      , "#.................LL........SVVV.......S...............#"
      , "######..........L..LL..........VV................S.SS..#"
      , "#.............................BBB...PP..............S..#"
      , "#..................S........SB.SS...P..S.........S.....#"
      , "#....VVS##S......S##S......S##..B...PS##........##S....#"
      , "#.....VV##........##.......S##S.OS.S..##S....L..##S....#"
      , "#....V.VSS.........S............O.....S.......L.SS.....#"
      , "#..............................O.O...........LLLLL.....#"
      , "#................................................S.....#"
      , "#.......S..........S........SS........S.......S.SS...V.#"
      , "#.......##....LLLL##S.......##.......S##......S.##...V.#"
      , "#......S##S...L...##S.......##.......S##.......S##S..V.#"
      , "#.......S.V....LL.S.........SS........S..........S.....#"
      , "#....S.S...V..........SS........................S.######"
      , "#.....SS.VV........S...S...........................S...#"
      , "#..S.SS...........S.........S.......VVVS........S.S....#"
      , "#......S##S......S##L..L....##S....BVS##.......S##.....#"
      , "#......S##...B....##..LL....##..B.VVBS##........##S....#"
      , "#.@......S...B..BBSS.L......SS........S.........SS.....#"
      , "#............B..BB.....................................#"
      , "########################################################" ] )
  , ( "Chữ thập"
    , [ "########################################################"
      , "#######################..........##################...##"
      , "##................OO..#..........#........KK.B......X.##"
      , "##..K........V.VOVOOO.#..........#......K.K..B.BOO....##"
      , "##.KK..........V.V....#..........#............BBB.....##"
      , "##KKK........V.....OO..........R................O.O..K##"
      , "##RRR.........SSO..O...........................KR.R.RR##"
      , "##RRR..........S..O............R...R..........KR..R.R.##"
      , "##.........SSSSO.OO...#..........#............KR.RRRR.##"
      , "##.LL.LRR.............#..K.K.....#...............B....##"
      , "##.LR..L..............#.....K....#............BB......##"
      , "##########...##########S..##.##..##########.S.##########"
      , "#.....KKK....R.....SSS.............BBBB....PS.SP.......#"
      , "#..........RRB...B.......BB.BRRV...VPPPPP..P.....POL.L.#"
      , "#......BB.BR.RRB.B........RRRRR.V....PPP.P....POOOOLLLL#"
      , "#.......B.BB..B...........##.##....P.PPP...............#"
      , "##########B..##########..P......S##########...##########"
      , "##KK.............V...P#.PP...P..S#S.S.................##"
      , "##.KKB.B.BKK...V.VV..P#PPPPP.P..S#S...................##"
      , "##.KK.RBR.KO..KVVKV...#.....PP...#.............K.K....##"
      , "##....RB...O....KK..SS........SSSSS...........K..KK...##"
      , "##........O..K.K..............R.S.S.......K.KK...BB...##"
      , "##...............S.S.S.....R.R.............K.KKS..B...##"
      , "##................O...#.......RR.#.....K.K.....BB.BB..##"
      , "##.............O..O...#..........#......K......B..BB.K##"
      , "##.@..................#..........#.......KKK....BKK...##"
      , "##...##################..........#######################"
      , "########################################################" ] )
  , ( "Vòng xoáy"
    , [ "########################################################"
      , "#...........LL.LL.P....................................#"
      , "#.....VVV.V.........P.P..............................X.#"
      , "#.S#######################O.K#######################...#"
      , "#.S#S.................O.OOBBB..VVVVVLLL.........K...#..#"
      , "#.S#OO.LLLO..OO.........OO.BBB....VVK.LLLV.VV.K...RR#R.#"
      , "#.O#...LL....OO.................V...........VV...RR.#..#"
      , "#.P#PPOL########################################....#..#"
      , "#..#PP..#......KK.....V...VVV.V........P.......#....#..#"
      , "#..#.PP.#......KK.VOO..O....V..........P.P.....#....#..#"
      , "#.K#.K..#.........VVOOOO..V...............L.L.L#P...#..#"
      , "#.K#...L#....#######################...####..LR#RPP.#..#"
      , "#..#K..L#....#......PP.PPPP...............#L..R#....#..#"
      , "#.....L.#..............PPPPP....KKKK..L.L.#RR.......#..#"
      , "#.......#..............SS..O....RRRR...LL.#RRR......#..#"
      , "#..#....#....#........SSOO.......RRR..L...#....#....#..#"
      , "#..#....#....##############################....#.B.B#..#"
      , "#..#....#......PP.P............................#....#..#"
      , "#..#...V#.V.KKKRP..P..LL..RRR..................#.B.K#..#"
      , "#..#VV..#V...KKKRR...L...RR....................#.K..#..#"
      , "#..#VV.V##.VK###################################KBB.#..#"
      , "#..#PL..P..................P.P.PS...........L...BBB.#..#"
      , "#.L#...................KKK.P...P..SS....LLLLL.....B.#..#"
      , "#..#.LLP...............K.....P...S..................#..#"
      , "#...#################################################P.#"
      , "#.@....................S.SS...K...K................P...#"
      , "#................V.V............K.................P....#"
      , "########################################################" ] )
  , ( "Hòn đảo"
    , [ "########################################################"
      , "#PPP.PRR.S.S....BB.B..S.S................SS............#"
      , "#P...PRR.S..........B.....S..............S.S.........X.#"
      , "#...PRRS.SS.RRK.K.....SSSPP.R...........SS.............#"
      , "#........RRRBR..SK.####..PP..R...####.KVK.KSS.S.O......#"
      , "#......BBBBB...KKS.####P..RR.SRS.####VV.K......OO.O....#"
      , "#..RR...B.#####....####...P..S...####.K.K.#######.OSOOS#"
      , "#R.RL..S..#####.KK.####.......SSSS........#######.SOSS.#"
      , "#...LL...S#####..K.#####.SSSS.S...........#######.O.OO.#"
      , "#.#############.KKK#####.SSSS...........BB#######......#"
      , "#.#############P...#####.....S.......B.BBB#######.LS..S#"
      , "#.#############P.RP#####....######.V.B........LL...SOSS#"
      , "#...######PPP..R..R#####..RR######.V..############LBS.B#"
      , "#...######..P..RR........RRR######V.VV############.OB.O#"
      , "#...######P.P......KKK.#######.......K############..B.B#"
      , "#..S######.........KK.K#######...............O####P.P..#"
      , "#...######.............#######.###B.#######O..####P...O#"
      , "#SS.S..................KKK.....###..#######PR.R.....O.O#"
      , "#.......############..RR.P.P.P.###.B#######..RPP.####.O#"
      , "#.......############.R.R..PP...###.....RSSRR..RR.####..#"
      , "#.......############.....PP.KK...VVR.R....SRR....####S.#"
      , "#.RRR...############VOO.........SV.SSRPRP.SRSRRR.SSSSS.#"
      , "#RR.R...############VLLO.L...S.....KPPR.......######.S.#"
      , "#......PPP..########PVVOLV.P.B.KBK.KP########.######.K.#"
      , "#.....P.......K...PP...LVVPPSS.SSK.O.########.######.O.#"
      , "#.@..........K........P...P....BOO...########.######...#"
      , "#..........K...K...P..P..........O..O.................O#"
      , "########################################################" ] )
  ]


mkWorld :: (String, [String]) -> World
mkWorld (name, rs) =
  World name walls props bushes floors near size (spot '@') (spot 'X')
  where
    cs = [ ((x, y), c)
         | (y, row) <- zip [0..] rs
         , (x, c) <- zip [0..] row
         ]

    legend =
      [('B', Crate), ('O', Barrel), ('P', Plant), ('S', Stool),
       ('V', Vase), ('L', Lamp), ('K', Sack), ('R', Rock)]

    walls = S.fromList [p | (p, '#') <- cs]

    props =
      M.fromList
        [ (p, t)
        | (p, c) <- cs
        , Just t <- [lookup c legend]
        ]

    floors = [p | (p, c) <- cs, c `elem` ".@X"]

    -- In the original maps there is no separate bush character.
    -- Plant areas are therefore used as bush zones for the first backend version.
    bushes =
      S.fromList
        [ f
        | f <- floors
        , any (\(q, t) -> t == Plant && cheb q f <= 1) (M.toList props)
        ]

    near =
      [f | f <- floors, any (\q -> cheb q f <= 1) (M.keys props)]

    size = (length (head rs), length rs)

    spot ch = head [p | (p, c) <- cs, c == ch]

worlds :: [World]
worlds = map mkWorld maps

blocked :: World -> Pos -> Bool
blocked w p = S.member p (wWalls w) || M.member p (wProps w)

inMap :: World -> Pos -> Bool
inMap w (x, y) =
  x >= 0 && y >= 0 &&
  x < fst (wSize w) && y < snd (wSize w)

dist2 :: Pos -> Pos -> Int
dist2 (a, b) (c, d) =
  (a - c) * (a - c) + (b - d) * (b - d)

cheb :: Pos -> Pos -> Int
cheb (a, b) (c, d) = max (abs (a - c)) (abs (b - d))

manh :: Pos -> Pos -> Int
manh (a, b) (c, d) = abs (a - c) + abs (b - d)

line :: Pos -> Pos -> [Pos]
line (x0, y0) (x1, y1) =
  [(lerp x0 x1 i, lerp y0 y1 i) | i <- [0..n]]
  where
    n = max (abs (x1 - x0)) (abs (y1 - y0))

    lerp a b i
      | n == 0 = a
      | otherwise =
          a + floor
            (fromIntegral ((b - a) * i) / fromIntegral n + (0.5 :: Double))

-- Sight is limited by radius and walls.
sees :: World -> Int -> Pos -> Pos -> Bool
sees w r a b =
  dist2 a b <= r * r &&
  not (any (`S.member` wWalls w) inner)
  where
    l = line a b
    inner = take (length l - 2) (drop 1 l)

findPlayer :: PlayerId -> Game -> Maybe Player
findPlayer pid g =
  case [p | p <- players g, pId p == pid] of
    (p:_) -> Just p
    [] -> Nothing

updatePlayer :: PlayerId -> (Player -> Player) -> [Player] -> [Player]
updatePlayer pid f = map (\p -> if pId p == pid then f p else p)

aliveHiders :: Game -> [Player]
aliveHiders g =
  [p | p <- players g, pRole p == Hider, pAlive p]

aliveHunters :: Game -> [Player]
aliveHunters g =
  [p | p <- players g, pRole p == Hunter, pAlive p]

playerSpeedFor :: Player -> Int
playerSpeedFor p
  | pRole p == Hunter = hunterSpeed
  | otherwise = playerSpeed
-- Pick 3 distinct map indices from the 10 maps.
randomMapOptions :: Int -> ([Int], Int)
randomMapOptions seed =
  let (a, r1) = randomIndex seed
      (b, r2) = randomIndex r1
      (c, r3) = randomIndex r2
      available = [0 .. length maps - 1]
      options = take 3 (nub [a, b, c] ++ [x | x <- available, x `notElem` [a, b, c]])
  in (options, r3)
  where
    randomIndex r =
      let r' = nextRng r
      in ((r' `div` 65536) `mod` length maps, r')

newPlayer :: PlayerId -> Role -> Control -> Pos -> Player
newPlayer pid role control pos =
  Player
    { pId = pid
    , pRole = role
    , pControl = control
    , pPos = pos
    , pForm = Nothing
    , pMoved = False
    , pMode = Patrol pos
    , pKnifeCd = 0
    , pSwapCd = 0
    , pFakeCount = 0
    , pAlive = True
    , pNote = ""
    }

spawnPositions :: World -> [Pos]
spawnPositions w =
  take (hunterSlots + maxHiderSlots) (wFloors w)

-- Start a lobby. Players do NOT choose a role.
-- The backend fills missing slots with bots and assigns roles randomly when the map is chosen.
startLobby :: Int -> [PlayerId] -> Game
startLobby seed humanIds =
  startLobbyWithPlayers seed humanIds

startLobbyWithPlayers :: Int -> [PlayerId] -> Game
startLobbyWithPlayers seed humanIds =
  let humanIds' = take (hunterSlots + maxHiderSlots) humanIds
      humanTotal = length humanIds'
      r1 = nextRng seed
      randomHiders = min maxHiderSlots
          (max minHiderSlots
            (((r1 `div` 65536) `mod`
              (maxHiderSlots - minHiderSlots + 1)) + max 0 (humanTotal - hunterSlots)))
      totalPlayers = hunterSlots + randomHiders
      usedHumanIds = take totalPlayers humanIds'
      nextId = if null usedHumanIds
                 then 1
                 else 1 + maximum (map playerIdToInt usedHumanIds)
      botCount = totalPlayers - length usedHumanIds
      botIds = [PlayerId (nextId + i) | i <- [0 .. botCount - 1]]
      allIds = usedHumanIds ++ botIds
      -- Lobby role is only a temporary placeholder. It is randomized before the match starts.
      placeholderSpecs = [(pid, Hider, if pid `elem` usedHumanIds then Human else Bot)
                         | pid <- allIds]
      (opts, r2) = randomMapOptions r1
      w = worlds !! head opts
      ps = makePlayers w placeholderSpecs
  in Game
      { world = w
      , mapNo = -1
      , phase = Lobby
      , phaseTicks = lobbyTicks
      , players = ps
      , mapOptions = opts
      , mapVotes = M.empty
      , tick = 0
      , rng = r2
      , over = Nothing
      , note = "Lobby: vote 1 trong 3 map. Role sẽ được random khi bắt đầu trận."
      , whistle = 0
      , bell = False
      , fakeProps = []
      , timeLimit = winTicks
      , hunterStreak = M.empty
      }

makePlayers :: World -> [(PlayerId, Role, Control)] -> [Player]
makePlayers w specs =
  let hs = [s | s@(_, Hunter, _) <- specs]
      ds = [s | s@(_, Hider, _) <- specs]
      hunterSpawns = take (length hs) (spawnFrom w (wSeeker w))
      hiderSpawns = take (length ds) (spawnFrom w (wPlayer w))
      makeAt pos (pid, role, control) =
        newPlayer pid role control pos
  in zipWith makeAt hunterSpawns hs ++ zipWith makeAt hiderSpawns ds

spawnFrom :: World -> Pos -> [Pos]
spawnFrom w start =
  start : filter (/= start)
    (sortByDistance start (wFloors w))

sortByDistance :: Pos -> [Pos] -> [Pos]
sortByDistance p = map snd . sortPairs
  where
    sortPairs xs = foldr insertPair [] [(dist2 p x, x) | x <- xs]
    insertPair pair [] = [pair]
    insertPair pair@(d, _) allPairs@((d2, _) : _)
      | d <= d2 = pair : allPairs
      | otherwise = head allPairs : insertPair pair (tail allPairs)

-- Test helper: start directly on one selected map with the full bot roster.
startGame :: Int -> Int -> Game
startGame mapIndex seed =
  let ids = [PlayerId i | i <- [1 .. hunterSlots + minHiderSlots]]
      g0 = startLobbyWithPlayers seed ids
  in chooseMapDirect mapIndex g0

chooseMapDirect :: Int -> Game -> Game
chooseMapDirect i g =
  let w = worlds !! (i `mod` length worlds)
      (rolePlayers, r1) = randomizeRoles (rng g) (hunterStreak g) (players g)
      reset p =
        p { pPos = if pRole p == Hunter then wSeeker w else wPlayer w
          , pForm = Nothing
          , pMoved = False
          , pKnifeCd = 0
          , pSwapCd = 0
          , pFakeCount = 0
          , pAlive = True
          }
      ps = assignSpawns w (map reset rolePlayers)
      newStreak = M.fromList
        [ (pId p, if pRole p == Hunter
                    then M.findWithDefault 0 (pId p) (hunterStreak g) + 1
                    else 0)
        | p <- ps
        ]
  in g
      { world = w
      , mapNo = i `mod` length worlds
      , phase = HiderPrepare
      , phaseTicks = prepareTicks
      , players = ps
      , mapVotes = M.empty
      , rng = r1
      , hunterStreak = newStreak
      , note = "Hiders have 20 seconds to hide. Hunters are locked. Roles were randomized."
      , fakeProps = []
      , timeLimit = winTicks
      }

-- Randomly assign exactly 3 Hunters. A player who was Hunter recently gets
-- a lower weight, so the role stays random but avoids repeated Hunter streaks.
randomizeRoles :: Int -> M.Map PlayerId Int -> [Player] -> ([Player], Int)
randomizeRoles seed streak ps =
  let hunterIds = pickHunters seed hunterSlots ps
      isHunter p = pId p `elem` hunterIds
  in (map (\p -> p { pRole = if isHunter p then Hunter else Hider }) ps,
      advanceRandom seed hunterSlots)
  where
    pickHunters _ 0 _ = []
    pickHunters r n candidates
      | null candidates = []
      | otherwise =
          let (chosen, r1) = weightedPick r candidates
          in pId chosen : pickHunters r1 (n - 1) [p | p <- candidates, pId p /= pId chosen]

    weightedPick r candidates =
      let weighted = [(p, max 1 (100 - 30 * M.findWithDefault 0 (pId p) streak)) | p <- candidates]
          total = sum [w | (_, w) <- weighted]
          slot = (r `div` 65536) `mod` total
          choose _ [] = head candidates
          choose n ((p,w):xs)
            | n < w = p
            | otherwise = choose (n - w) xs
      in (choose slot weighted, nextRng r)

    advanceRandom r n = iterate nextRng r !! n

assignSpawns :: World -> [Player] -> [Player]
assignSpawns w ps =
  let hs = [p | p <- ps, pRole p == Hunter]
      ds = [p | p <- ps, pRole p == Hider]
      hPos = take (length hs) (spawnFrom w (wSeeker w))
      dPos = take (length ds) (spawnFrom w (wPlayer w))
      place xs positions = zipWith (\p pos -> p {pPos = pos}) xs positions
  in place hs hPos ++ place ds dPos

-- A human can join during the lobby by replacing any bot.
-- The human does not choose a role; role assignment happens when the match starts.
addHumanPlayer :: PlayerId -> Game -> Game
addHumanPlayer pid g
  | phase g /= Lobby = g
  | any ((== pid) . pId) (players g) = g
  | otherwise =
      case [p | p <- players g, pControl p == Bot] of
        [] -> g { note = "Lobby đã đủ người." }
        (bot:_) ->
          g { players = updatePlayer (pId bot)
                (\p -> p { pId = pid, pControl = Human })
                (players g)
            , note = "Người chơi đã vào lobby. Role sẽ được random khi bắt đầu."
            }

-- Map voting. One player has one vote; voting again changes the vote.
castVote :: PlayerId -> Int -> Game -> Game
castVote pid mapIndex g
  | phase g /= Lobby = g
  | not (elem mapIndex (mapOptions g)) = g
  | findPlayer pid g == Nothing = g
  | otherwise = g { mapVotes = M.insert pid mapIndex (mapVotes g)
                  , note = "Vote map " ++ show (mapIndex + 1) ++ "."
                  }

chooseMap :: Game -> Game
chooseMap g =
  let counts =
        [ (m, length [() | (_, v) <- M.toList (mapVotes g), v == m])
        | m <- mapOptions g
        ]

      best = if null counts then mapOptions g
             else let mx = maximum (map snd counts)
                  in [m | (m, n) <- counts, n == mx]

      r = nextRng (rng g)
      winner = pick r best
  in chooseMapDirect winner g { rng = r }

-- Find a prop and its position near a player.
nearestProp :: World -> Pos -> Maybe (Pos, Prop)
nearestProp w p =
  case [ (dist2 q p, q, t)
       | (q, t) <- M.toList (wProps w)
       , cheb q p <= 2
       ] of
    [] -> Nothing
    xs ->
      let (_, q, t) = minimumBy (comparing (\(d, _, _) -> d)) xs
      in Just (q, t)

fakePositions :: Game -> Player -> [Pos]
fakePositions g p =
  take 2
    [q | q <- candidates, valid q]
  where
    (x, y) = pPos p
    candidates =
      [(x+1,y), (x-1,y), (x,y+1), (x,y-1),
       (x+1,y+1), (x-1,y+1), (x+1,y-1), (x-1,y-1)]

    valid q =
      inMap (world g) q &&
      not (blocked (world g) q) &&
      all (\p2 -> pPos p2 /= q) (players g) &&
      all (\f -> fpPos f /= q) (fakeProps g)

applyAction :: PlayerAction -> Game -> Game
applyAction (PlayerAction pid act) g
  | findPlayer pid g == Nothing = g
  | otherwise =
      case phase g of
        Lobby -> applyLobby pid act g
        HiderPrepare -> applyPrepare pid act g
        Playing -> applyPlaying pid act g
        GameOver -> g

applyLobby :: PlayerId -> Act -> Game -> Game
applyLobby pid act g =
  case act of
    Vote m -> castVote pid m g
    _ -> g

applyPrepare :: PlayerId -> Act -> Game -> Game
applyPrepare pid act g =
  case findPlayer pid g of
    Nothing -> g
    Just p
      | pRole p == Hunter -> g { note = "Hunters are locked for the first 20 seconds." }
      | otherwise -> applyHiderAction pid act g

applyPlaying :: PlayerId -> Act -> Game -> Game
applyPlaying pid act g =
  case findPlayer pid g of
    Nothing -> g
    Just p
      | not (pAlive p) -> g
      | pRole p == Hunter -> applyHunterAction pid act g
      | otherwise -> applyHiderAction pid act g

applyHiderAction :: PlayerId -> Act -> Game -> Game
applyHiderAction pid act g =
  case findPlayer pid g of
    Nothing -> g
    Just p ->
      case act of
        Move delta -> movePlayer pid delta g
        Morph
          | pForm p == Nothing -> morphPlayer pid False g
          | otherwise -> g { note = "Đã hóa thân. Dùng SwapMorph để đổi prop." }
        SwapMorph -> morphPlayer pid True g
        Duplicate -> duplicatePlayer pid g
        Revert -> revertPlayer pid g
        _ -> g

applyHunterAction :: PlayerId -> Act -> Game -> Game
applyHunterAction pid act g =
  case act of
    Move delta -> movePlayer pid delta g
    Attack -> hunterAttack pid g
    _ -> g

movePlayer :: PlayerId -> Pos -> Game -> Game
movePlayer pid (dx, dy) g =
  case findPlayer pid g of
    Nothing -> g
    Just p ->
      let maxStep =
            if pRole p == Hunter then hunterSpeed else playerSpeed
          dx' = clamp (-maxStep) maxStep dx
          dy' = clamp (-maxStep) maxStep dy
          old = pPos p
          new = (fst old + dx', snd old + dy')
      in if (dx' == 0 && dy' == 0)
           then g
           else if validPlayerPosition pid new g
                  then g { players = updatePlayer pid
                              (\x -> x { pPos = new, pMoved = True })
                              (players g)
                         }
                  else g

clamp :: Int -> Int -> Int -> Int
clamp lo hi x = max lo (min hi x)

validPlayerPosition :: PlayerId -> Pos -> Game -> Bool
validPlayerPosition pid q g =
  inMap (world g) q &&
  not (S.member q (wWalls (world g))) &&
  not (any (\(p, _) -> p == q) otherProps) &&
  not (any (\p -> pAlive p && pId p /= pid && pPos p == q) (players g))
  where
    currentPropPos =
      case findPlayer pid g of
        Just p -> pPos p
        Nothing -> (-999999, -999999)

    otherProps =
      [ (p, prop)
      | (p, prop) <- M.toList (wProps (world g))
      , p /= currentPropPos
      ]

morphPlayer :: PlayerId -> Bool -> Game -> Game
morphPlayer pid isSwap g =
  case findPlayer pid g of
    Nothing -> g
    Just p ->
      case nearestProp (world g) (pPos p) of
        Nothing -> g { note = "Không có prop đủ gần để hóa thân." }
        Just (q, t)
          | not isSwap && pForm p /= Nothing ->
              g { note = "Đã hóa thân. Dùng SwapMorph để đổi prop." }
          | isSwap && pForm p == Nothing ->
              g { note = "Phải hóa thân trước khi Swap Morph." }
          | isSwap && pSwapCd p > 0 ->
              g { note = "Swap Morph còn cooldown." }
          | otherwise ->
              let p' =
                    p { pPos = q
                      , pForm = Just t
                      , pMoved = False
                      , pSwapCd = if isSwap then swapMorphCooldown else pSwapCd p
                      , pFakeCount = 0
                      , pNote = "Đã hóa thân thành " ++ propName t
                      }
              in g
                  { players = updatePlayer pid (const p') (players g)
                  , fakeProps = removeFakes pid (fakeProps g)
                  , note = pNote p'
                  }

duplicatePlayer :: PlayerId -> Game -> Game
duplicatePlayer pid g =
  case findPlayer pid g of
    Nothing -> g
    Just p
      | pRole p /= Hider -> g
      | pForm p == Nothing -> g { note = "Phải hóa thân trước khi tạo fake." }
      | pFakeCount p >= 2 -> g { note = "Đã có tối đa 2 fake props." }
      | otherwise ->
          case fakePositions g p of
            [] -> g { note = "Không có chỗ trống để tạo fake." }
            (q:_) ->
              let t = case pForm p of
                        Just x -> x
                        Nothing -> Crate
                  f = FakeProp pid t q
              in g
                  { fakeProps = f : fakeProps g
                  , players = updatePlayer pid
                      (\x -> x { pFakeCount = pFakeCount x + 1 })
                      (players g)
                  , note = "Đã tạo fake prop."
                  }

revertPlayer :: PlayerId -> Game -> Game
revertPlayer pid g =
  g { players = updatePlayer pid
        (\p -> p { pForm = Nothing, pMoved = False, pFakeCount = 0
                 , pNote = "Đã trở lại hình người." })
        (players g)
    , fakeProps = removeFakes pid (fakeProps g)
    , note = "Đã trở lại hình người."
    }

removeFakes :: PlayerId -> [FakeProp] -> [FakeProp]
removeFakes pid = filter (\f -> fpOwner f /= pid)

propName :: Prop -> String
propName Crate = "thùng gỗ"
propName Barrel = "thùng phuy"
propName Plant = "chậu cây"
propName Stool = "ghế đẩu"
propName Vase = "bình hoa"
propName Lamp = "đèn đứng"
propName Sack = "bao tải"
propName Rock = "tảng đá"

hunterAttack :: PlayerId -> Game -> Game
hunterAttack hid g =
  case findPlayer hid g of
    Nothing -> g
    Just hunter
      | pKnifeCd hunter > 0 -> g { note = "Knife đang cooldown." }
      | otherwise ->
          let g1 = g { players = updatePlayer hid
                          (\p -> p { pKnifeCd = knifeCooldown })
                          (players g)
                     }
              hit = [p | p <- aliveHiders g1
                           , visibleTo hunter p g1
                           , knifeHits hunter p]
              fakeHit = any (\f -> dist2 (pPos hunter) (fpPos f) <= 2)
                             (visibleFakes (pId hunter) g1)
          in case hit of
               (victim:_) -> catchHider (pId victim) g1
               [] | fakeHit -> g1 { note = "Knife trúng fake prop. Hider vẫn an toàn." }
                  | otherwise -> g1 { note = "Knife không trúng hider." }

knifeHits :: Player -> Player -> Bool
knifeHits hunter target =
  pRole hunter == Hunter &&
  pRole target == Hider &&
  pAlive target &&
  fromIntegral (dist2 (pPos hunter) (pPos target)) <= knifeHitbox * knifeHitbox

catchHider :: PlayerId -> Game -> Game
catchHider pid g =
  let g1 =
        g { players = updatePlayer pid
              (\p -> p { pAlive = False, pForm = Nothing, pFakeCount = 0 })
              (players g)
          , fakeProps = removeFakes pid (fakeProps g)
          , timeLimit = timeLimit g + timeBonusTicks
          , note = "Hider bị bắt! +20 giây."
          }
  in g1

-- A bot hunter chases only hiders that are actually visible to that hunter.
moveBots :: Game -> Game
moveBots g =
  foldl' moveOne g [p | p <- players g, pControl p == Bot, pAlive p]
  where
    moveOne game bot =
      case pRole bot of
        Hunter ->
          case visibleHiderTarget bot game of
            Just targetP ->
              let next = stepToward (world game) (pPos bot) (pPos targetP)
                  movedGame = if phase game == Playing
                                then setBotPosition (pId bot) next game
                                else game
               in if knifeHits bot targetP
                   then hunterAttack (pId bot) movedGame
                   else movedGame
            Nothing ->
              setBotPosition (pId bot)
                (stepToward (world game) (pPos bot) (wPlayer (world game))) game

        Hider ->
          let r = nextRng (rng game)
              options =
                 [candidate | candidate <- neighbors (pPos bot)
                     , validPlayerPosition (pId bot) candidate game]
              nextPos = if null options then pPos bot else pick r options
           in setBotPosition (pId bot) nextPos game

setBotPosition :: PlayerId -> Pos -> Game -> Game
setBotPosition pid q g =
  if validPlayerPosition pid q g
    then g { players = updatePlayer pid
              (\p -> p { pPos = q, pMoved = q /= pPos p })
              (players g) }
    else g

neighbors :: Pos -> [Pos]
neighbors (x, y) =
  [(x+1,y), (x-1,y), (x,y+1), (x,y-1)]

visibleHiderTarget :: Player -> Game -> Maybe Player
visibleHiderTarget hunter g =
  case [p | p <- aliveHiders g, visibleTo hunter p g] of
    [] -> Nothing
    xs -> Just (minimumBy (comparing (\p -> dist2 (pPos hunter) (pPos p))) xs)

stepToward :: World -> Pos -> Pos -> Pos
stepToward w from to
  | from == to = from
  | otherwise = bfs from
  where
    bfs start =
      search (S.singleton start) [(start, start)]

    search _ [] = from
    search seen frontier =
      case [first | (current, first) <- frontier, current == to] of
        (first:_) -> first
        [] ->
          let (seen', next) = foldl' expand (seen, []) frontier
          in search seen' (reverse next)

    expand acc (current, first) =
      foldl' visit acc (neighbors current)
      where
        visit (seen, xs) n
          | blocked w n || S.member n seen = (seen, xs)
          | otherwise =
              ( S.insert n seen
              , (n, if current == from then n else first) : xs
              )

-- Visibility:
-- 1. Outside a bush, a hunter cannot receive exact information about a hider
--    inside that bush.
-- 2. Inside a bush, nearby hiders are revealed within bushRevealRange.
-- 3. Sight is still limited by sightRange and walls.
visibleTo :: Player -> Player -> Game -> Bool
visibleTo viewer targetP g
  | pRole targetP /= Hider || not (pAlive targetP) = False
  | pRole viewer == Hider = sees w sightRange (pPos viewer) (pPos targetP)
  | not (sees w sightRange (pPos viewer) (pPos targetP)) = False
  | targetInBush && not viewerInBush = False
  | viewerInBush = cheb (pPos viewer) (pPos targetP) <= bushRevealRange
  | otherwise = True
  where
    w = world g
    targetInBush = S.member (pPos targetP) (wBushes w)
    viewerInBush = S.member (pPos viewer) (wBushes w)

data PlayerView = PlayerView
  { pvId :: PlayerId
  , pvRole :: Role
  , pvPos :: Pos
  , pvForm :: Maybe Prop
  , pvAlive :: Bool
  } deriving (Eq, Show)

playerView :: Player -> PlayerView
playerView p =
  PlayerView (pId p) (pRole p) (pPos p) (pForm p) (pAlive p)

-- IMPORTANT: this is the state that Server.hs should send to one client.
-- Hidden hiders are omitted instead of being sent and merely hidden by React.
visiblePlayers :: PlayerId -> Game -> [PlayerView]
visiblePlayers viewerId g =
  case findPlayer viewerId g of
    Nothing -> []
    Just viewer ->
      [playerView p | p <- players g, pId p == viewerId || canSeePlayer viewer p g]

canSeePlayer :: Player -> Player -> Game -> Bool
canSeePlayer viewer targetP g
  | pId viewer == pId targetP = True
  | not (pAlive targetP) = False
  | pRole targetP == Hider = visibleTo viewer targetP g
  | otherwise = sees (world g) sightRange (pPos viewer) (pPos targetP)

visibleFakes :: PlayerId -> Game -> [FakeProp]
visibleFakes viewerId g =
  case findPlayer viewerId g of
    Nothing -> []
    Just viewer ->
      [ f
      | f <- fakeProps g
      , sees (world g) sightRange (pPos viewer) (fpPos f)
      , fakeVisibleTo viewer f g
      ]

fakeVisibleTo :: Player -> FakeProp -> Game -> Bool
fakeVisibleTo viewer f g
  | pRole viewer /= Hunter = True
  | fakeInBush && not viewerInBush = False
  | viewerInBush = cheb (pPos viewer) (fpPos f) <= bushRevealRange
  | otherwise = True
  where
    fakeInBush = S.member (fpPos f) (wBushes (world g))
    viewerInBush = S.member (pPos viewer) (wBushes (world g))

advanceCooldowns :: Game -> Game
advanceCooldowns g =
  g { players = map dec (players g) }
  where
    dec p =
      p { pKnifeCd = max 0 (pKnifeCd p - 1)
        , pSwapCd = max 0 (pSwapCd p - 1)
        , pMoved = False
        }

advancePhase :: Game -> Game
advancePhase g =
  case phase g of
    Lobby
      | phaseTicks g <= 1 -> chooseMap g
      | otherwise -> g { phaseTicks = phaseTicks g - 1 }

    HiderPrepare
      | phaseTicks g <= 1 ->
          g { phase = Playing
            , phaseTicks = 0
            , note = "Hunt bắt đầu!"
            }
      | otherwise ->
          g { phaseTicks = phaseTicks g - 1 }

    Playing -> g

    GameOver -> g

checkWin :: Game -> Game
checkWin g
  | null (aliveHiders g) =
      g { phase = GameOver, over = Just False, note = "Tất cả Hiders đã bị bắt." }
  | tick g >= timeLimit g =
      g { phase = GameOver, over = Just True, note = "Hiders sống sót hết thời gian!" }
  | otherwise = g

-- One authoritative server tick.
stepGame :: Game -> Game
stepGame g0 =
  let g1 = advanceCooldowns g0
      g2 = if phase g1 == Playing then moveBots g1 else g1
      g3 = g2 { tick = tick g2 + 1 }
      g4 = advancePhase g3
  in checkWin g4
