module Lozenge.UnionFind (
  UF,
  newUF,
  makeSet,
  find,
  union,
  parents,
)
where

import Control.Monad (forM_)
import Control.Monad.ST (ST)
import Data.Array.ST (STUArray, getBounds, newArray_, readArray, writeArray)
import Data.STRef (STRef, newSTRef, readSTRef, writeSTRef)

data UF s = UF
  { ufParent :: STRef s (STUArray s Int Int),
    ufRank :: STRef s (STUArray s Int Int),
    ufCount :: STRef s Int
  }

newUF :: ST s (UF s)
newUF = UF <$> (newArray_ (0, 0) >>= newSTRef) <*> (newArray_ (0, 0) >>= newSTRef) <*> newSTRef 0

makeSet :: UF s -> ST s Int
makeSet uf = do
  n <- readSTRef (ufCount uf)
  ps <- roomFor n (ufParent uf)
  rs <- roomFor n (ufRank uf)
  writeArray ps n n
  writeArray rs n 0
  writeSTRef (ufCount uf) (n + 1)
  pure n

roomFor :: Int -> STRef s (STUArray s Int Int) -> ST s (STUArray s Int Int)
roomFor n ref = do
  old <- readSTRef ref
  (_, hi) <- getBounds old
  if n <= hi
    then pure old
    else do
      new <- newArray_ (0, 2 * n - 1)
      forM_ [0 .. n - 1] (\i -> readArray old i >>= writeArray new i)
      writeSTRef ref new
      pure new

find :: UF s -> Int -> ST s Int
find uf x = do
  ps <- readSTRef (ufParent uf)
  let go y = do
        p <- readArray ps y
        if p == y
          then pure y
          else do
            r <- go p
            writeArray ps y r
            pure r
  go x

union :: UF s -> Int -> Int -> ST s Int
union uf a b = do
  ra <- find uf a
  rb <- find uf b
  if ra == rb
    then pure ra
    else do
      ps <- readSTRef (ufParent uf)
      rs <- readSTRef (ufRank uf)
      rankA <- readArray rs ra
      rankB <- readArray rs rb
      case compare rankA rankB of
        LT -> rb <$ writeArray ps ra rb
        GT -> ra <$ writeArray ps rb ra
        EQ -> ra <$ (writeArray ps rb ra >> writeArray rs ra (rankA + 1))

parents :: UF s -> ST s [Int]
parents uf = do
  ps <- readSTRef (ufParent uf)
  n <- readSTRef (ufCount uf)
  traverse (readArray ps) [0 .. n - 1]
