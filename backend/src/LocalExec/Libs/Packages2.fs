/// Package functions that require access to other types/fns in this module
module LocalExec.Libs.Packages2

open System.Threading.Tasks
open FSharp.Control.Tasks

open Prelude
open LibExecution.RuntimeTypes
open LibExecution.Builtin.Shortcuts

module VT = ValueType
module Dval = LibExecution.Dval
module PT2DT = LibExecution.ProgramTypesToDarkTypes

let packageManager = LibCloud.PackageManager.packageManager

let resolver : LibParser.NameResolver.NameResolver =
  let builtinResolver =
    // CLEANUP we need a better way to determine what builtins should be
    // available to the name resolver, as this currently assumes builtins
    // from _all_ environments are available
    LibExecution.Builtin.combine
      // We are missing the builtins that contain this function (and all associated ones)
      [ BuiltinExecution.Builtin.contents
          BuiltinExecution.Libs.HttpClient.defaultConfig
        BuiltinCli.Builtin.contents
        Packages.contents
        Cli.contents
        TestUtils.LibTest.contents
        BuiltinCloudExecution.Builtin.contents
        BuiltinCliHost.Builtin.contents ]
      []
    |> LibParser.NameResolver.fromBuiltins

  let thisResolver =
    { LibParser.NameResolver.empty with
        allowError = false
        builtinFns =
          Set
            [ LibExecution.ProgramTypes.FnName.builtIn
                [ "LocalExec"; "Packages" ]
                "parseAndSave"
                0
              LibExecution.ProgramTypes.FnName.builtIn
                [ "LocalExec"; "Packages" ]
                "parse"
                0 ] }

  LibParser.NameResolver.merge builtinResolver thisResolver (Some packageManager)



let fns : List<BuiltInFn> =
  [ { name = fn [ "LocalExec"; "Packages" ] "parse" 0
      typeParams = []
      parameters =
        [ Param.make "package source" TString "The source code of the package"
          Param.make "filename" TString "Used for error message" ]
      returnType =
        TypeReference.result
          (TCustomType(
            Ok(FQName.BuiltIn(typ [ "LocalExec"; "Packages" ] "Package" 0)),
            []
          ))
          TString
      description = "Parse a package"
      fn =
        function
        | _, _, [ DString contents; DString path ] ->
          uply {
            let! (fns, types, constants) =
              LibParser.Parser.parsePackageFile resolver path contents

            let packagesFns = fns |> List.map PT2DT.PackageFn.toDT
            let packagesTypes = types |> List.map PT2DT.PackageType.toDT
            let packagesConstants = constants |> List.map PT2DT.PackageConstant.toDT

            let typeName =
              FQName.BuiltIn(typ [ "LocalExec"; "Packages" ] "Package" 0)
            let fields =
              [ "fns", DList(VT.customType PT2DT.PackageFn.typeName [], packagesFns)
                "types",
                DList(VT.customType PT2DT.PackageType.typeName [], packagesTypes)
                "constants",
                DList(
                  VT.customType PT2DT.PackageConstant.typeName [],
                  packagesConstants
                ) ]
            return
              DRecord(typeName, typeName, [], Map fields)
              |> Dval.resultOk (KTCustomType(typeName, [])) KTString
          }
        | _ -> incorrectArgs ()
      sqlSpec = NotQueryable
      previewable = Impure
      deprecated = NotDeprecated } ]


let contents : LibExecution.Builtin.Contents = (fns, [], [])
