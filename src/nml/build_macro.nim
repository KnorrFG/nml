import macros except name
import macroutils, sugar, sequtils, options, strutils, strformat,
  tables, sets
import core, engine
import fusion / matching

{.experimental: "caseStmtMacros".}

using n: NimNode

type 
  Slot = ref object
    signal, body: NimNode
    argnames: seq[NimNode]
  DslElem = ref object
    elemType: NimNode
    parent: Option[DslElem]
    ident: Option[NimNode]
    config: seq[tuple[name, val: NimNode]]
    slots: seq[Slot]
  ForwardingDecl = ref object
    name: NimNode
    target: NimNode


proc newDslElem(parent: Option[DslElem], elemType: NimNode,
                ident = none(NimNode),
                config: seq[tuple[name, val: NimNode]] = @[]): DslElem =
  DslElem(elemType: elemType, parent: parent, ident: ident, config: config)


# -----------------------------------------------------------------------------
# My Macro Utils
# -----------------------------------------------------------------------------

proc leftMostIdent(n): NimNode =
  ## in a chain of DotExpr, get the leftmost identifier
  if n.kind == nnkIdent:
    return n
  elif n.kind == nnkDotExpr:
    return n[0].leftMostIdent
  else:
    error("Invalid node encoutered: " & n.repr)


proc replaceLeftMostIdentWith(n: NimNode, replacement: NimNode): NimNode =
  if n.kind == nnkDotExpr:
    return DotExpr(n[0].replaceLeftMostIdentWith(replacement), n[1])
  elif n.kind == nnkIdent:
    return replacement
  else:
    error("Invalid node encoutered: " & n.repr)


proc derefIfNeeded(n): NimNode=
  ## If a type is defined like this: type Foo = ref FooObj
  ## this ref is resolved and FooObjs impl is returned, otherwise n is returned
  case n:
    of TypeDef[_, Empty(), RefTy[@actualType is Sym()]]:
      # this is the case where a ref type is only defined as ref to an already
      # defined non ref type
      return actualType.getImpl
    else:
      return n


proc getParentType(n): Option[NimNode] =
  case n.derefIfNeeded:
    of TypeDef[_, _, RefTy[ObjectTy[_, OfInherit[@parentSym] | Empty(), _]]]:
      return parentSym
    else:
      error(
        "unsupported node Type (currently only ref types are supported):\p" &
        n.treeRepr)


proc getFields(n): seq[NimNode] =
  ## returns a list of IdentDefs that were defined for the type that is
  ## represented by n. n is supposed to be a TypeDef
  case n.derefIfNeeded:
    of TypeDef[_, _, RefTy[ObjectTy[_, _, RecList[all @fields] | Empty()]]|
                           ObjectTy[_, _, RecList[all @fields] | Empty()]]:
      return fields
    else:
      error("unsupported node Type :\p" & n.treeRepr)


proc getFieldsRecursive(n): seq[NimNode] =
  ## same as getFields, but also returns all fields of all parent types
  let 
    parentType = n.getParentType
    parentFields = if parentType.isSome:
                     parentType.unsafeGet.getImpl.getFields
                   else:
                     @[]

  n.getFields & parentFields


proc dotPrepend(n, prependee: NimNode): NimNode =
  case n:
    of Ident():
      return DotExpr(prependee, n)
    of DotExpr[@l, @r]:
      return DotExpr(l.dotPrepend(prependee), r)
    else:
      error("Invalid node type:\p" & n.treeRepr)
# -----------------------------------------------------------------------------
# Code Generation
# -----------------------------------------------------------------------------

proc isParamDef(n: NimNode): bool =
  n.kind in {nnkExprEqExpr, nnkExprColonExpr} 


proc toIdentDefs(n: NimNode): seq[NimNode] =
  #echo n.treeRepr
  assert n.kind == nnkArglist
  for pdef in n:
    if not pdef.isParamDef:
      error pdef.repr & " is no parameter definition"
    result.add if pdef.kind == nnkExprEqExpr:
      IdentDefs(pdef[0], Empty(), pdef[1])
    else:
      IdentDefs(pdef[0], pdef[1], Empty())
  #for c in result:
    #echo c.treeRepr


proc typeDefinition(name: NimNode, ctorSig: NimNode,
                    code: seq[NimNode], members: seq[NimNode]):
    NimNode =
  let procName = ident("new" & name.strVal)
  let body = @[
    Command("new", Ident"result"),
    Call("initNElem", Ident"result")] & code

  # The members are the definition for the forwarded fields, they go somewhere
  # here:
  result = StmtList(
    TypeSection(
      TypeDef(
        name,
        Empty(),
        RefTy(
          ObjectTy(
            Empty(),
            OfInherit(Ident"NElem"),
            RecList(members))))),
    ProcDef(
      procName,
      Empty(),
      FormalParams(name, ctorSig.toIdentDefs),
      Empty(),
      StmtList(body)))


proc toAst(e: DslElem): seq[NimNode] =
  ## creates the AST nodes for setting the elements properties, and adding them
  ## to the parent object. This function expects that the identifier is not
  ## None. Also, every object without parent is added to the root object
  ## Slots are not created here, since they require the existence of all
  ## objects
  for confPair in e.config:
    result.add Call("set", DotExpr(e.ident.get, confPair.name), confPair.val)

  let parent = if e.parent.isSome:
                 e.parent.unsafeGet.ident.get
               else:
                 Ident"result"


  result.add(Call(DotExpr(parent, Ident"add"), e.ident.get))


proc replaceSelf(n: NimNode, self: NimNode): NimNode =
  ## exprects n to be the body of a slot. In that body all occurences of the
  ## identifier "self" must be replaces with the identifier of the owning
  ## element, which is provided in the self argument
  assert n.kind == nnkStmtList and self.kind == nnkIdent
  n.forNode(nnkIdent, (node) => (if node.strVal == "self": self else: node))


proc startsWithParent(n: NimNode): bool =
  ## returns true if the leftmost identifier in a dotexpression is "parent"
  n.leftMostIdent.strVal == "parent"


proc elemsToAst(elems: seq[DslElem]): seq[NimNode] =
  ## generates var statement + elem.toAst
  let varContents = collect newSeq():
    for elem in elems:
      assert elem.elemType.kind == nnkIdent
      IdentDefs(elem.ident.get, Empty(), Call("new" & elem.elemType.strVal))
  result.add(VarSection(varContents)) 
  for elem in elems:
    result.insert(elem.toAst, result.len)

  # the slots require all other elems to be defined already, so they have to be
  # created below
  for e in elems:
    for slot in e.slots:
      #echo "foo: " & slot.signal.repr
      #echo "foo: " & slot.signal.treerepr
      let signal = if slot.signal.startsWithParent:
                     if e.parent.isNone:
                       slot.signal.replaceLeftMostIdentWith(Ident"result")
                     else:
                       slot.signal.replaceLeftMostIdentWith(
                         e.parent.unsafeGet.ident.get)
                   else: slot.signal
      #echo "bar: " & signal.repr
      #echo "slot.argnames: " & slot.argnames.repr
      #I cannot pass the signal as typed because it will not be valid if its a
      #local signal, But I cannot pass it as untyped, because then i cant do a
      #type look up, i need a second macro, that will just complete a local
      #signal, if it is one, and pass the result to generate callback
      
      let completeSignalCall = Call("completeLocalSignal", signal, e.ident.get,
                                    e.elemType)
      result.add Call("generateCallback",
                      Prefix(bindSym"@", Bracket(slot.argnames)),
                      slot.body.replaceSelf e.ident.get, completeSignalCall)
      #echo "call: " & result[^1].repr


proc nameFromDef(n): string=
  case n:
    of Ident(strVal: @name) |
       Postfix[Ident(strVal: "*"), Ident(strVal: @name)]:
      return name.get
    else:
      error("Invalid node:\p" & n.treeRepr)


proc namesFromIdentDef(n): seq[string] =
  if n.kind == nnkIdentDefs:
    return n[0 ..< ^2].map(nameFromDef)
  else:
    error("Invalid node:\p" & n.treeRepr)


macro completeLocalSignal*(signal, potentialOwner: untyped, elemType: typed): 
    untyped=
  let fields = elemType.getImpl.getFieldsRecursive.map(namesFromIdentDef).
    concat.toHashSet
  if signal.leftMostIdent.strVal in fields:
    signal.dotPrepend(potentialOwner)
  else:
    signal


macro generateCallback*(argnames, body: untyped; signal: typed): untyped=
  assert argnames.matches(Prefix[_, Bracket()]) and
      body.kind == nnkStmtList
  #echo "argnames: " & argnames.repr
  let argnames = argnames[1]
  let typeinst = signal.getTypeInst
  case typeinst:
    of BracketExpr[Sym(strVal: "PropertyT"), @typename, _]:
      # its a property, get the onchange event
      if not argnames.len == 1:
        error(unindent"""for a property slot, there must be exactly one argname, 
                         but there are: """ &
                         argnames.toSeq.mapIt(it.repr).join(", "))
      let procnode = newproc(params=[Empty(),
                                     IdentDefs(argnames[0], typename, Empty())],
                             body=body)
      return Call("add", DotExpr(signal, ident"onchange"), procnode)
    of Sym():
      # its an even, get the signature from the typedef
      let 
        impl = typeinst.getimpl
        base = impl.typ[0].inherits
      if not base.matches(OfInherit[Sym(strVal: "EventBase")]):
        break
      let params = macroutils.body(impl[2][0])[0][1][2][0]
      if params.len != argnames.len + 1:
        error("provided number of argument does not fit event " &
            fmt"{argnames.len} given, and {params.len - 1} required")

      let 
        renamedArgs = collect newSeq():
          for (sigDef, name) in zip(params[1..^1], argnames.toSeq):
            IdentDefs(name, sigDef[1], Empty())
        newParams = @[Empty()] & renamedArgs
        procnode = newproc(params=newParams, body=body)
      return Call("add", signal, procnode)
    else:
      discard

  error(
    "Only a property or an Even can be connected to a slot, but type is: " &
    signal.getTypeInst.repr)


proc getMemberDefs(forwardings: seq[ForwardingDecl], elems: seq[DslElem]):
    seq[NimNode] =
  ## generates the fields for a ui-type that are defined in a forward section
  let elemDict = elems.mapIt((it.ident.get.strVal, it)).toTable
  for fwd in forwardings:
    let target = fwd.target.leftMostIdent.strVal
    if target in elemDict:
      let 
        targetType = elemDict[target].elemType
        expr = fwd.target.replaceLeftMostIdentWith(targetType)
      result.add(IdentDefs(
        Postfix("*",  fwd.name),
        Call("typeof", expr),
        Empty()))
    else:
      error(target & " is undefined")


proc makeAsgnStmts(forwardings: seq[ForwardingDecl]): seq[NimNode] =
  ## asigns the local variables of the children to the type fields for element
  ## forwarding
  for fwd in forwardings:
    result.add Asgn(DotExpr(Ident("result"), fwd.name), fwd.target)


# -----------------------------------------------------------------------------
# Parsing
# -----------------------------------------------------------------------------
proc isNElemDecl(n: NimNode): bool =
  if n.matches Call[Ident(strVal: @typename), StmtList()] |
                    Asgn[Ident(), Call[Ident(), StmtList()]]:
    if typename.isSome() and typename.get[0].isLowerAscii():
      return false
    else:
      return true
  return false

proc isConfig(n: NimNode): bool = n.kind == nnkCommand and n[0].strVal != "slot"
proc isSlot(n: NimNode): bool =
  n.matches:
    Command[Ident(strVal: "slot"), Call(), StmtList()] |
    Command[Ident(strVal: "slot"), Ident() | DotExpr(), StmtList()]

proc isPropertyBinding(n: NimNode): bool =
  n.kind == nnkInfix and macroutils.name(n).strVal == "<-"

proc isForwardSection(n): bool =
  n.matches Call[Ident(strVal: "forward"), StmtList()]

proc parseForwardSection(n): seq[ForwardingDecl] =
  assert n.isForwardSection
  collect newSeq():
    for entry in n[1]:
      assert entry.kind == nnkAsgn
      ForwardingDecl(name: entry.left, target:entry.right)


proc parsePropertyBinding(n: NimNode, parent: Option[DslElem]): Slot =
  assert n.isPropertyBinding

  let pName = n.left
  if pName.kind != nnkIdent:
    error "Left of a <- must be an Identifier"
  
  func getSignal(n: NimNode): NimNode =
    case n:
      of @owner is Ident():
        DotExpr(owner, pName)
      else:
        n

  case n.right:
    of Ident() | DotExpr():
      Slot(signal: n.right.getSignal, argnames: @[Ident"it"],
           body: StmtList(quote do: self.`pname`.set it))
    else:
      var source = Empty()
      n.right.forNode(nnkPrefix, proc(x: auto): NimNode=
        if x.name.strVal == "*":
          source = x.argument
          Ident"it"
        else:
          x)
      if source == Empty():
        error("Expression is missing a * to mark the source: \p" & n.right.repr)
        Slot()
      else:
        Slot(signal: source.getSignal, argnames: @[Ident"it"],
             body: StmtList(superquote do: self.`pname`.set `n.right`))
     

proc parseSlot(n: NimNode): Slot =
  assert n.isSlot

  Command[Ident(strVal: "slot"),
    Call[@signal, all @argnames], @body is StmtList()] |
  Command[Ident(strVal: "slot"),
    @signal is (Ident() | DotExpr()), @body is StmtList()] := n

  Slot(signal: signal, argnames: argnames, body: body)


proc parseNElem(n: NimNode, parent: Option[DslElem]): seq[DslElem] =
  ## parses one Nelem. Creates the DslElem node and reads the config.
  ## recursive call for child elems
  assert n.isNElemDecl

  Asgn[@ident, Call[@typename, StmtList[all @body]]] |
    Call[@typename, StmtList[all @body]] := n
  result.add(newDslElem(parent, typename, ident))

  for entry in body:
    #echo entry.repr
    if entry.isNElemDecl:
      result.insert(entry.parseNElem some(result[0]), result.len)
    elif entry.isConfig:
      assert entry.len == 2
      result[0].config.add((name: entry[0], val: entry[1]))
    elif entry.isSlot():
      result[0].slots.add(entry.parseSlot)
    elif entry.isPropertyBinding:
      result[0].slots.add(entry.parsePropertyBinding parent)
    else:
      error "Invalid DSL element encountered: \pentry:\p" & entry.repr &
        "\pbody:\p" & body.mapIt(it.repr).join("\p")


# -----------------------------------------------------------------------------
# Macro + Tests
# -----------------------------------------------------------------------------
proc fillInSymbols(elems: seq[DslElem]): seq[DslElem] =
  ## some elems dont have names, those names are generated here
  var i = 0
  let base = genSym().strVal
  collect newSeq():
    for e in elems:
      if e.ident.isNone:
        inc i
        e.dup(ident = some(Ident(base & $i)))
      else:
        e


macro mkui*(args: varargs[untyped]): untyped =
  assert args.len >= 2
  let 
    name = args[0]
    code = args[^1]
    ctor = newTree(nnkArglist, args[1 ..< ^1])

  var 
    elems: seq[DslElem]
    forwardings: seq[ForwardingDecl]

  for node in code:
    if node.isForwardSection:
      forwardings.add(node.parseForwardSection)
    elif node.isNElemDecl:
      elems.add parseNElem(node, none(DslElem))
    else:
      error("Invalid Top level elem:\p" & node.treeRepr)
  
  let 
    finalElems = fillInSymbols(elems.concat)
    memberDefs = getMemberDefs(forwardings, finalElems)

  result = typeDefinition(name, ctor,
                          finalElems.elemsToAst & forwardings.makeAsgnStmts,
                          memberDefs)

