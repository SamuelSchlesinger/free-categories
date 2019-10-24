{-|
Module: Data.Quiver.Functor
Description: free categories
Copyright: (c) Eitan Chatav, 2019
Maintainer: eitan@morphism.tech
Stability: experimental

Consider the category of Haskell quivers with

* objects are types of higher kind
  * @p :: k -> k -> Type@
* morphisms are terms of @RankNType@,
  * @forall x y. p x y -> q x y@
* identity is `id`
* composition is `.`

There is a natural hierarchy of typeclasses for
endofunctors of the category of Haskell quivers,
analagous to that for Haskell types.
-}

{-# LANGUAGE
    PolyKinds
  , RankNTypes
#-}

module Data.Quiver.Functor
  ( CFunctor (..)
  , CFoldable (..)
  , CTraversable (..)
  , CPointed (..)
  , CStrong (..)
  , CApplicative (..)
  , CMonad (..)
  ) where

import Control.Category
import Data.Quiver
import Prelude hiding (id, (.))

{- | An endfunctor of quivers.

prop> cmap id = id
prop> cmap (g . f) = cmap g . cmap f
-}
class CFunctor c where
  cmap :: (forall x y. p x y -> q x y) -> c p x y -> c q x y
instance CFunctor (ProductQ p) where cmap f (ProductQ p q) = ProductQ p (f q)
instance CFunctor (Quiver p) where cmap g (Quiver f) = Quiver (g . f)
instance Functor t => CFunctor (ApQ t) where cmap f (ApQ t) = ApQ (f <$> t)
instance CFunctor OpQ where cmap f = OpQ . f . getOpQ
instance CFunctor IsoQ where cmap f (IsoQ u d) = IsoQ (f u) (f d)
instance CFunctor IQ where cmap f = IQ . f . getIQ
instance CFunctor (ComposeQ p) where cmap f (ComposeQ p q) = ComposeQ p (f q)
instance CFunctor (ExtendQ p) where cmap g (ExtendQ f) = ExtendQ (g . f)
instance CFunctor (LiftQ p) where cmap g (LiftQ f) = LiftQ (g . f)

{- | Generalizing `Foldable` from `Monoid`s to `Category`s.

prop> cmap f = cfoldMap (csingleton . f)
-}
class CFunctor c => CFoldable c where
  {- | Map each element of the structure to a `Category`,
  and combine the results.-}
  cfoldMap :: Category q => (forall x y. p x y -> q x y) -> c p x y -> q x y
  {- | Combine the elements of a structure using a `Category`.-}
  cfold :: Category q => c q x y -> q x y
  cfold = cfoldMap id
  {- | Right-associative fold of a structure.

  In the case of `Control.Category.Free.Path`s,
  `cfoldr`, when applied to a binary operator,
  a starting value, and a `Control.Category.Free.Path`,
  reduces the `Control.Category.Free.Path` using the binary operator,
  from right to left:

  prop> cfoldr (?) q (p1 :>> p2 :>> ... :>> pn :>> Done) == p1 ? (p2 ? ... (pn ? q) ...)
  -}
  cfoldr :: (forall x y z . p x y -> q y z -> q x z) -> q y z -> c p x y -> q x z
  cfoldr (?) q c = getLiftQ (cfoldMap (\ x -> LiftQ (\ y -> x ? y)) c) q
  {- | Left-associative fold of a structure.

  In the case of `Control.Category.Free.Path`s,
  `cfoldl`, when applied to a binary operator,
  a starting value, and a `Control.Category.Free.Path`,
  reduces the `Control.Category.Free.Path` using the binary operator,
  from left to right:

  prop> cfoldl (?) q (p1 :>> p2 :>> ... :>> pn :>> Done) == (... ((q ? p1) ? p2) ? ...) ? pn
  -}
  cfoldl :: (forall x y z . q x y -> p y z -> q x z) -> q x y -> c p y z -> q x z
  cfoldl (?) q c = getExtendQ (cfoldMap (\ x -> ExtendQ (\ y -> y ? x)) c) q
  {- | Map each element of the structure to a `Monoid`,
  and combine the results.-}
  ctoMonoid :: Monoid m => (forall x y. p x y -> m) -> c p x y -> m
  ctoMonoid f = getKQ . cfoldMap (KQ . f)
  {- | Map each element of the structure, and combine the results in a list.-}
  ctoList :: (forall x y. p x y -> a) -> c p x y -> [a]
  ctoList f = ctoMonoid (pure . f)
  {- | Map each element of a structure to an `Applicative` on a `Category`,
  evaluate from left to right, and combine the results.-}
  ctraverse_
    :: (Applicative m, Category q)
    => (forall x y. p x y -> m (q x y)) -> c p x y -> m (q x y)
  ctraverse_ f = getApQ . cfoldMap (ApQ . f)
instance CFoldable (ProductQ p) where cfoldMap f (ProductQ _ q) = f q
instance CFoldable IQ where cfoldMap f (IQ c) = f c

{- | Generalizing `Traversable` to quivers.-}
class CFoldable c => CTraversable c where
  {- | Map each element of a structure to an `Applicative` on a quiver,
  evaluate from left to right, and collect the results.-}
  ctraverse
    :: Applicative m
    => (forall x y. p x y -> m (q x y)) -> c p x y -> m (c q x y)
instance CTraversable (ProductQ p) where
  ctraverse f (ProductQ p q) = ProductQ p <$> f q
instance CTraversable IQ where ctraverse f (IQ c) = IQ <$> f c

{- | Embed a single quiver arrow with `csingleton`.-}
class CFunctor c => CPointed c where csingleton :: p x y -> c p x y
instance CPointed (Quiver p) where csingleton q = Quiver (const q)
instance Applicative t => CPointed (ApQ t) where csingleton = ApQ . pure
instance CPointed IQ where csingleton = IQ
instance Category p => CPointed (ComposeQ p) where csingleton = ComposeQ id

{- | [Strength]
(https://ncatlab.org/nlab/show/tensorial+strength)
for quiver endofunctors with respect to `ProductQ`.

/Note:/ Every `Functor` is strong with respect to @(,)@,
but not every `CFunctor` is strong with respect to @ProductQ@.

prop> csecond . cmap csecond . cassoc = cmap cassoc . csecond
prop> cmap elim1 . csecond = elim1

`cfirst` and `csecond` are related as
prop> cfirst = cmap swapQ . csecond . swapQ
prop> csecond = cmap swapQ . cfirst . swapQ
-}
class CFunctor c => CStrong c where
  cfirst :: ProductQ (c p) q x y -> c (ProductQ p q) x y
  cfirst = cmap swapQ . csecond . swapQ
  csecond :: ProductQ p (c q) x y -> c (ProductQ p q) x y
  csecond = cmap swapQ . cfirst . swapQ
  {-# MINIMAL cfirst | csecond #-}
instance CStrong (Quiver p) where
  csecond (ProductQ p (Quiver f)) = Quiver (ProductQ p . f)
instance Functor t => CStrong (ApQ t) where
  csecond (ProductQ p (ApQ t)) = ApQ (ProductQ p <$> t)
instance CStrong IQ where csecond (ProductQ p (IQ q)) = IQ (ProductQ p q)

{- | Generalize `Applicative` to quivers.

The laws of a strong lax monoidal endofunctor hold.

>>> let cunit = csingleton (KQ ())
>>> let ctimes = czip ProductQ

prop> cmap (f `cbimap` g) (p `ctimes` q) = cmap f p `ctimes` cmap g q
prop> cmap celim1 (cunit `ctimes` q) = q
prop> cmap celim2 (p `ctimes` cunit) = p
prop> cmap cassoc ((p `ctimes` q) `ctimes` r) = p `ctimes` (q `ctimes` r)

The functions `cap` and `czip` are related as

prop> cap = czip getQuiver
prop> czip f p q = (Quiver . f) `cmap` p `cap` q
-}
class (CStrong c, CPointed c) => CApplicative c where
  cap :: c (Quiver p q) x y -> c p x y -> c q x y
  cap = czip getQuiver
  czip
    :: (forall x y. p x y -> q x y -> r x y)
    -> c p x y -> c q x y -> c r x y
  czip f p q = (Quiver . f) `cmap` p `cap` q
  {-# MINIMAL cap | czip #-}
instance CApplicative (Quiver p) where
  cap (Quiver cf) (Quiver cq) = Quiver (\p -> getQuiver (cf p) (cq p))
instance Applicative t => CApplicative (ApQ t) where
  czip f (ApQ tp) (ApQ tq) = ApQ (f <$> tp <*> tq)
instance CApplicative IQ where czip f (IQ p) (IQ q) = IQ (f p q)

{- | Generalize `Monad` to quivers.

Associativity and left and right identity laws hold.

prop> cjoin . cjoin = cjoin . cmap cjoin
prop> cjoin . csingleton = id
prop> cjoin . cmap csingleton = id

The functions `cbind` and `cjoin` are related as

prop> cjoin = cbind id
prop> cbind f p = cjoin (cmap f p)
-}
class (CFunctor c, CPointed c) => CMonad c where
  cjoin :: c (c p) x y -> c p x y
  cjoin = cbind id
  cbind :: (forall x y. p x y -> c q x y) -> c p x y -> c q x y
  cbind f p = cjoin (cmap f p)
  {-# MINIMAL cjoin | cbind #-}
instance CMonad (Quiver p) where
  cjoin (Quiver q) = Quiver (\p -> getQuiver (q p) p)
instance Monad t => CMonad (ApQ t) where
  cbind f (ApQ t) = ApQ $ do
    p <- t
    getApQ $ f p
instance CMonad IQ where cjoin = getIQ
instance Category p => CMonad (ComposeQ p) where
  cjoin (ComposeQ yz (ComposeQ xy q)) = ComposeQ (yz . xy) q
