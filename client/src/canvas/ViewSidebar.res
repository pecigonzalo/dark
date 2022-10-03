open Prelude
open ViewUtils
module B = BlankOr
module TL = Toplevel
module TD = TLID.Dict
module Cmd = Tea.Cmd

type modification = AppTypes.modification
type model = AppTypes.model
type msg = AppTypes.msg
module Mod = AppTypes.Modification

let fontAwesome = Icons.fontAwesome

let tw = Attrs.class
let tw2 = (c1, c2) => Attrs.class(`${c1} ${c2}`)
let tw3 = (c1, c2, c3) => Attrs.class(`${c1} ${c2} ${c3}`)

let missingEventRouteDesc: string = "Undefined"

let delPrefix: string = "deleted-"

type identifier =
  | Tlid(TLID.t)
  | Other(string)

type onClickAction =
  | Destination(AppTypes.Page.t)
  | SendMsg(msg)
  | DoNothing

let tlidOfIdentifier = (identifier): option<TLID.t> =>
  switch identifier {
  | Tlid(tlid) => Some(tlid)
  | Other(_) => None
  }

let entryKeyFromIdentifier = (identifier): string =>
  switch identifier {
  | Tlid(tlid) => "entry-" ++ TLID.toString(tlid)
  | Other(s) => "entry-" ++ s
  }

type rec entry = {
  name: string,
  identifier: identifier,
  onClick: onClickAction,
  uses: option<int>,
  minusButton: option<msg>,
  plusButton: option<msg>,
  // if this is in the deleted section, what does minus do?
  killAction: option<msg>,
  verb: option<string>,
}

and category = {
  count: int,
  name: string,
  plusButton: option<msg>,
  iconAction: option<msg>,
  icon: Html.html<msg>,
  emptyName: string, // what if there's none
  tooltip: option<AppTypes.Tooltip.source>,
  entries: list<item>,
}

and nestedCategory = {
  count: int,
  name: string,
  icon: Html.html<msg>,
  entries: list<item>,
}

and item =
  | NestedCategory(nestedCategory)
  | Entry(entry)

let rec count = (s: item): int =>
  switch s {
  | Entry(_) => 1
  | NestedCategory(c) => (c.entries |> List.map(~f=count))->List.sum(module(Int))
  }

module Styles = {
  let categoryNameBase = %twc(
    "block text-grey8 font-bold mt-0 tracking-wide w-full font-heading -ml-4"
  )
  let contentCategoryName = %twc("text-lg text-center ") ++ categoryNameBase

  let nestedSidebarCategoryName = %twc("text-base text-left ") ++ categoryNameBase

  let sidebarCategory = %twc("mb-5 pl-2 pr-0.5 py-0 relative group-sidebar-category")

  let content = %twc(
    "absolute pl-4 bg-sidebar-bg p-1.25 mt-2.5 pb-2.5 min-w-[20em] max-w-2xl max-h-96 overflow-y-scroll shadow-[2px_2px_2px_0_var(--black1)] z-[1] -top-5 left-14 scrollbar-corner-transparent scrollbar-thin"
  )

  let contentVisibility = %twc("hidden group-sidebar-category-hover:block")
}

let iconButton = (~key: string, ~icon: string, ~style: string, handler: msg): Html.html<msg> => {
  let twStyle = %twc("hover:text-sidebar-hover cursor-pointer")
  let event = EventListeners.eventNeither(~key, "click", _ => handler)
  Html.div(list{event, tw2(style, twStyle)}, list{fontAwesome(icon)})
}

let handlerCategory = (
  filter: toplevel => bool,
  name: string,
  emptyName: string,
  action: AppTypes.AutoComplete.omniAction,
  iconAction: option<msg>,
  icon: Html.html<msg>,
  tooltip: AppTypes.Tooltip.source,
  hs: list<PT.Handler.t>,
): category => {
  let handlers = hs |> List.filter(~f=h => filter(TLHandler(h)))
  {
    count: List.length(handlers),
    name: name,
    emptyName: emptyName,
    plusButton: Some(CreateRouteHandler(action)),
    iconAction: iconAction,
    icon: icon,
    tooltip: Some(tooltip),
    entries: List.map(handlers, ~f=h => {
      Entry({
        name: PT.Handler.Spec.name(h.spec) |> B.valueWithDefault(missingEventRouteDesc),
        uses: None,
        identifier: Tlid(h.tlid),
        onClick: Destination(FocusedHandler(h.tlid, None, true)),
        minusButton: None,
        killAction: Some(ToplevelDeleteForever(h.tlid)),
        plusButton: None,
        verb: if TL.isHTTPHandler(TLHandler(h)) {
          h.spec->PT.Handler.Spec.modifier->Option.andThen(~f=B.toOption)
        } else {
          None
        },
      })
    }),
  }
}

let httpCategory = (handlers: list<PT.Handler.t>): category =>
  handlerCategory(
    TL.isHTTPHandler,
    "HTTP",
    "HTTP handlers",
    NewHTTPHandler(None),
    Some(GoToArchitecturalView),
    Icons.darkIcon("http"),
    Http,
    handlers,
  )

let cronCategory = (handlers: list<PT.Handler.t>): category =>
  handlerCategory(
    TL.isCronHandler,
    "Cron",
    "Crons",
    NewCronHandler(None),
    Some(GoToArchitecturalView),
    Icons.darkIcon("cron"),
    Cron,
    handlers,
  )

let replCategory = (handlers: list<PT.Handler.t>): category =>
  handlerCategory(
    TL.isReplHandler,
    "REPL",
    "REPLs",
    NewReplHandler(None),
    Some(GoToArchitecturalView),
    fontAwesome("terminal"),
    Repl,
    handlers,
  )

let workerCategory = (handlers: list<PT.Handler.t>): category => {
  // Show the old workers here for now
  let isWorker = tl => TL.isWorkerHandler(tl) || TL.isDeprecatedCustomHandler(tl)
  handlerCategory(
    isWorker,
    "Worker",
    "Workers",
    NewWorkerHandler(None),
    Some(GoToArchitecturalView),
    fontAwesome("wrench"),
    Worker,
    handlers,
  )
}

let dbCategory = (m: model, dbs: list<PT.DB.t>): category => {
  count: List.length(dbs),
  name: "Datastores",
  emptyName: "Datastores",
  plusButton: Some(CreateDBTable),
  iconAction: Some(GoToArchitecturalView),
  icon: Icons.darkIcon("db"),
  tooltip: Some(Datastore),
  entries: dbs->List.map(~f=db => {
    let uses = db.name == "" ? 0 : Refactor.dbUseCount(m, db.name)
    Entry({
      name: db.name == "" ? "Untitled DB" : db.name,
      identifier: Tlid(db.tlid),
      uses: Some(uses),
      onClick: Destination(FocusedDB(db.tlid, true)),
      minusButton: None,
      killAction: Some(ToplevelDeleteForever(db.tlid)),
      verb: None,
      plusButton: None,
    })
  }),
}

let f404Category = (m: model): category => {
  let f404s = {
    // Generate set of deleted handler specs, stringified
    let deletedHandlerSpecs =
      m.deletedHandlers
      |> Map.values
      |> List.map(~f=(h: PT.Handler.t) => {
        let space = h.spec->PT.Handler.Spec.space->B.toString
        let name = h.spec->PT.Handler.Spec.name->B.toString
        let modifier = h.spec->PT.Handler.Spec.modifier->B.optionToString
        // Note that this concatenated string gets compared to `space ++ path ++ modifier` later.
        // h.spec.name and f404.path are the same thing, with different names. Yes this is confusing.
        space ++ name ++ modifier
      })
      |> Set.String.fromList

    m.f404s
    |> List.uniqueBy(~f=(f: AnalysisTypes.FourOhFour.t) => f.space ++ f.path ++ f.modifier)
    |> // Don't show 404s for deleted handlers
    List.filter(~f=(f: AnalysisTypes.FourOhFour.t) =>
      !Set.member(~value=f.space ++ f.path ++ f.modifier, deletedHandlerSpecs)
    )
  }

  {
    count: List.length(f404s),
    name: "404s",
    emptyName: "404s",
    plusButton: None,
    iconAction: None,
    icon: Icons.darkIcon("fof"),
    tooltip: Some(FourOhFour),
    entries: List.map(f404s, ~f=({space, path, modifier, _} as fof) => Entry({
      name: space == "HTTP" ? path : space ++ " " ++ path,
      uses: None,
      identifier: Other(fof.space ++ fof.path ++ fof.modifier),
      onClick: SendMsg(CreateHandlerFrom404(fof)),
      minusButton: Some(Delete404APICall(fof)),
      killAction: None,
      plusButton: Some(CreateHandlerFrom404(fof)),
      verb: space == "WORKER" ? None : Some(modifier),
    })),
  }
}

let userFunctionCategory = (m: model, ufs: list<PT.UserFunction.t>): category => {
  let fns = ufs |> List.filter(~f=(fn: PT.UserFunction.t) => fn.name != "")
  {
    count: List.length(fns),
    name: "Functions",
    emptyName: "Functions",
    plusButton: Some(CreateFunction),
    iconAction: Some(GoToArchitecturalView),
    icon: Icons.darkIcon("fn"),
    tooltip: Some(Function),
    entries: fns->List.map(~f=fn => {
      Entry({
        name: fn.name,
        identifier: Tlid(fn.tlid),
        uses: Introspect.allUsedIn(fn.tlid, m)->List.length->Some,
        minusButton: None,
        killAction: Some(DeleteUserFunctionForever(fn.tlid)),
        onClick: Destination(FocusedFn(fn.tlid, None)),
        plusButton: None,
        verb: None,
      })
    }),
  }
}

let userTipeCategory = (m: model, tipes: list<PT.UserType.t>): category => {
  let tipes = tipes |> List.filter(~f=(ut: PT.UserType.t) => ut.name != "")
  {
    count: List.length(tipes),
    name: "Types",
    emptyName: "Types",
    plusButton: Some(CreateType),
    iconAction: None,
    icon: Icons.darkIcon("types"),
    tooltip: None,
    entries: List.map(tipes, ~f=tipe => {
      let minusButton = if Refactor.usedTipe(m, tipe.name) {
        None
      } else {
        Some(Msg.DeleteUserType(tipe.tlid))
      }

      Entry({
        name: tipe.name,
        identifier: Tlid(tipe.tlid),
        uses: Some(Refactor.tipeUseCount(m, tipe.name)),
        minusButton: minusButton,
        killAction: Some(DeleteUserTypeForever(tipe.tlid)),
        onClick: Destination(FocusedType(tipe.tlid)),
        plusButton: None,
        verb: None,
      })
    }),
  }
}

let standardCategories = (m, hs, dbs, ufns, types) => {
  let hs = hs |> Map.values |> List.sortBy(~f=tl => TL.sortkey(TLHandler(tl)))
  let dbs = dbs |> Map.values |> List.sortBy(~f=tl => TL.sortkey(TLDB(tl)))
  let ufns = ufns |> Map.values |> List.sortBy(~f=tl => TL.sortkey(TLFunc(tl)))
  let types = types |> Map.values |> List.sortBy(~f=tl => TL.sortkey(TLTipe(tl)))

  // We want to hide user defined types for users who arent already using them
  // since there is currently no way to use them other than as a function param.
  // we should show user defined types once the user can use them more
  let types = types == list{} ? list{} : list{userTipeCategory(m, types)}

  list{
    httpCategory(hs),
    workerCategory(hs),
    cronCategory(hs),
    replCategory(hs),
    dbCategory(m, dbs),
    userFunctionCategory(m, ufns),
    ...types,
  }
}

let packageManagerCategory = (fns: packageFns): category => {
  let fnNameEntries = (moduleList: list<PT.Package.Fn.t>): list<item> => {
    let fnNames =
      moduleList
      ->List.sortBy(~f=(fn: PT.Package.Fn.t) => fn.name.module_)
      ->List.uniqueBy(~f=(fn: PT.Package.Fn.t) => fn.name.function)

    fnNames->List.map(~f=(fn: PT.Package.Fn.t) => Entry({
      name: fn.name.module_ ++ "::" ++ fn.name.function ++ "_v" ++ string_of_int(fn.name.version),
      identifier: Tlid(fn.tlid),
      onClick: Destination(FocusedPackageManagerFn(fn.tlid)),
      uses: None,
      minusButton: None,
      plusButton: None,
      killAction: None,
      verb: None,
    }))
  }

  let packageEntries = (userList: list<PT.Package.Fn.t>): list<item> => {
    let uniquePackages =
      userList
      ->List.sortBy(~f=(fn: PT.Package.Fn.t) => fn.name.package)
      ->List.uniqueBy(~f=(fn: PT.Package.Fn.t) => fn.name.package)

    uniquePackages->List.map(~f=fn => {
      let packageList = userList->List.filter(~f=f => fn.name.package == f.name.package)

      NestedCategory({
        count: List.length(uniquePackages),
        name: fn.name.package,
        icon: fontAwesome("cubes"),
        entries: fnNameEntries(packageList),
      })
    })
  }

  let uniqueAuthors =
    fns
    ->Map.values
    ->List.sortBy(~f=(fn: PT.Package.Fn.t) => fn.name.owner)
    ->List.uniqueBy(~f=(fn: PT.Package.Fn.t) => fn.name.owner)

  let authorEntries = uniqueAuthors->List.map(~f=(fn: PT.Package.Fn.t) => {
    let authorList = fns->Map.values->List.filter(~f=f => fn.name.owner == f.name.owner)

    NestedCategory({
      count: List.length(uniqueAuthors),
      name: fn.name.owner,
      icon: fontAwesome("user"),
      entries: packageEntries(authorList),
    })
  })

  {
    count: List.length(uniqueAuthors),
    name: "Package Manager",
    emptyName: "Packages",
    plusButton: None,
    iconAction: None,
    icon: fontAwesome("box-open"),
    tooltip: Some(PackageManager),
    entries: authorEntries,
  }
}

let deletedCategory = (m: model): category => {
  let cats = standardCategories(
    m,
    m.deletedHandlers,
    m.deletedDBs,
    m.deletedUserFunctions,
    m.deleteduserTypes,
  )->List.map(~f=(c: category): nestedCategory => {
    name: c.name,
    count: c.count,
    icon: c.icon,
    entries: c.entries->List.map(~f=item =>
      switch item {
      | Entry(e) =>
        let actionOpt =
          e.identifier->tlidOfIdentifier->Option.map(~f=tlid => Msg.RestoreToplevel(tlid))

        Entry({
          ...e,
          plusButton: actionOpt,
          uses: None,
          minusButton: e.killAction,
          onClick: actionOpt->Option.map(~f=msg => SendMsg(msg))->Option.unwrap(~default=DoNothing),
        })
      | NestedCategory(_) => item
      }
    ),
  })

  {
    count: cats->List.map(~f=c => count(NestedCategory(c)))->List.sum(module(Int)),
    name: "Deleted",
    emptyName: "Deleted elements",
    plusButton: None,
    iconAction: None,
    icon: Icons.darkIcon("deleted"),
    tooltip: Some(Deleted),
    entries: cats->List.map(~f=c => NestedCategory(c)),
  }
}

// ---------------
// Render the nested categories
// ---------------

let categoryButton = (~props=list{}, description: string, icon: Html.html<msg>): Html.html<msg> =>
  Html.div(
    list{
      tw(
        %twc(
          "mr-0 text-2xl text-grey5 duration-200 group-sidebar-category-hover:text-3xl w-9 h-9 text-center"
        ),
      ),
      Attrs.title(description),
      Attrs.role("img"),
      Attrs.alt(description),
      ...props,
    },
    list{icon},
  )

let viewEmptyCategoryContents = (name: string): Html.html<msg> => {
  Html.div(list{tw2(%twc("ml-3 mt-4 text-sidebar-secondary"), "")}, list{Html.text("No " ++ name)})
}

let viewSidebarButton = (
  m: model,
  name: string,
  plusButton: option<msg>,
  icon: Html.html<msg>,
  iconAction: option<msg>,
): Html.html<msg> => {
  let plusButton = switch plusButton {
  | Some(msg) if m.permission == Some(ReadWrite) =>
    let style = %twc("text-xs self-end hover:text-sidebar-hover hover:cursor-pointer")
    iconButton(~key="plus-" ++ name, ~icon="plus-circle", ~style, msg)
  | Some(_) | None => Vdom.noNode
  }

  let icon = {
    let props = switch iconAction {
    | Some(ev) => list{EventListeners.eventNeither(~key="return-to-arch", "click", _ => ev)}
    | None => list{Vdom.noProp}
    }

    categoryButton(name, icon, ~props)
  }
  let style = %twc("outline-none flex justify-start items-center w-full")
  Html.div(list{tw(style)}, list{icon, plusButton})
}

let viewEntry = (m: model, e: entry): Html.html<msg> => {
  let isSelected = tlidOfIdentifier(e.identifier) == CursorState.tlidOf(m.cursorState)

  let pluslink = switch e.plusButton {
  | Some(msg) if m.permission == Some(ReadWrite) =>
    iconButton(
      ~key=e.name ++ "-plus",
      ~icon="plus-circle",
      ~style=%twc(
        "ml-1.5 group-sidebar-addbutton-hover:text-sidebar-hover inline-block text-grey8"
      ),
      msg,
    )
  | Some(_) | None => Vdom.noNode
  }

  let linkItem = {
    // We add pluslink here as it's hard to get into place otherwise
    let verb = switch e.verb {
    | Some(verb) =>
      let verbStyle = switch verb {
      | "GET" => %twc("text-http-get")
      | "POST" => %twc("text-http-post")
      | "PUT" => %twc("text-http-put")
      | "DELETE" => %twc("text-http-delete")
      | "PATCH" => %twc("text-http-patch")
      | "HEAD" => %twc("text-white2") // TODO
      | "OPTIONS" => %twc("text-http-options")
      | _ => %twc("text-white2")
      }
      Html.span(list{tw2(verbStyle, "ml-4")}, list{Html.text(verb), pluslink})
    | _ => pluslink
    }

    let contents = switch e.onClick {
    | Destination(dest) =>
      let selected = {
        // font-black is same as fa-solid, font-medium produces the empty circle
        let dotStyle = if isSelected {
          %twc("inline-block text-sidebar-hover group-hover:text-orange font-black")
        } else {
          %twc("inline-block text-transparent group-hover:text-sidebar-hover font-medium")
        }
        // unclear why both align-middle and mb-[2px] are needed to make the dot center
        let baseStyle = %twc("text-xxs pl-0.25 pr-0.5 align-middle mb-[2px]")
        fontAwesome(~style=`${baseStyle} ${dotStyle}`, "circle")
      }

      let cls = {
        let unused = e.uses == Some(0) ? %twc("text-sidebar-secondary") : ""
        let default = %twc(
          "flex justify-between cursor-pointer w-full text-sidebar-primary no-underline outline-none"
        )

        `${default} ${unused}`
      }

      list{Url.linkFor(dest, cls, list{Html.span(list{}, list{selected, Html.text(e.name)}), verb})}

    | SendMsg(_) =>
      let pointer = m.permission == Some(ReadWrite) ? %twc("cursor-pointer") : ""
      list{
        Html.span(
          list{tw2(pointer, %twc("flex justify-between w-full"))},
          list{Html.text(e.name), verb},
        ),
      }
    | DoNothing => list{Html.text(e.name), verb}
    }

    let action = switch e.onClick {
    | SendMsg(msg) if m.permission == Some(ReadWrite) =>
      EventListeners.eventNeither(~key=e.name ++ "-clicked-msg", "click", _ => msg)
    | SendMsg(_) | DoNothing | Destination(_) => Vdom.noProp
    }

    Html.span(list{tw(%twc("w-full group inline-block group-sidebar-addbutton")), action}, contents)
  }

  // This prevents the delete button appearing
  // We'll add it back in for 404s specifically at some point
  let minuslink = switch e.minusButton {
  | Some(msg) if m.permission == Some(ReadWrite) =>
    iconButton(
      ~key=entryKeyFromIdentifier(e.identifier),
      ~style=%twc("mr-3 text-sidebar-secondary"),
      ~icon="minus-circle",
      msg,
    )
  | Some(_) | None => Vdom.noNode
  }

  Html.div(list{tw(%twc("mt-1.25 flex"))}, list{minuslink, linkItem})
}

let rec viewItem = (m: model, s: item): Html.html<msg> =>
  switch s {
  | NestedCategory(c) =>
    if c.count > 0 {
      viewNestedCategory(m, c)
    } else {
      Vdom.noNode
    }
  | Entry(e) => viewEntry(m, e)
  }

and viewNestedCategory = (m: model, c: nestedCategory): Html.html<msg> => {
  let titleStyle = Styles.nestedSidebarCategoryName
  let title = Html.span(list{tw(titleStyle)}, list{Html.text(c.name)})
  let entries = List.map(~f=viewItem(m), c.entries)

  Html.div(
    list{tw(Styles.sidebarCategory)},
    list{Html.div(list{tw(%twc("pl-4"))}, list{title, ...entries})},
  )
}

let viewToplevelCategory = (m: model, c: category): Html.html<msg> => {
  let button = viewSidebarButton(m, c.name, c.plusButton, c.icon, c.iconAction)
  let content = {
    let title = Html.span(list{tw(Styles.contentCategoryName)}, list{Html.text(c.name)})

    let entries = if c.count > 0 {
      List.map(~f=viewItem(m), c.entries)
    } else {
      list{viewEmptyCategoryContents(c.emptyName)}
    }

    Html.div(
      list{tw3("category-content", Styles.content, Styles.contentVisibility)},
      list{title, ...entries},
    )
  }

  Html.div(list{tw(Styles.sidebarCategory)}, list{button, content})
}

// ---------------
// Deploys
// ---------------

let viewDeploy = (d: StaticAssets.Deploy.t): Html.html<msg> => {
  let statusString = switch d.status {
  | Deployed => "Deployed"
  | Deploying => "Deploying"
  }

  let copyBtn = Html.div(
    list{
      tw(%twc("text-xs absolute -top-2 -right-1.5 hover:text-sidebar-hover")),
      EventListeners.eventNeither(
        "click",
        ~key="hash-" ++ d.deployHash,
        m => Msg.ClipboardCopyLivevalue("\"" ++ d.deployHash ++ "\"", m.mePos),
      ),
    },
    list{fontAwesome("copy")},
  )

  let statusColor = switch d.status {
  | Deployed => %twc("text-green")
  | Deploying => %twc("text-sidebar-secondary")
  }

  Html.div(
    list{tw(%twc("flex flex-wrap justify-between items-center mt-4"))},
    list{
      Html.div(
        list{
          tw(
            %twc(
              "relative inline-block border border-solid border-sidebar-secondary p-0.5 rounded-sm"
            ),
          ),
        },
        list{
          Html.a(
            list{
              tw(%twc("text-sm text-sidebar-primary hover:text-sidebar-hover no-underline")),
              Attrs.href(d.url),
              Attrs.target("_blank"),
            },
            list{Html.text(d.deployHash)},
          ),
          copyBtn,
        },
      ),
      Html.div(list{tw2(statusColor, %twc("inline-block"))}, list{Html.text(statusString)}),
      Html.div(
        list{tw(%twc("block w-full text-xxs text-right"))},
        list{Html.text(Js.Date.toUTCString(d.lastUpdate))},
      ),
    },
  )
}

let viewDeployStats = (m: model): Html.html<msg> => {
  let button = viewSidebarButton(m, "Static Assets", None, fontAwesome("file"), None)

  let content = {
    let deploys = if m.staticDeploys != list{} {
      m.staticDeploys->List.map(~f=viewDeploy)
    } else {
      list{viewEmptyCategoryContents("Static deploys")}
    }

    Html.div(
      list{tw3("category-content", Styles.content, Styles.contentVisibility)},
      list{
        Html.span(list{Attrs.class(Styles.contentCategoryName)}, list{Html.text("Static Assets")}),
        ...deploys,
      },
    )
  }

  Html.div(list{tw(Styles.sidebarCategory)}, list{button, content})
}

// ---------------
// Secrets
// ---------------

let viewSecret = (s: SecretTypes.t): Html.html<msg> => {
  let copyBtn = Html.div(
    list{
      tw(%twc("text-base hover:text-sidebar-hover")),
      EventListeners.eventNeither(
        "click",
        ~key="copy-secret-" ++ s.secretName,
        m => Msg.ClipboardCopyLivevalue(s.secretName, m.mePos),
      ),
      Attrs.title("Click to copy secret name"),
    },
    list{fontAwesome("copy")},
  )

  let secretValue = Util.obscureString(s.secretValue)
  let secretValue = {
    // If str length > 16 chars, we just want to keep the last 16 chars
    let len = String.length(secretValue)
    let count = len - 16
    if count > 0 {
      String.dropLeft(~count, secretValue)
    } else {
      secretValue
    }
  }

  let style = %twc("text-xs no-underline box-border px-1.5 py-0 w-full overflow-hidden")

  Html.div(
    list{
      tw("flex relative justify-between items-center flex-row flex-nowrap w-72 ml-5 mr-1 mt-2.5"),
    },
    list{
      Html.div(
        list{
          tw(
            %twc(
              "group border border-solid border-sidebar-secondary pt-1 rounded-sm text-sidebar-primary w-64 hover:cursor-pointer hover:text-sidebar-hover hover:border-sidebar-hover"
            ),
          ),
        },
        list{
          Html.span(
            list{tw2(style, %twc("inline-block group-hover:hidden"))},
            list{Html.text(s.secretName)},
          ),
          Html.span(
            list{tw2(style, %twc("hidden group-hover:inline-block"))},
            list{Html.text(secretValue)},
          ),
        },
      ),
      copyBtn,
    },
  )
}

let viewSecretKeys = (m: model): Html.html<AppTypes.msg> => {
  let button = viewSidebarButton(
    m,
    "Secret Keys",
    Some(SecretMsg(OpenCreateModal)),
    fontAwesome("user-secret"),
    None,
  )

  let content = {
    let title = Html.span(list{tw(Styles.contentCategoryName)}, list{Html.text("Secret Keys")})
    let entries = if m.secrets != list{} {
      List.map(m.secrets, ~f=viewSecret)
    } else {
      list{viewEmptyCategoryContents("secret keys")}
    }
    Html.div(
      list{tw3("category-content", Styles.content, Styles.contentVisibility)},
      list{title, ...entries},
    )
  }

  Html.div(list{tw(Styles.sidebarCategory)}, list{button, content})
}

// --------------------
// Admin
// --------------------

let adminDebuggerView = (m: model): Html.html<msg> => {
  let rowStyle = %twc("flex h-4 items-center ml-4 m-1.5")
  let stateRowStyle = rowStyle ++ %twc(" justify-start mx-0")

  let stateInfoTohtml = (key: string, value: Html.html<msg>): Html.html<msg> =>
    Html.div(
      list{tw(stateRowStyle)},
      list{
        Html.p(list{}, list{Html.text(key)}),
        Html.p(list{tw(%twc("w-3.5"))}, list{Html.text(":")}),
        Html.p(list{tw(%twc("max-w-[210px] whitespace-nowrap"))}, list{value}),
      },
    )

  let pageToString = pg =>
    switch pg {
    | AppTypes.Page.Architecture => "Architecture"
    | FocusedPackageManagerFn(tlid) =>
      Printf.sprintf("Package Manager Fn (TLID %s)", TLID.toString(tlid))
    | FocusedFn(tlid, _) => Printf.sprintf("Fn (TLID %s)", TLID.toString(tlid))
    | FocusedHandler(tlid, _, _) => Printf.sprintf("Handler (TLID %s)", TLID.toString(tlid))
    | FocusedDB(tlid, _) => Printf.sprintf("DB (TLID %s)", TLID.toString(tlid))
    | FocusedType(tlid) => Printf.sprintf("Type (TLID %s)", TLID.toString(tlid))
    | SettingsModal(tab) => Printf.sprintf("SettingsModal (tab %s)", Settings.Tab.toText(tab))
    }

  let environment = {
    let color = switch m.environment {
    | "production" => %twc("text-black3")
    | "dev" => %twc("text-blue")
    | _ => %twc("text-magenta")
    }

    Html.div(
      list{tw2(%twc("bg-white1 text-[0.4em] rounded-sm p-0.5 -m-2.5"), color)},
      list{Html.text(m.environment)},
    )
  }

  let stateInfo = Html.div(
    list{},
    list{
      stateInfoTohtml("env", Html.text(m.environment)),
      stateInfoTohtml("page", Html.text(pageToString(m.currentPage))),
      stateInfoTohtml("cursorState", Html.text(AppTypes.CursorState.show(m.cursorState))),
    },
  )

  let input = (
    checked: bool,
    fn: AppTypes.EditorSettings.t => AppTypes.EditorSettings.t,
    label: string,
    style: string,
  ) => {
    let event = EventListeners.eventNoPropagation(
      ~key=`tt-${label}-${checked ? "checked" : "unchecked"}`,
      "mouseup",
      _ => Msg.ToggleEditorSetting(es => fn(es)),
    )

    Html.div(
      list{event, tw(rowStyle ++ " " ++ style)},
      list{
        Html.input(
          list{Attrs.type'("checkbox"), Attrs.checked(checked), tw(%twc("cursor-pointer"))},
          list{},
        ),
        Html.label(list{tw(%twc("ml-2"))}, list{Html.text(label)}),
      },
    )
  }

  let toggleTimer = input(
    m.editorSettings.runTimers,
    es => {...es, runTimers: !es.runTimers},
    "Run Timers",
    "mt-4",
  )

  let toggleFluidDebugger = input(
    m.editorSettings.showFluidDebugger,
    es => {...es, showFluidDebugger: !es.showFluidDebugger},
    "Show Fluid Debugger",
    "",
  )

  let toggleHandlerASTs = input(
    m.editorSettings.showHandlerASTs,
    es => {...es, showHandlerASTs: !es.showHandlerASTs},
    "Show Handler ASTs",
    "mb-4",
  )

  let debugger = Html.a(
    list{
      Attrs.href(ViewScaffold.debuggerLinkLoc(m)),
      tw(stateRowStyle ++ %twc(" text-grey8 hover:text-white3")),
    },
    list{
      Html.text(
        if m.teaDebuggerEnabled {
          "Disable Debugger"
        } else {
          "Enable Debugger"
        },
      ),
    },
  )

  let saveTestButton = Html.a(
    list{
      EventListeners.eventNoPropagation(~key="stb", "mouseup", _ => Msg.SaveTestButton),
      tw2(
        stateRowStyle,
        %twc(
          "border border-solid rounded-sm p-1 mb-5 h-2.5 w-fit text-xxs text-grey8 cursor-pointer hover:text-black2 hover:bg-grey8"
        ),
      ),
    },
    list{Html.text("SAVE STATE FOR INTEGRATION TEST")},
  )

  let hoverView = Html.div(
    list{tw3("category-content", Styles.content, Styles.contentVisibility)},
    Belt.List.concatMany([
      list{stateInfo, toggleTimer, toggleFluidDebugger, toggleHandlerASTs, debugger},
      list{saveTestButton},
    ]),
  )

  Html.div(
    list{tw2(Styles.sidebarCategory, %twc("p-0"))},
    list{
      Html.div(
        list{tw(%twc("outline-none flex justify-start items-center w-full flex-col -ml-1"))},
        list{categoryButton("Admin", fontAwesome("cog")), environment},
      ),
      hoverView,
    },
  )
}

// --------------------
// Standard view apparatus
// --------------------

let viewSidebar_ = (m: model): Html.html<msg> => {
  let cats = Belt.List.concat(
    standardCategories(m, m.handlers, m.dbs, m.userFunctions, m.userTypes),
    list{f404Category(m), deletedCategory(m), packageManagerCategory(m.functions.packageFunctions)},
  )

  let showAdminDebugger = if m.settings.contributingSettings.general.showSidebarDebuggerPanel {
    adminDebuggerView(m)
  } else {
    Vdom.noNode
  }

  let categories = Belt.List.concat(
    cats->List.map(~f=viewToplevelCategory(m)),
    list{viewSecretKeys(m), viewDeployStats(m), showAdminDebugger},
  )

  Html.div(
    list{
      Attrs.id("sidebar-left"), // keep for z-index
      tw(
        %twc(
          "h-full top-0 left-0 p-0 fixed box-border transition-[width] duration-200 bg-sidebar-bg pt-8 w-14"
        ),
      ),
      // Block opening the omnibox here by preventing canvas pan start
      EventListeners.nothingMouseEvent("mousedown"),
      EventListeners.eventNoPropagation(~key="ept", "mouseover", _ => Msg.EnablePanning(false)),
      EventListeners.eventNoPropagation(~key="epf", "mouseout", _ => Msg.EnablePanning(true)),
    },
    categories,
  )
}

let rtCacheKey = (m: model) =>
  (
    m.handlers |> Map.mapValues(~f=(h: PT.Handler.t) => (h.pos, TL.sortkey(TLHandler(h)))),
    m.dbs |> Map.mapValues(~f=(db: PT.DB.t) => (db.pos, TL.sortkey(TLDB(db)))),
    m.userFunctions |> Map.mapValues(~f=(uf: PT.UserFunction.t) => uf.name),
    m.userTypes |> Map.mapValues(~f=(ut: PT.UserType.t) => ut.name),
    m.f404s,
    m.deletedHandlers |> Map.mapValues(~f=(h: PT.Handler.t) => TL.sortkey(TLHandler(h))),
    m.deletedDBs |> Map.mapValues(~f=(db: PT.DB.t) => (db.pos, TL.sortkey(TLDB(db)))),
    m.deletedUserFunctions |> Map.mapValues(~f=(uf: PT.UserFunction.t) => uf.name),
    m.deleteduserTypes |> Map.mapValues(~f=(ut: PT.UserType.t) => ut.name),
    m.staticDeploys,
    m.unlockedDBs,
    m.usedDBs,
    m.usedFns,
    m.usedTipes,
    CursorState.tlidOf(m.cursorState),
    m.environment,
    m.editorSettings,
    m.permission,
    m.currentPage,
    m.tooltipState.tooltipSource,
    m.secrets,
    m.functions.packageFunctions |> Map.mapValues(~f=(t: PT.Package.Fn.t) => t.name.owner),
    m.settings.contributingSettings.general.showSidebarDebuggerPanel,
  ) |> Option.some

let viewSidebar = m => ViewCache.cache1m(rtCacheKey, viewSidebar_, m)
