# AoC Day 2 (Gift Shop) in (Haskell &) HardCaml

This problem asks us to compute the sum of invalid product IDs across a set of numeric ranges.

An invalid product ID is a number formed by duplicating a sequence of digits, for example:

- `11`, `22`
- `1212`, `998998`
- `824824`, `21212121`

In general, these numbers all have the form: $\text{dup}(a) = a \times (10^k + 1)$, where `a` is a `k`-digit number. Think of this as “write `a` twice and glue the copies together.”

## Reformulation

A straightforward solution would scan every number in each range `[lo, hi]` and check whether it’s a duplicated pattern. However, that would not be very efficient. We observe that for a fixed `k` $\text{dup}(a) = a \times (10^k + 1)$ is strictly increasing in `a`. That means all invalid IDs of a given digit width inside `[lo, hi]` come from a single, contiguous range of `a` values.

Starting from: $lo \le a(10^k + 1) \le hi$, we can invert the bounds to get:

```haskell
loA = max (10^(k-1)) (ceilDiv lo (10^k + 1))
hiA = min (10^k - 1) (hi `div` (10^k + 1))
```

If `loA ≤ hiA`, then all invalid IDs for this `k` are just: $(10^k + 1) \times \sum_{a=loA}^{hiA} a$, which we can compute directly using the arithmetic series formula. No per-ID checking required.

## Haskell implementation

### Parsing and normalization

```haskell
parseInput :: String -> [Range]
parseInput =
  pairUp
  . mapMaybe (readMaybe :: String -> Maybe Integer)
  . split ",-"
```

The input is split on commas and hyphens, parsed into integers, and paired up into `(lo, hi)` ranges. We then sort and merge overlapping ranges with `mergeRanges` so we don’t accidentally double-count anything.

### Computing the sum

```haskell
invalidSumInRange :: Range -> Integer
invalidSumInRange (lo, hi) =
  sum [sumForK k | k <- [1 .. maxK]]
```

For each digit width `k`, we:

- Compute `m = 10^k + 1`
- Work out the valid range of `a` values using division
- Use a closed-form sum to add them up
- Multiply by `m` to get the contribution to the final answer

This approach avoids iterating over each individual product ID and is fast even for large ranges.

### Putting it together

```haskell
solve :: String -> Integer
solve =
  sum
  . map invalidSumInRange
  . mergeRanges
  . parseInput
```

## Hardware design in HardCaml

### Assumptions

Doing string parsing and dynamic lists in hardware is painful and not very interesting here, so we make a few simplifying assumptions:

- Input ranges are already parsed and de-duplicated
- Ranges are streamed in one at a time
- The circuit keeps a running accumulator for the total sum

This lets us focus on the core numeric logic.

## Streaming interface

```ocaml
module I = struct
  type 'a t =
    { clock : 'a
    ; clear : 'a
    ; start : 'a
    ; finish : 'a
    ; data_lo : 'a [@bits 64]
    ; data_hi : 'a [@bits 64]
    ; data_in_valid : 'a
    }
end
```

- `start` together with `data_in_valid` loads a new `(lo, hi)` range
- `finish` signals that no more ranges are coming
- The output is a `With_valid` sum that becomes valid when all ranges are processed

## State machine

```ocaml
type t =
  | Idle
  | Running
  | Done
```

### Idle

The circuit waits for a valid input range. When one arrives, it initializes:

- `k = 1`
- `p10 = 10`
- `p10_prev = 1`
- the accumulator (which holds the global sum across all ranges)

and transitions to `Running`.

### Running

For each digit width `k`, the circuit effectively enumerates all `k`-digit values of `a`.

It computes:

```ocaml
m = p10 + 1
prod = a * m
```

In software we’d just divide to find the valid bounds for `a`, but division is expensive in hardware and not directly available in HardCaml’s combinational logic. Instead, the design leans into iteration.

- Powers of ten are generated using shifts:

  ```ocaml
  p10_next = (p10 << 3) + (p10 << 1)
  ```

- The product `prod = a × (10^k + 1)` is built incrementally:

  ```ocaml
  prod <- prod + m
  a    <- a + 1
  ```

Each cycle checks:

- `prod < lo` → not in range yet, keep going
- `prod > hi` → we’re done with this `k`, move to the next
- otherwise → add `prod` to the accumulator

This trades latency for much simpler and cheaper hardware, which is usually a good deal.

### Done

Once all digit widths have been processed:

- `sum.valid` is asserted
- the circuit waits for `finish`
- then returns to `Idle`, ready for the next stream

## Verification

We use two streaming tests with waveforms for inspections.

As expected, the hardware results exactly match the reference Haskell implementation.

```ocaml
dune build bin/generate.exe @runtest
File "test/test_range_sum.ml", line 1, characters 0-0:
diff --git a/_build/default/test/test_range_sum.ml b/_build/.sandbox/56537e1829c468b9cdc4791eef637e0b/default/test/test_range_sum.ml.corrected
index e05ff98..e7b5050 100644
--- a/_build/default/test/test_range_sum.ml
+++ b/_build/.sandbox/56537e1829c468b9cdc4791eef637e0b/default/test/test_range_sum.ml.corrected
@@ -112,10 +112,110 @@ let run_with_waves ~name ranges =

 let%expect_test "range_sum waveforms (ranges_1)" =
   run_with_waves ~name:"ranges_1" ranges_1;
-  [%expect {| ("Final streaming sum" (!last_sum 1227775554)) |}]
+  [%expect {|
+    ("Final streaming sum" (!last_sum 1227775554))
+    ranges_1
+    ┌Signals─────────────────────┐┌Waves───────────────────────────────────────────────────────┐
+    │                            ││────────────────┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───│
+    │range_sum$a                 ││ 0              │1  │2  │3  │0  │10 │0  │100│0  │10.│0  │10.│
+    │                            ││────────────────┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───│
+    │                            ││────────────────────┬───┬───────────────────────────────────│
+    │range_sum$acc               ││ 0                  │11 │33                                 │
+    │                            ││────────────────────┴───┴───────────────────────────────────│
+    │                            ││────────────┬───────────────────────────────────────────────│
+    │range_sum$hi                ││ 0          │22                                             │
+    │                            ││────────────┴───────────────────────────────────────────────│
+    │range_sum$i$clear           ││────┐                                                       │
+    │                            ││    └───────────────────────────────────────────────────────│
+    │range_sum$i$clock           ││┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ │
+    │                            ││  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─│
+    │                            ││────────┬───────────────────────────────────────────────────│
+    │range_sum$i$data_hi         ││ 0      │22                                                 │
+    │                            ││────────┴───────────────────────────────────────────────────│
+    │range_sum$i$data_in_valid   ││        ┌───┐                                               │
+    │                            ││────────┘   └───────────────────────────────────────────────│
+    │                            ││────────┬───────────────────────────────────────────────────│
+    │range_sum$i$data_lo         ││ 0      │11                                                 │
+    │                            ││────────┴───────────────────────────────────────────────────│
+    │range_sum$i$finish          ││                                                            │
+    │                            ││────────────────────────────────────────────────────────────│
+    │range_sum$i$start           ││        ┌───┐                                               │
+    │                            ││────────┘   └───────────────────────────────────────────────│
+    │                            ││────────────┬───────────────┬───────┬───────┬───────┬───────│
+    │range_sum$k                 ││ 0          │1              │2      │3      │4      │5      │
+    │                            ││────────────┴───────────────┴───────┴───────┴───────┴───────│
+    │                            ││────────────┬───────────────────────────────────────────────│
+    │range_sum$lo                ││ 0          │11                                             │
+    │                            ││────────────┴───────────────────────────────────────────────│
+    │range_sum$o$sum$valid       ││                                                            │
+    │                            ││────────────────────────────────────────────────────────────│
+    │                            ││────────────────────┬───┬───────────────────────────────────│
+    │range_sum$o$sum$value       ││ 0                  │11 │33                                 │
+    │                            ││────────────────────┴───┴───────────────────────────────────│
+    │                            ││────────────┬───────────────┬───────┬───────┬───────┬───────│
+    │range_sum$p10               ││ 0          │10             │100    │1000   │10000  │100000 │
+    │                            ││────────────┴───────────────┴───────┴───────┴───────┴───────│
+    │                            ││────────────┬───────────────┬───────┬───────┬───────┬───────│
+    │range_sum$p10_prev          ││ 0          │1              │10     │100    │1000   │10000  │
+    │                            ││────────────┴───────────────┴───────┴───────┴───────┴───────│
+    │                            ││────────────────┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───│
+    │range_sum$prod              ││ 0              │11 │22 │33 │0  │10.│0  │10.│0  │10.│0  │10.│
+    │                            ││────────────────┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───│
+    └────────────────────────────┘└────────────────────────────────────────────────────────────┘
+    |}]
 ;;

 let%expect_test "range_sum waveforms (ranges_2)" =
   run_with_waves ~name:"ranges_2" ranges_2;
-  [%expect {| ("Final streaming sum" (!last_sum <computed>)) |}]
+  [%expect {|
+    ("Final streaming sum" (!last_sum 35367539282))
+    ranges_2
+    ┌Signals─────────────────────┐┌Waves───────────────────────────────────────────────────────┐
+    │                            ││────────────────┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───│
+    │range_sum$a                 ││ 0              │1  │2  │3  │4  │5  │6  │7  │8  │9  │10 │0  │
+    │                            ││────────────────┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───│
+    │                            ││────────────────────────────────────────────────────────────│
+    │range_sum$acc               ││ 0                                                          │
+    │                            ││────────────────────────────────────────────────────────────│
+    │                            ││────────────┬───────────────────────────────────────────────│
+    │range_sum$hi                ││ 0          │35281                                          │
+    │                            ││────────────┴───────────────────────────────────────────────│
+    │range_sum$i$clear           ││────┐                                                       │
+    │                            ││    └───────────────────────────────────────────────────────│
+    │range_sum$i$clock           ││┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ │
+    │                            ││  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─│
+    │                            ││────────┬───────────────────────────────────────────────────│
+    │range_sum$i$data_hi         ││ 0      │35281                                              │
+    │                            ││────────┴───────────────────────────────────────────────────│
+    │range_sum$i$data_in_valid   ││        ┌───┐                                               │
+    │                            ││────────┘   └───────────────────────────────────────────────│
+    │                            ││────────┬───────────────────────────────────────────────────│
+    │range_sum$i$data_lo         ││ 0      │17330                                              │
+    │                            ││────────┴───────────────────────────────────────────────────│
+    │range_sum$i$finish          ││                                                            │
+    │                            ││────────────────────────────────────────────────────────────│
+    │range_sum$i$start           ││        ┌───┐                                               │
+    │                            ││────────┘   └───────────────────────────────────────────────│
+    │                            ││────────────┬───────────────────────────────────────────┬───│
+    │range_sum$k                 ││ 0          │1                                          │2  │
+    │                            ││────────────┴───────────────────────────────────────────┴───│
+    │                            ││────────────┬───────────────────────────────────────────────│
+    │range_sum$lo                ││ 0          │17330                                          │
+    │                            ││────────────┴───────────────────────────────────────────────│
+    │range_sum$o$sum$valid       ││                                                            │
+    │                            ││────────────────────────────────────────────────────────────│
+    │                            ││────────────────────────────────────────────────────────────│
+    │range_sum$o$sum$value       ││ 0                                                          │
+    │                            ││────────────────────────────────────────────────────────────│
+    │                            ││────────────┬───────────────────────────────────────────┬───│
+    │range_sum$p10               ││ 0          │10                                         │100│
+    │                            ││────────────┴───────────────────────────────────────────┴───│
+    │                            ││────────────┬───────────────────────────────────────────┬───│
+    │range_sum$p10_prev          ││ 0          │1                                          │10 │
+    │                            ││────────────┴───────────────────────────────────────────┴───│
+    │                            ││────────────────┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───│
+    │range_sum$prod              ││ 0              │11 │22 │33 │44 │55 │66 │77 │88 │99 │110│0  │
+    │                            ││────────────────┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───│
+    └────────────────────────────┘└────────────────────────────────────────────────────────────┘
+    |}]
 ;;
```
