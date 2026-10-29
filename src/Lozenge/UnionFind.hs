module Lozenge.UnionFind (
  UF,
  newUF,
  makeSet,
  find,
  union,
  parents,
)
where

import Control.Monad.ST (ST)

data UF s

newUF :: ST s (UF s)
newUF = error "TODO: newUF"

makeSet :: UF s -> ST s Int
makeSet = error "TODO: makeSet"

find :: UF s -> Int -> ST s Int
find = error "TODO: find"

union :: UF s -> Int -> Int -> ST s Int
union = error "TODO: union"

parents :: UF s -> ST s [Int]
parents = error "TODO: parents"
