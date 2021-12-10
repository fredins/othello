{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TupleSections #-}

module Main where
import           Control.Monad
import qualified Data.Map                      as M
import           Data.Maybe
import           Data.Text                      ( pack )
import           Data.Tuple.Extra               ( both )
import           Data.Vector                    ( Vector
                                                , fromList
                                                )
import           Debug.Trace
import qualified GI.Gtk                        as G
import           GI.Gtk.Declarative
import           GI.Gtk.Declarative.App.Simple
import           GI.Gtk.Declarative.Container.Grid
import           Othello


type Images = M.Map Pos G.Image

data Resources = Resources
  { empty     :: Images
  , white     :: Images
  , black     :: Images
  , highlight :: Images
  }

data Screen = StartMenu
          | Play
          | GameOver

data State = State
  { activeP   :: Player
  , playerB   :: Player
  , playerW   :: Player
  , board     :: Board
  , screen    :: Screen
  , resources :: Resources
  }


data Event = Close
           | DiskClicked (Pos, Maybe Disk)
           | StartPvP

update' :: State -> Event -> Transition State Event
update' s@State {..} e = case e of
  Close    -> Exit
  StartPvP -> Transition s { screen = Play } $ return Nothing

  DiskClicked (p, d) ->
    Transition
        (if null ps || isJust d
          then s
          else s { activeP = aP
                 , playerB = pB
                 , playerW = pW
                 , board   = b
                 , screen  = if gameOver pB pW b then GameOver else Play
                 }
        )
      $ return Nothing
   where
    ps       = flipped activeP board p
    b        = flipAll (p : ps) board activeP
    (pB, pW) = both (\d -> Player d $ countColor d b) (Black, White)
    aP | activeP == playerB && canPlay pW b && not (null ps) = pW
       | otherwise = pB

-- TODO add case screen, and add points + whose turn + buttons (restart, exit, show moves)
view' :: State -> AppView G.Window Event
view' s@State {..} =
  bin G.Window [#title := "Othello", on #destroy Close] $ case screen of
    StartMenu ->
      widget G.Button [#label := "Player vs Player", on #clicked StartPvP]

    Play -> container
      G.Box
      [#orientation := G.OrientationVertical]
      [ BoxChild defaultBoxChildProperties $ container
        G.Box
        [#orientation := G.OrientationHorizontal]
        [ BoxChild defaultBoxChildProperties { padding = 5 }
                   (widget G.Image [#file := "gui/white1.png"])
        , BoxChild
          defaultBoxChildProperties { padding = 5 }
          (widget G.Label [#label := pack (show (points playerW) ++ "x")])
        , BoxChild
          defaultBoxChildProperties { padding = 50 }
          (widget G.Label [#label := pack (show (disk activeP) ++ "'s turn")])
        , BoxChild defaultBoxChildProperties { padding = 5 }
                   (widget G.Image [#file := "gui/black1.png"])
        , BoxChild
          defaultBoxChildProperties { padding = 5 }
          (widget G.Label [#label := pack (show (points playerB) ++ "x")])
        ]
      , BoxChild defaultBoxChildProperties $ grid s
      ]

    GameOver -> widget G.Label [#label := pack winner]
 where
  (pb, pw) = updatePoints board
  winner | pb > pw   = "Black wins with " ++ show pb ++ " vs " ++ show pw ++ " points"
         | pw > pb   = "White wins with " ++ show pw ++ " vs " ++ show pb ++ " points"
         | otherwise = "Draw!"


grid :: State -> Widget Event
grid s@State {..} = container G.Grid [] cs
 where
  cs = fromList $ map c $ M.toList board
  c pd@((y, x), d) = GridChild
    defaultGridChildProperties { leftAttach = fromIntegral x
                               , topAttach  = fromIntegral y
                               }
    (widget G.Button [#image := image pd, on #clicked $ DiskClicked pd])
  image :: (Pos, Maybe Disk) -> G.Image
  image (p, d) = fromJust $ M.lookup p $ case d of
    (Just White) -> white resources
    (Just Black) -> black resources
    Nothing      -> if p `elem` (fst <$> possibleMoves activeP board)
      then highlight resources
      else empty resources



-- TODO add highlight res
createResources :: IO Resources
createResources = do
  e <- mapM (f "gui/empty.png") positions
  w <- mapM (f "gui/white.png") positions
  b <- mapM (f "gui/black.png") positions
  h <- mapM (f "gui/highlight.png") positions
  return Resources { empty     = M.fromList e
                   , white     = M.fromList w
                   , black     = M.fromList b
                   , highlight = M.fromList h
                   }
 where
  f :: String -> Pos -> IO (Pos, G.Image)
  f s p = (p, ) <$> G.imageNewFromFile s


initState :: IO State
initState = do
  res <- createResources

  return State { activeP   = pB
               , playerB   = pB
               , playerW   = pW
               , board     = startingBoard
               , screen    = StartMenu
               , resources = res
               }
 where
  pB = Player Black 0
  pW = Player White 0


main :: IO ()
main = do
  G.init Nothing
  state <- initState
  -- TODO maybe async?
  void $ run App { view         = view'
                 , update       = update'
                 , inputs       = []
                 , initialState = state
                 }
  G.main
