module Reflex.Dom.Colonnade where

import Colonnade.Types
import Control.Monad
import Reflex (Dynamic)
import Reflex.Dynamic (mapDyn)
import Reflex.Dom (MonadWidget)
import Reflex.Dom.Widget.Basic
import Data.Map (Map)
import qualified Colonnade.Encoding as Encoding
import qualified Data.Map as Map

cell :: m () -> Cell m
cell = Cell Map.empty

data Cell m = Cell
  { cellAttrs :: Map String String
  , cellContents :: m ()
  }

basic :: (MonadWidget t m, Foldable f)
      => Map String String -- ^ Table element attributes
      -> f a -- ^ Values
      -> Encoding Headed (Cell m) a -- ^ Encoding of a value into cells
      -> m ()
basic tableAttrs as encoding = do
  elAttr "table" tableAttrs $ do
    theadBuild encoding
    el "tbody" $ forM_ as $ \a -> do
      el "tr" $ mapM_ (Encoding.runRowMonadic encoding (elFromCell "td")) as

elFromCell :: MonadWidget t m => String -> Cell m -> m ()
elFromCell name (Cell attrs contents) = elAttr name attrs contents

theadBuild :: MonadWidget t m => Encoding Headed (Cell m) a -> m ()
theadBuild encoding = el "thead" . el "tr" 
  $ Encoding.runHeaderMonadic encoding (elFromCell "th")

dynamic :: (MonadWidget t m, Foldable f)
        => Map String String -- ^ Table element attributes
        -> f (Dynamic t a) -- ^ Dynamic values
        -> Encoding Headed (Cell m) a -- ^ Encoding of a value into cells
        -> m ()
dynamic tableAttrs as encoding@(Encoding v) = do
  elAttr "table" tableAttrs $ do
    theadBuild encoding
    el "tbody" $ forM_ as $ \a -> do
      el "tr" $ forM_ v $ \(OneEncoding _ encode) -> do
        dynPair <- mapDyn encode a
        dynAttrs <- mapDyn cellAttrs dynPair
        dynContent <- mapDyn cellContents dynPair
        _ <- elDynAttr "td" dynAttrs $ dyn dynContent
        return ()
