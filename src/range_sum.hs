module Solution where

import Data.List (sortOn)
import Data.Maybe (mapMaybe)
import Text.Read (readMaybe)

type Range = (Integer, Integer)

split :: [Char] -> String -> [String]
split seps = foldr step [""]
  where
    step c acc@(x:xs)
      | c `elem` seps = "" : acc
      | otherwise     = (c:x) : xs

pairUp :: [a] -> [(a, a)]
pairUp (x:y:xs) = (x, y) : pairUp xs
pairUp _        = []

parseInput :: String -> [Range]
parseInput =
  pairUp
  . mapMaybe (readMaybe :: String -> Maybe Integer)
  . split ",-"

mergeRanges :: Ord a => [(a, a)] -> [(a, a)]
mergeRanges = foldr step [] . sortOn fst
  where
    step r [] = [r]
    step (l, r) acc@((l', r') : xs)
      | r < l'     = (l, r) : acc
      | otherwise  = (min l l', max r r') : xs

pow10 :: Int -> Integer
pow10 n = 10 ^ n

ceilDiv :: Integer -> Integer -> Integer
ceilDiv a b = (a + b - 1) `div` b

sumFromTo :: Integer -> Integer -> Integer
sumFromTo a b
  | a > b     = 0
  | otherwise =
      let n = b - a + 1
      in (a + b) * n `div` 2

-- For a fixed k, dup(a) is strictly increasing in a, so for a range [lo,hi]
-- we can find the valid a-interval by division, then sum via arithmetic series.

invalidSumInRange :: Range -> Integer
invalidSumInRange (lo, hi) = sum [sumForK k | k <- [1 .. maxK]]
  where
    -- For 64-bit values, duplicated numbers fit only for k ≤ 9. For generality compute maxK.
    maxK = 9

    sumForK :: Int -> Integer
    sumForK k =
      let m     = pow10 k + 1    -- multiplier for dup(a)
          aMin  = pow10 (k - 1)  -- smallest k-digit number
          aMax  = pow10 k - 1    -- largest k-digit number

          -- Invert dup(a)=a*m to constrain a so that lo <= a*m <= hi
          loA   = max aMin (ceilDiv lo m)
          hiA   = min aMax (hi `div` m)

          sumA  = sumFromTo loA hiA
      in m * sumA

solve :: String -> Integer
solve =
  sum
  . map invalidSumInRange
  . mergeRanges
  . parseInput

