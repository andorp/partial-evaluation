{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE ViewPatterns #-}

module Reduce where

import Debug.Trace
import Data.Map (Map)
import qualified Data.Map as Map

type EName = String

data Stage = R | C deriving (Show,Eq,Ord)

data Lit
  = LFloat Float
  deriving (Show,Eq,Ord)

data PrimFun
  = PAdd
  | PMul
  | PIfZero
  deriving (Show,Eq,Ord)

data Exp
  = ELit      Stage Lit
  | EPrimFun  Stage PrimFun
  | EVar      Stage EName
  | EApp      Stage Exp Exp
  | ELam      Stage EName Exp
  | ELet      Stage EName Exp Exp
  -- specialization
  | EBody     Stage Exp
  | ESpec     EName Exp
  deriving (Show,Eq,Ord)

powerFun =
  ELet C "power" (ELam C "x" $ ELam C "n" $ ifZero (EVar C "n")
    (ELit C $ LFloat 1.0)
    (EApp C (EApp C (EPrimFun C PMul) (EVar C "x"))
            (EApp C (EApp C (EVar C "power") (EVar C "x")) (EApp C (EApp C (EPrimFun C PAdd) (ELit C $ LFloat $ -1.0)) (EVar C "n"))))
  )

reduceExp = powerFun $ EApp C (EApp C (EVar C "power") (ELit C $ LFloat 2.0)) (ELit C $ LFloat 4.0)

lit0R = ELit R $ LFloat 0.0
lit1R = ELit R $ LFloat 1.0

lit0 = ELit C $ LFloat 0.0
lit1 = ELit C $ LFloat 1.0
lit2 = ELit C $ LFloat 2.0

ifZero v t e = EApp C (EApp C (EApp C (EPrimFun C PIfZero) v) t) e

idFun = ELet C "id" (ELam C "x" $ EVar C "x")
reduceId = idFun $ EApp C (EVar C "id") lit1

lamIdFun = ELam C "x" $ EVar C "x"
reduceLamId = EApp C lamIdFun lit1

lamFun = ELam C "x" $ ELam C "y" $ EVar C "x"
reduceLamFun = EApp C (EApp C lamFun lit1) lit2

lamMixFun1 = ELam C "x" $ ELam R "y" $ ELam C "z" $ EApp R (EVar C "x") (EVar C "z") -- let fun = \x@C -> \y@R -> \z@C -> x@C z@C
reduceLamMix1 = EApp C (EApp R (EApp C lamMixFun1 lit1) (EVar R "a")) lit2 -- fun 1.0@C a@R 2.0@C ==> (\y -> 1.0 2.0) a

let0 = ELet C "v" lit1 $ EVar C "v"
let1 = ELet R "v" lit1 $ EVar R "v"

add = EApp C (EApp C (EPrimFun C PAdd) lit1) lit2
mul = EApp C (EApp C (EPrimFun C PMul) lit1) lit2

letFun0 = ELet C "v" (ELam C "x" $ EVar C "x") $ EApp C (EVar C "v") lit1
letFun1 = ELet C "f" (ELam C "x" $ ELam C "y" $ ifZero (EVar C "x") (EVar C "y") (EApp C (EApp C (EVar C "f") (EVar C "y")) (EVar C "x"))) $
  EApp C (EApp C (EVar C "f") lit2) lit0

reduceIfZero = ifZero lit0 lit1 lit2

-------- specialization test
primAddR x y = EApp R (EApp R (EPrimFun R PAdd) x) y
specFun0 = ESpec "f" $ ELam R "x" $ ELam C "y" $ EBody R $ primAddR (EVar R "x") (EVar C "y")
letSpecFun0 = ELet C "f" specFun0 $ EApp C (EApp R (EVar C "f") lit1R) lit2
--------
-- TODO
{-
  the generic function "f" should not be used in the residual; should be replaced with the specialised functions in the same scope
-}
{-
specFun1 = ELam R "x" $ ELam C "y" $ ELam R "z" $ primAddR (EVar R "x") $ primAddR (EVar C "y") (EVar R "z")
letSpecFun1 = ELet C "f" specFun1 $ EApp R (EApp C (EApp R (EVar C "f") lit1R) lit2) lit0R
-}

test = reduce mempty mempty reduceLamId
test1 = reduce mempty mempty reduceLamFun
test2 = reduce mempty mempty reduceLamMix1
test3 = reduce mempty mempty let0
test4 = reduce mempty mempty let1
test5 = reduce mempty mempty add
test6 = reduce mempty mempty mul
test7 = reduce mempty mempty letFun0
test8 = reduce mempty mempty reduceIfZero
test9 = reduce mempty mempty letFun1
test10 = reduce mempty mempty letSpecFun0

testPower = reduce mempty mempty reduceExp

result = ELit C (LFloat 1.0)
result1 = ELit C (LFloat 1.0)
result2 = EApp R (ELam R "y" (EApp R (ELit C (LFloat 1.0)) (ELit C (LFloat 2.0)))) (EVar R "a")
result3 = ELit C (LFloat 1.0)
result4 = ELet R "v" (ELit C (LFloat 1.0)) (EVar R "v")
result5 = ELit C (LFloat 3.0)
result6 = ELit C (LFloat 2.0)
result7 = ELit C (LFloat 1.0)
result8 = ELit C (LFloat 1.0)
result9 = ELit C (LFloat 2.0)
resultPower = ELit C (LFloat 16.0)

tests =
  [ (test,result)
  , (test1,result1)
  , (test2,result2)
  , (test3,result3)
  , (test4,result4)
  , (test5,result5)
  , (test6,result6)
  , (test7,result7)
  , (test8,result8)
  , (test9,result9)
  , (testPower,resultPower)
  ]

ok = mapM_ (\(a,b) -> putStrLn $ show (a == b) ++ " - " ++ show b) tests

type Env = Map EName Exp

--TODO(improve scoping): addEnv env n x = Map.insertWith (\new old -> error $ "addEnv - name clash: " ++ n ++ " " ++ show (new,old)) n x env
addEnv env n x = Map.insert n x env

-- HINT: the stack items are reduced expressions

reduce env stack e = {-trace (unlines [show env,show stack,show e,"\n"]) $ -}case e of
  ELit {} -> e
  -- question: who should reduce the stack arguments?
  --  answer: EApp

  EPrimFun C PAdd | (ELit _ (LFloat a)):(ELit _ (LFloat b)):_ <- stack -> ELit C $ LFloat $ a + b
  EPrimFun C PMul | (ELit _ (LFloat a)):(ELit _ (LFloat b)):_ <- stack -> ELit C $ LFloat $ a * b

  EPrimFun C PIfZero | (ELit _ (LFloat v)):th:el:_ <- stack -> if v == 0 then th else el

  EPrimFun R _ -> e

  EVar R n -> e
  EVar C n -> case Map.lookup n env of
    Nothing -> error $ "missing variable: " ++ n
    Just v -> reduce env stack v

  ELam C n x -> reduce (addEnv env n (head stack)) (tail stack) x
  ELam R n x -> ELam R n $ reduce env (tail stack) x

--  EBody C a -> reduce env stack a
  EBody R a -> EBody R $ reduce env stack a
    -- specialise function with key: name + args + body

  -- TODO: collet relevant (C) arguments from stack
  ESpec n e -> let e' = reduce env stack e in trace ("\n<SPECIALIZED> " ++ n ++ " = " ++ show e' ++ "\n<STACK> " ++ show (take 2 stack) ++ "\n") (EVar R $ n ++ "_spec")

  EApp C f a -> reduce env (reduce env stack a:stack) f
  EApp R f a -> EApp R (reduce env (a':stack) f) a' where a' = reduce env stack a

  ELet C n a b -> reduce (addEnv env n a) stack b
  ELet R n a b -> ELet R n (reduce env stack a) (reduce env stack b)

  _ -> error $ "can not reduce: " ++ show e

{-
  TODO:
    annotate RHS in let expressions
    specialize add x@c y@r
    how to specialise "power"?
-}
