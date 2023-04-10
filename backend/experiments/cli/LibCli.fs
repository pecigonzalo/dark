module Cli.LibCli

open System.Threading.Tasks
open FSharp.Control.Tasks

open Prelude
open LibExecution.RuntimeTypes

module Errors = LibExecution.Errors

let fn = FQFnName.stdlibFnName

let err (str : string) = Ply(Dval.errStr str)

let incorrectArgs = Errors.incorrectArgs

let varA = TVariable "a"


let fns : List<BuiltInFn> =
  [ { name = fn "" "print" 0
      typeParams = []
      parameters = [ Param.make "value" varA "The value to be printed." ]
      returnType = TUnit
      description = "Prints the given <param value> to the standard output."
      fn =
        (function
        | _, _, [ value ] ->
          let str = LibExecution.DvalReprDeveloper.toRepr value
          print str
          Ply(DUnit)
        | _ -> incorrectArgs ())
      sqlSpec = NotYetImplemented
      previewable = Impure
      deprecated = NotDeprecated }

    { name = fn "File" "read" 0
      typeParams = []
      parameters = [ Param.make "path" TString "" ]
      returnType = TResult(TBytes, TString)
      description =
        "Reads the contents of a file specified by <param path> asynchronously and returns its contents as Bytes wrapped in a Result"
      fn =
        (function
        | _, _, [ DString path ] ->
          uply {
            try
              let! contents = System.IO.File.ReadAllBytesAsync path
              return DResult(Ok(DBytes contents))
            with
            | e -> return DResult(Error(DString($"Error reading file: {e.Message}")))
          }
        | _ -> incorrectArgs ())
      sqlSpec = NotQueryable
      previewable = Impure
      deprecated = NotDeprecated }

    { name = fn "File" "write" 0
      typeParams = []
      parameters = [ Param.make "path" TString ""; Param.make "contents" TBytes "" ]
      returnType = TResult(TUnit, TString)
      description =
        "Writes the specified byte array <param contents> to the file specified by <param path> asynchronously"
      fn =
        (function
        | _, _, [ DString path; DBytes contents ] ->
          uply {
            try
              do! System.IO.File.WriteAllBytesAsync(path, contents)
              return DResult(Ok(DUnit))
            with
            | e -> return DResult(Error(DString($"Error writing file: {e.Message}")))
          }
        | _ -> incorrectArgs ())
      sqlSpec = NotQueryable
      previewable = Impure
      deprecated = NotDeprecated } ]
