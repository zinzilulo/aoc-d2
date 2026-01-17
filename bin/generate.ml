open! Core
open! Hardcaml
open! Hardcaml_demo_project

let generate_range_sum_rtl () =
  let module C = Circuit.With_interface (Range_sum.I) (Range_sum.O) in
  let scope = Scope.create ~auto_label_hierarchical_ports:true () in
  let circuit = C.create_exn ~name:"range_sum_top" (Range_sum.hierarchical scope) in
  let rtl_circuits =
    Rtl.create ~database:(Scope.circuit_database scope) Verilog [ circuit ]
  in
  let rtl = Rtl.full_hierarchy rtl_circuits |> Rope.to_string in
  print_endline rtl
;;

let range_sum_rtl_command =
  Command.basic
    ~summary:""
    [%map_open.Command
      let () = return () in
      fun () -> generate_range_sum_rtl ()]
;;

let () =
  Command_unix.run (Command.group ~summary:"" [ "range-sum", range_sum_rtl_command ])
;;
