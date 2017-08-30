{-# LANGUAGE DeriveFoldable, DeriveFunctor, DeriveTraversable, FlexibleContexts, OverloadedStrings, PatternSynonyms, TemplateHaskell #-}
module Syntax.Sized.Lifted where

import Control.Monad
import Data.Deriving
import Data.String
import Data.Vector(Vector)

import Syntax hiding (Definition)
import Util

data Expr v
  = Var v
  | Global QName
  | Lit Literal
  | Con QConstr (Vector (Expr v)) -- ^ Fully applied
  | Call (Expr v) (Vector (Expr v)) -- ^ Fully applied, only global
  | PrimCall RetDir (Expr v) (Vector (Direction, Expr v))
  | Let NameHint (Expr v) (Scope1 Expr v)
  | Case (Expr v) (Branches QConstr () Expr v)
  | ExternCode (Extern (Expr v))
  | Anno (Expr v) (Type v)
  deriving (Foldable, Functor, Traversable)

type Type = Expr

-------------------------------------------------------------------------------
-- Helpers
pattern Sized :: Type v -> Expr v -> Expr v
pattern Sized sz e = Anno e sz

typeOf :: Expr v -> Expr v
typeOf (Anno _ sz) = sz
typeOf _ = error "Lifted.typeOf"

typeDir :: Expr v -> Direction
typeDir (Lit (TypeRep rep)) = Direct rep
typeDir _ = Indirect

-------------------------------------------------------------------------------
-- Instances
deriveEq1 ''Expr
deriveEq ''Expr
deriveOrd1 ''Expr
deriveOrd ''Expr
deriveShow1 ''Expr
deriveShow ''Expr

instance GlobalBind Expr where
  global = Global
  bind f g expr = case expr of
    Var v -> f v
    Global v -> g v
    Lit l -> Lit l
    Con c es -> Con c (bind f g <$> es)
    Call e es -> Call (bind f g e) (bind f g <$> es)
    PrimCall retDir e es -> PrimCall retDir (bind f g e) (fmap (bind f g) <$> es)
    Let h e s -> Let h (bind f g e) (bound f g s)
    Case e brs -> Case (bind f g e) (bound f g brs)
    ExternCode c -> ExternCode (bind f g <$> c)
    Anno e t -> Anno (bind f g e) (bind f g t)

instance Applicative Expr where
  pure = Var
  (<*>) = ap

instance Monad Expr where
  expr >>= f = bind f Global expr

instance (Eq v, IsString v, Pretty v)
  => Pretty (Expr v) where
  prettyM expr = case expr of
    Var v -> prettyM v
    Global g -> prettyM g
    Lit l -> prettyM l
    Con c es -> prettyApps (prettyM c) $ prettyM <$> es
    Call e es -> prettyApps (prettyM e) $ prettyM <$> es
    PrimCall retDir f es -> "primcall" <+> prettyAnnotation retDir (prettyApps (prettyM f) $ (\(d, e) -> prettyAnnotation d $ prettyM e) <$> es)
    Let h e s -> parens `above` letPrec $ withNameHint h $ \n ->
      "let" <+> prettyM n <+> "=" <+> prettyM e <+> "in" <+>
        prettyM (Util.instantiate1 (pure $ fromName n) s)
    Case e brs -> parens `above` casePrec $
      "case" <+> inviolable (prettyM e) <+>
      "of" <$$> indent 2 (prettyM brs)
    ExternCode c -> prettyM c
    Anno e t -> parens `above` annoPrec $
      prettyM e <+> ":" <+> prettyM t
