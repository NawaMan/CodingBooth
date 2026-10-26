module Main where

greet :: String -> Int -> String
greet name times = concat (replicate times ("Hello, " ++ name ++ "! "))

main :: IO ()
main = putStrLn (greet "booth" 2)
