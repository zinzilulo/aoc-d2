open! Core
open! Hardcaml
open! Hardcaml_waveterm
open! Hardcaml_test_harness
module Range_sum = Hardcaml_demo_project.Range_sum
module Harness = Cyclesim_harness.Make (Range_sum.I) (Range_sum.O)

let ( <--. ) = Bits.( <--. )

let ranges_1 =
  [ 11, 22
  ; 95, 115
  ; 998, 1012
  ; 1188511880, 1188511890
  ; 222220, 222224
  ; 1698522, 1698528
  ; 446443, 446449
  ; 38593856, 38593862
  ; 565653, 565659
  ; 824824821, 824824827
  ; 2121212118, 2121212124
  ]
;;

let ranges_2 =
  [ 17330, 35281
  ; 9967849351, 9967954114
  ; 880610, 895941
  ; 942, 1466
  ; 117855, 209809
  ; 9427633930, 9427769294
  ; 1, 14
  ; 311209, 533855
  ; 53851, 100089
  ; 104, 215
  ; 33317911, 33385573
  ; 42384572, 42481566
  ; 43, 81
  ; 87864705, 87898981
  ; 258952, 303177
  ; 451399530, 451565394
  ; 6464564339, 6464748782
  ; 1493, 2439
  ; 9941196, 10054232
  ; 2994, 8275
  ; 6275169, 6423883
  ; 20, 41
  ; 384, 896
  ; 2525238272, 2525279908
  ; 8884, 16221
  ; 968909030, 969019005
  ; 686256, 831649
  ; 942986, 986697
  ; 1437387916, 1437426347
  ; 8897636, 9031809
  ; 16048379, 16225280
  ]
;;

let streaming_testbench ranges (sim : Harness.Sim.t) =
  let inputs = Cyclesim.inputs sim in
  let outputs = Cyclesim.outputs sim in
  let cycle ?n () = Cyclesim.cycle ?n sim in
  (* Reset *)
  inputs.clear := Bits.vdd;
  cycle ();
  inputs.clear := Bits.gnd;
  cycle ();
  (* Stream of (lo, hi) ranges *)
  let last_sum = ref 0L in
  List.iter ranges ~f:(fun (lo, hi) ->
    inputs.data_lo <--. lo;
    inputs.data_hi <--. hi;
    inputs.data_in_valid := Bits.vdd;
    inputs.start := Bits.vdd;
    cycle ();
    inputs.start := Bits.gnd;
    inputs.data_in_valid := Bits.gnd;
    (* Wait for result *)
    while not (Bits.to_bool !(outputs.sum.valid)) do
      cycle ()
    done;
    last_sum := Bits.to_int64_trunc !(outputs.sum.value);
    (* Advance *)
    inputs.finish := Bits.vdd;
    cycle ();
    inputs.finish := Bits.gnd;
    cycle ());
  print_s [%message "Final streaming sum" (!last_sum : int64)]
;;

let run_with_waves ~name ranges =
  let display_rules =
    [ Display_rule.port_name_matches
        ~wave_format:(Bit_or Unsigned_int)
        (Re.Glob.glob "range_sum*" |> Re.compile)
    ]
  in
  Harness.run_advanced
    ~create:Range_sum.hierarchical
    ~trace:`All_named
    ~print_waves_after_test:(fun waves ->
      print_endline name;
      Waveform.print
        ~display_rules
        ~signals_width:30
        ~display_width:92
        ~wave_width:1
        waves)
    (streaming_testbench ranges)
;;

let%expect_test "range_sum waveforms (ranges_1)" =
  run_with_waves ~name:"ranges_1" ranges_1;
  [%expect {| ("Final streaming sum" (!last_sum 1227775554)) |}]
;;

let%expect_test "range_sum waveforms (ranges_2)" =
  run_with_waves ~name:"ranges_2" ranges_2;
  [%expect {| ("Final streaming sum" (!last_sum <computed>)) |}]
;;
