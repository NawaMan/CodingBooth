{- |
  Factorial Calculator - Compute factorial of a number

  The factorial of n (written n!) is the product of all positive
  integers from 1 to n. For example: 5! = 5 × 4 × 3 × 2 × 1 = 120
-}

module Main where

import System.Environment (getArgs)
import Text.Read (readMaybe)

-- | Calculate factorial using recursion
factorial :: Integer -> Integer
factorial 0 = 1
factorial n = n * factorial (n - 1)

-- | Calculate factorial with memoization (for fun)
factorialMemo :: Integer -> Integer
factorialMemo = (map fact [0..] !!) . fromIntegral
  where fact 0 = 1
        fact n = n * factorialMemo (n - 1)

-- | Show step-by-step calculation
showSteps :: Integer -> String
showSteps n
  | n <= 1    = show n
  | otherwise = show n ++ " x " ++ showSteps (n - 1)

-- | Format the result nicely
formatResult :: Integer -> String
formatResult n =
  let result = factorial n
      steps = if n <= 10 then showSteps n else show n ++ "!"
  in show n ++ "! = " ++ steps ++ " = " ++ show result

-- | Show help message
showHelp :: IO ()
showHelp = do
  putStrLn "Factorial Calculator"
  putStrLn ""
  putStrLn "Compute the factorial of a number."
  putStrLn "The factorial of n (n!) is the product of all integers from 1 to n."
  putStrLn ""
  putStrLn "Usage: factorial <number>"
  putStrLn ""
  putStrLn "Examples:"
  putStrLn "  factorial 5     Compute 5! = 120"
  putStrLn "  factorial 10    Compute 10! = 3628800"
  putStrLn "  factorial 20    Compute 20! (a very large number)"

main :: IO ()
main = do
  args <- getArgs
  case args of
    [] -> showHelp
    (arg:_) -> case readMaybe arg :: Maybe Integer of
      Nothing -> putStrLn "Error: Please provide a valid non-negative integer"
      Just n
        | n < 0     -> putStrLn "Error: Factorial is not defined for negative numbers"
        | n > 1000  -> putStrLn "Error: Number too large (max 1000)"
        | otherwise -> putStrLn $ formatResult n
