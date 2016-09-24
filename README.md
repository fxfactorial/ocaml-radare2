OCaml interface to radare2
-------------------------------

This is an OCaml interface to radare2, the reverse engineer's dream
tool.

## Installation

You can install it using `opam` the OCaml package manager,
see [here](http://hyegar.com/2015/10/20/so-youre-learning-ocaml/) for
a quick introduction to the OCaml ecosystem and how to get opam.

If not on opam or wanting to use the latest and greatest then do:

```
$ opam pin add radare2 git@github.com:fxfactorial/ocaml-radare2.git -y
```

Otherwise use the one on `opam`

```
$ opam install radare2 -y
```

## Example usage:

Here's a utop session, (`opam install utop`)

```ocaml
#require "radare2";;
let result = R2.with_command_j ~cmd:"/j chown" "/bin/ls";;
val result : Yojson.Basic.json =
`List 
  [`Assoc
    [("offset", `Int 4294987375); ("id:", `Int 0);
     ("data", `String "ywritesecuritychownfile_inheritdi")]]"
```


## Documentation

Here is the `mli` with comments, fairly simple and high level.

```ocaml

(** A running instance of r2 *)
type r2

(** Send a command to r2, get back plain string output *)
val command : r2:r2 -> string -> string

(** Send a command to r2, get back Yojson. If output isn't JSON
    parsable then raises {Invalid_argument} so make sure command starts
    with /j *)
val command_json : r2:r2 -> string -> Yojson.Basic.json

(** Create a r2 instance with a given file, raises {Invalid_argument}
    if file doesn't exists *)
val open_file : string -> r2

(** close a r2 instance *)
val close : r2 -> unit

(** Convenience function for opening a r2 instance, sending a command,
    getting the result as plain string and closing the r2 instance *)
val with_command : cmd:string -> string -> string

(** Convenience function for opening a r2 instance, sending a command,
    getting the result as Yojson and closing the r2 instance *)
val with_command_j : cmd:string -> string -> Yojson.Basic.json
```
