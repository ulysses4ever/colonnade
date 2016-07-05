{-# LANGUAGE RankNTypes   #-}
{-# LANGUAGE BangPatterns #-}

module Siphon.Decoding where

import Siphon.Types
import Colonnade.Types
import Siphon.Internal (row,comma)
import Data.Text (Text)
import Data.ByteString (ByteString)
import Pipes (yield,Pipe,Consumer',Producer,await)
import Data.Vector (Vector)
import qualified Data.Vector as Vector
import qualified Colonnade.Decoding as Decoding
import qualified Data.Attoparsec.ByteString as AttoByteString
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.Attoparsec.Types as Atto

-- unrow :: c1 -> (Vector c2,c1)
-- 
-- row :: _
--     -> Decoding (Indexed f) c a
--     -> Vector c
--     -> Either DecodingErrors a

-- decodeVectorPipe ::
--      Monad m
--   => Decoding (Indexed f) c a
--   -> Pipe (Vector c) a m ()
-- decodeVectorPipe 

mkParseError :: Int -> [String] -> String -> DecodingRowError f content
mkParseError i ctxs msg = id
  $ DecodingRowError i
  $ RowErrorParse $ concat
    [ "Contexts: ["
    , concat ctxs
    , "], Error Message: ["
    , msg
    , "]"
    ]

-- | This is seldom useful but is included for completeness.
headlessPipe :: Monad m
  => Siphon c
  -> Decoding Headless c a
  -> Pipe c a m (DecodingRowError Headless c)
headlessPipe sd decoding = uncheckedPipe requiredLength 0 sd indexedDecoding Nothing
  where
  indexedDecoding = Decoding.headlessToIndexed decoding
  requiredLength = Decoding.length indexedDecoding

indexedPipe :: Monad m
  => Siphon c
  -> Decoding (Indexed Headless) c a
  -> Pipe c a m (DecodingRowError Headless c)
indexedPipe sd decoding = do
  (firstRow, mleftovers) <- consumeGeneral sd mkParseError 
  let req = Decoding.maxIndex decoding
      vlen = Vector.length firstRow
  if vlen < req
    then return (DecodingRowError 0 (RowErrorMinSize req vlen))
    else case Decoding.uncheckedRun decoding firstRow of
      Left cellErr -> return $ DecodingRowError 0 $ RowErrorDecode cellErr
      Right a -> do
        yield a
        uncheckedPipe vlen 1 sd decoding mleftovers


headedPipe :: (Monad m, Eq c)
  => Siphon c
  -> Decoding Headed c a
  -> Pipe c a m (DecodingRowError Headed c)
headedPipe sd decoding = do
  (headers, mleftovers) <- consumeGeneral sd mkParseError 
  case Decoding.headedToIndexed headers decoding of
    Left headingErrs -> return (DecodingRowError 0 (RowErrorHeading headingErrs))
    Right indexedDecoding -> 
      let requiredLength = Vector.length headers
       in uncheckedPipe requiredLength 1 sd indexedDecoding mleftovers
  

uncheckedPipe :: Monad m
  => Int -- ^ expected length of each row
  -> Int -- ^ index of first row, usually zero or one
  -> Siphon c 
  -> Decoding (Indexed f) c a
  -> Maybe c
  -> Pipe c a m (DecodingRowError f c)
uncheckedPipe requiredLength ix sd d mleftovers = 
  pipeGeneral ix sd mkParseError checkedRunWithRow mleftovers
  where
  checkedRunWithRow rowIx v = 
    let vlen = Vector.length v in
    if vlen /= requiredLength
      then Left $ DecodingRowError rowIx 
                $ RowErrorSize requiredLength vlen
      else Decoding.uncheckedRunWithRow rowIx d v

consumeGeneral :: Monad m
  => Siphon c
  -> (Int -> [String] -> String -> e)
  -> Consumer' c m (Vector c, Maybe c)
consumeGeneral = error "ahh"

pipeGeneral :: Monad m
  => Int -- ^ index of first row, usually zero or one
  -> Siphon c
  -> (Int -> [String] -> String -> e)
  -> (Int -> Vector c -> Either e a)
  -> Maybe c -- ^ leftovers that should be handled first
  -> Pipe c a m e
pipeGeneral initIx (Siphon _ _ parse isNull) wrapParseError decodeRow mleftovers = 
  case mleftovers of
    Nothing -> go1 initIx
    Just leftovers -> handleResult initIx (parse leftovers)
  where
  go1 !ix = do
    c1 <- awaitSkip isNull
    handleResult ix (parse c1)
  go2 !ix c1 = handleResult ix (parse c1)
  go3 !ix k = do
    c1 <- awaitSkip isNull
    handleResult ix (k c1)
  handleResult !ix r = case r of
    Atto.Fail _ ctxs msg -> return $ wrapParseError ix ctxs msg
    Atto.Done c1 v -> do
      case decodeRow ix v of
        Left err -> return err
        Right r -> do
          yield r
          if isNull c1 then go1 ix else go2 ix c1
    Atto.Partial k -> go3 ix k

awaitSkip :: Monad m
          => (a -> Bool)
          -> Consumer' a m a
awaitSkip f = go where
  go = do
    a <- await
    if f a then go else return a 

