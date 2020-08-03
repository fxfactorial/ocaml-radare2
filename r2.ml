type r2 = {
  pid : int;
  fdw : Unix.file_descr;
  fdr : Unix.file_descr;
}

let bufsize = 512

let find_null data ~pos ~len =
  let rec find pos =
    if pos < len
    then if Bytes.get data pos = '\000'
      then Some pos else find (pos+1)
    else None in
  find pos

exception No_input

let rec read_spin fd data =
  match Unix.read fd data 0 (Bytes.length data) with
  | exception (Unix.Unix_error ((Unix.EAGAIN | EWOULDBLOCK),_,_)) ->
    read_spin fd data
  | 0 -> raise No_input
  | n -> n

let read {fdr; _} =
  let buf = Buffer.create bufsize in
  let data = Bytes.create bufsize in
  let rec fill () =
    let len = read_spin fdr data in
    match find_null data ~pos:0 ~len with
    | None -> Buffer.add_subbytes buf data 0 len; fill ()
    | Some pos -> Buffer.add_subbytes buf data 0 pos in
  fill ();
  Buffer.contents buf

let send_command r2 cmd =
  let c = Printf.sprintf "%s\n" cmd in
  ignore (Unix.write_substring r2.fdw c 0 (String.length c));
  read r2

let command ~r2 cmd = send_command r2 cmd

let parse_json s =
  (Yojson.Safe.from_string s :> Yojson.t)

let command_json ~r2 cmd =
  try
    send_command r2 cmd |> parse_json
  with
    Yojson.Json_error _ ->
    raise (Invalid_argument "Output wasn't JSON parsable, \
                             make sure you used /j")

module Version : sig
  val supported : unit Lazy.t
end
= struct
  let system_error msg =
    invalid_arg ("Failed to run radare2: " ^ Unix.error_message msg)

  let try_finally f x ~finally =
    try let r = f x in finally x; r
    with exn -> finally x; raise exn

  let read_version () =
    match Unix.open_process_in "radare2 -qv" with
    | exception Unix.Unix_error (msg,_,_) -> system_error msg
    | output -> try_finally input_line output
                  ~finally:close_in

  let extract_number str pos len =
    try int_of_string (String.sub str pos len)
    with Failure _ -> invalid_arg "invalid version format"

  let parse ver =
    let len = String.length ver in
    match String.index ver '.' with
    | exception Not_found -> extract_number ver 0 len,0
    | pos ->
      extract_number ver 0 pos,
      if pos = len - 1 then 0
      else match String.index_from ver (pos+1) '.' with
        | exception Not_found ->
          if pos = len - 1 then 0
          else extract_number ver (pos+1) (len-pos-1)
        | dot ->
          extract_number ver (pos+1) (dot-pos-1)

  let supported = lazy begin
    let version = parse @@ read_version () in
    if version < (2,3)
    then invalid_arg "incompatible radare version: please install r2 >= 2.3.0"
  end
end

let close ({pid; fdw; fdr; _} as r2) =
  let _ : string = command ~r2 "q" in
  List.iter Unix.close [fdw; fdr];
  match Unix.waitpid [] pid with
  | _,Unix.WEXITED 0 -> ()
  | _,Unix.WEXITED n ->
    failwith ("radare2 terminated with a non-zero exit code: " ^
              string_of_int n)
  | _,Unix.WSIGNALED _
  | _,Unix.WSTOPPED _ -> failwith "radare2 was killed"

let readall ch =
  let buf = Buffer.create bufsize in
  let rec read () = Buffer.add_channel buf ch bufsize; read () in
  try read () with End_of_file -> Buffer.contents buf



let open_file f_name =
  let lazy () = Version.supported in
  if not (Sys.file_exists f_name) then
    raise (Invalid_argument "Non-existent file")
  else
    let i_r, i_w = Unix.pipe ()
    and o_r, o_w = Unix.pipe ()
    and e_r, e_w = Unix.pipe () in
    match Unix.fork () with
    | 0 ->
      Unix.dup2 i_r Unix.stdin;
      Unix.dup2 o_w Unix.stdout;
      Unix.dup2 e_w Unix.stderr;
      Unix.execv "/bin/sh" [|"/bin/sh"; "-c"; "radare2 -q0 " ^ f_name|]
    | pid ->
      List.iter Unix.close [i_r; o_w; e_w];
      Unix.set_nonblock o_r;
      let err = Unix.in_channel_of_descr e_r in
      let r2 = {pid; fdw=i_w; fdr=o_r} in
      match read r2 with
      | exception No_input ->
        List.iter Unix.close [i_w; o_r];
        let problem = readall err in
        close_in err;
        invalid_arg ("Failed to start radare2 process: " ^ problem)
      | "" -> r2
      | s ->
        close r2;
        failwith ("spurious output on open: " ^ s)

let with_command ~cmd f_name =
  let r2 = open_file f_name in
  let output = command ~r2 cmd in
  close r2;
  output

let with_command_j ~cmd f_name =
  let r2 = open_file f_name in
  let output = command ~r2 cmd in
  close r2;
  output |> parse_json
