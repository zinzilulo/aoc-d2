open! Core
open! Hardcaml
open! Hardcaml_waveterm
open! Hardcaml_test_harness
module Range_sum = Hardcaml_demo_project.Range_sum
module Harness = Cyclesim_harness.Make (Range_sum.I) (Range_sum.O)

let ( <--. ) = Bits.( <--. )

let streaming_testbench (sim : Harness.Sim.t) =
  let inputs = Cyclesim.inputs sim in
  let outputs = Cyclesim.outputs sim in
  let cycle ?n () = Cyclesim.cycle ?n sim in
  (* Reset *)
  inputs.clear := Bits.vdd;
  cycle ();
  inputs.clear := Bits.gnd;
  cycle ();
  let ranges =
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
  in
  let last_sum = ref 0L in
  List.iter ranges ~f:(fun (lo, hi) ->
    inputs.data_lo <--. lo;
    inputs.data_hi <--. hi;
    inputs.data_in_valid := Bits.vdd;
    inputs.start := Bits.vdd;
    cycle ();
    inputs.start := Bits.gnd;
    inputs.data_in_valid := Bits.gnd;
    while not (Bits.to_bool !(outputs.sum.valid)) do
      cycle ()
    done;
    last_sum := Bits.to_int64_trunc !(outputs.sum.value);
    inputs.finish := Bits.vdd;
    cycle ();
    inputs.finish := Bits.gnd;
    cycle ());
  print_s [%message "Final streaming sum" (!last_sum : int64)]
;;

let waves_config = Waves_config.no_waves

let%expect_test "range_sum streaming with printed waveforms" =
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
      Waveform.print
        ~display_rules
        ~signals_width:30
        ~display_width:92
        ~wave_width:1
        waves)
    streaming_testbench;
  [%expect {| (Final streaming sum <computed>) |}]
;;

let%expect_test "Streaming test for range_sum" =
  Harness.run_advanced ~waves_config ~create:Range_sum.hierarchical streaming_testbench;
  [%expect {| (Result (sum 1227775554)) |}]
;;
