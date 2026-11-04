{-# LANGUAGE OverloadedStrings #-}

module Lozenge.Pretty (render) where

import Data.Text (Text)
import Lozenge.Expr (Expr (..), Value (..), binOpName, cmpOpName, unOpName)
import Prettyprinter (Doc, defaultLayoutOptions, layoutPretty, nest, parens, pretty, sep)
import Prettyprinter.Render.Text (renderStrict)

render :: Expr -> Text
render = renderStrict . layoutPretty defaultLayoutOptions . doc

doc :: Expr -> Doc ann
doc (Var x) = pretty x
doc (Lit (VBool True)) = "true"
doc (Lit (VBool False)) = "false"
doc (Lit (VBV w v)) = form "const" [pretty w, pretty v]
doc (Un op a) = form (unOpName op) [doc a]
doc (Bin op a b) = form (binOpName op) [doc a, doc b]
doc (Cmp op a b) = form (cmpOpName op) [doc a, doc b]
doc (Ite c t e) = form "ite" [doc c, doc t, doc e]

form :: Text -> [Doc ann] -> Doc ann
form name args = parens (nest 2 (sep (pretty name : args)))
