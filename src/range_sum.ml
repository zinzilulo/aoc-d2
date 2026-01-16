(* We generally open Core and Hardcaml in any source file in a hardware project. For
   design source files specifically, we also open Signal. *)
open! Core
open! Hardcaml
open! Signal

let num_bits = 64

module I = struct
  type 'a t =
    { clock : 'a
    ; clear : 'a
    ; start : 'a
    ; finish : 'a
    ; data_lo : 'a [@bits num_bits]
    ; data_hi : 'a [@bits num_bits]
    ; data_in_valid : 'a
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t = { sum : 'a With_valid.t [@bits num_bits] } [@@deriving hardcaml]
end

module States = struct
  type t =
    | Idle
    | Running
    | Done
  [@@deriving sexp_of, compare ~localize, enumerate]
end

let create
      scope
      ({ clock; clear; start; finish; data_lo; data_hi; data_in_valid } : _ I.t)
  : _ O.t
  =
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let sm = State_machine.create (module States) spec in
  let%hw_var lo = Variable.reg spec ~width:num_bits in
  let%hw_var hi = Variable.reg spec ~width:num_bits in
  let%hw_var acc = Variable.reg spec ~width:num_bits in
  let%hw_var k = Variable.reg spec ~width:4 in
  let%hw_var p10 = Variable.reg spec ~width:num_bits in
  let%hw_var a = Variable.reg spec ~width:num_bits in
  let%hw_var prod = Variable.reg spec ~width:num_bits in
  let%hw_var p10_prev = Variable.reg spec ~width:num_bits in
  let sum = Variable.wire ~default:(zero num_bits) () in
  let sum_valid = Variable.wire ~default:gnd () in
  let one = of_int_trunc ~width:num_bits 1 in
  let ten = of_int_trunc ~width:num_bits 10 in
  let max_k = 12 in
  let open Hardcaml.Comb in
  let p10_next = sll p10.value ~by:3 +: sll p10.value ~by:1 in
  let m = p10.value +:. 1 in
  compile
    [ sm.switch
        [ ( Idle
          , [ when_
                (start &: data_in_valid)
                [ lo <-- data_lo
                ; hi <-- data_hi
                ; k <-- of_int_trunc ~width:4 1
                ; a <-- zero num_bits
                ; prod <-- zero num_bits
                ; p10_prev <-- one
                ; p10 <-- ten
                ; sm.set_next Running
                ]
            ] )
        ; ( Running
          , [
              (let a_max =
                 Signal.uresize ((p10_prev.value *: ten) -:. 1) ~width:num_bits
               in
               if_
                 (a.value ==: zero num_bits)
                 [ a <-- p10_prev.value
                 ; prod <-- Signal.uresize (p10_prev.value *: m) ~width:num_bits
                 ]
                 [
                   if_
                     (a.value >: a_max)
                     [ a <-- zero num_bits
                     ; prod <-- zero num_bits
                     ; p10_prev <-- p10.value
                     ; p10 <-- p10_next
                     ; k <-- k.value +:. 1
                     ]
                     [ if_
                         (prod.value <: lo.value)
                         [ a <-- a.value +:. 1; prod <-- prod.value +: m ]
                         [ if_
                             (prod.value >: hi.value)
                             [ a <-- zero num_bits
                             ; prod <-- zero num_bits
                             ; p10_prev <-- p10.value
                             ; p10 <-- p10_next
                             ; k <-- k.value +:. 1
                             ]
                             [ acc <-- acc.value +: prod.value
                             ; a <-- a.value +:. 1
                             ; prod <-- prod.value +: m
                             ]
                         ]
                     ]
                 ])
            ; when_ (k.value >: of_int_trunc ~width:4 max_k) [ sm.set_next Done ]
            ] )
        ; Done, [ sum_valid <-- vdd; when_ finish [ sm.set_next Idle ] ]
        ]
    ; sum <-- acc.value
    ];
  { sum = { value = sum.value; valid = sum_valid.value } }
;;

(* The [hierarchical] wrapper is used to maintain module hierarchy in the generated
   waveforms and (optionally) the generated RTL. *)
let hierarchical scope =
  let module Scoped = Hierarchy.In_scope (I) (O) in
  Scoped.hierarchical ~scope ~name:"range_sum" create
;;
