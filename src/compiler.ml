open Lang
open Lexing
open Contexts
open Typecheck

let string_of_position lexbuf =
  let pos = lexbuf.lex_curr_p in
  Printf.sprintf "%s:%d:%d"
    pos.pos_fname
    pos.pos_lnum
    (pos.pos_cnum - pos.pos_bol + 1)

let read eval programName lexbuf =
  match Parser.program Lexer.read lexbuf with
  | exception Lexer.SyntaxError msg ->
    Printf.fprintf stderr "Syntax error: %s at %s\n"
      (string_of_position lexbuf)
      msg
  | exception _ ->
    Printf.fprintf stderr "Syntax error at %s\n"
      (string_of_position lexbuf)
  | e -> eval { e with programName }

let read_file eval filename =
  let ic = open_in filename in
  let lexbuf = Lexing.from_channel ic in
  (* Get the program name by removing the full path, removing the
     file extension, and capitalizing the first character. *)
  let programName = filename
    |> Filename.remove_extension
    |> Filename.basename
    |> JavaCG.make_valid_java_ident
    |> String.capitalize_ascii in
  read eval programName lexbuf

let gamma_base = Env.from_bindings [
  "unsafeWrite", `Function ([`Promise `Int; `Int], `Unit);
  "sleep", `Function ([`Int], `Unit);
  "milliseconds", `Function ([`Int], `Int);
  "seconds", `Function ([`Int], `Int);
  "intToString", `Function ([`Int], `String);
  "boolToString", `Function ([`Bool], `String);
  "print", `Function ([`String], `Unit);
  "println", `Function ([`String], `Unit);
  "readFile", `Function ([`String], `String);
  "charAt", `Function ([`String; `Int], `String);
  "substring", `Function ([`String; `Int; `Int], `String);
  "concat", `Function ([`String; `String], `String);
  "length", `Function ([`String], `Int)
]

let eval_program ~output_file ~verbose ~benchmark_typechecker ~benchmark_pipeline program =
  let output_file =
    if !output_file = "" then program.programName ^ ".java"
    else !output_file in
  let gamma = gamma_base |> load_env program.funcs in
  let typecheck types func =
    if !verbose then begin
      print_endline (string_of_expr func.expr);
      print_endline "---------------";
    end;
    let preprocessed_func = Ident.preprocess_idents gamma func in
    let ty = typecheck_fn types gamma preprocessed_func in
    if !verbose then begin
      print_endline (func.funcName ^ ": " ^ string_of_ty ty);
      print_endline "---------------"
    end;
    preprocessed_func in
  let compile ?(write=true) program =
    let program = { program with funcs = List.map (typecheck program.types) program.funcs } in
    let javaProgram = JavaCG.emit_program program in
    if write then begin
      let oc = open_out output_file in
      output_string oc javaProgram;
      close_out oc
    end in
  if !benchmark_typechecker then begin
    let start_time = Sys.time () in
    for _ = 0 to 1000 do
      List.iter (fun func -> typecheck program.types func |> ignore) program.funcs;
    done;
    let end_time = Sys.time () in
    Printf.printf "Completed type checking benchmark for program '%s' in: %f seconds (1000 runs)\n"
      program.programName (end_time -. start_time)
  end else if !benchmark_pipeline then begin
    let start_time = Sys.time () in
    for _ = 0 to 1000 do
      compile ~write:false program
    done;
    let end_time = Sys.time () in
    Printf.printf "Completed full compiler benchmark for program '%s' in: %f seconds (1000 runs)\n"
      program.programName (end_time -. start_time)
  end else compile program

let () =
  let benchmark_typechecker = ref false
  and benchmark_pipeline = ref false
  and verbose = ref false
  and output_file = ref "" in
  let spec = [
    "--tybench", Arg.Set benchmark_typechecker, "Benchmark the typechecker (reports seconds per 1000 runs)";
    "--bench", Arg.Set benchmark_pipeline, "Benchmark the entire pipeline (reports seconds per 1000 runs)";
    "-v", Arg.Set verbose, "Print out extra debug information";
    "--verbose", Arg.Set verbose, "Print out extra debug information";
    "-o", Arg.Set_string output_file, "Set output file name (default to ./<Filename>.java if not provided)"
  ] in
  Arg.parse spec (fun filename ->
    read_file (eval_program ~benchmark_typechecker ~benchmark_pipeline ~verbose ~output_file) filename)
    "compiler [-o output_file] [--tybench|--bench] [-v|--verbose] <input_file>"
