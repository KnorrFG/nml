import macros except name
import macroutils, constructor, sugar, sequtils, options
import core, engine
import fusion / matching

{.experimental: "caseStmtMacros".}

type 
  Slot = ref object
    signal: tuple[owner, name: NimNode]
    argname, body: NimNode
  DslElem = ref object
    elemType: NimNode
    parent: Option[DslElem]
    ident: Option[NimNode]
    config: seq[tuple[name, val: NimNode]]
    slots: seq[Slot]

DslElem.construct false:
  (parent, elemType): required
  ident: none(NimNode)
  config = @[]


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
                    code: seq[NimNode]): NimNode =
  let procName = ident("new" & name.strVal)
  let body = @[
    Command("new", Ident"result"),
    Call("initNElem", Ident"result")] & code
  result = StmtList(
    TypeSection(
      TypeDef(
        name,
        Empty(),
        RefTy(ObjectTy(Empty(), OfInherit(Ident"NElem"), Empty())))),
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
      let sigOwner = if slot.signal.owner.strVal == "parent":
                       if e.parent.isNone:
                         Ident"result"
                       else:
                         e.parent.unsafeGet.ident.get
                     else: slot.signal.owner
      echo slot.argname.treeRepr
      result.add Call("generateCallback", slot.argname,
                      slot.body.replaceSelf e.ident.get,
                      DotExpr(sigOwner, slot.signal.name))


macro generateCallback*(argname, body: untyped; signal: typed): untyped=
  assert argname.kind == nnkIdent and body.kind == nnkStmtList
  let typeinst = signal.getTypeInst
  if typeinst.matches(
      BracketExpr[Sym(strVal: "PropertyT"), @typename, _]):
    let procNode = newProc(params=[Empty(),
                                   IdentDefs(argname, typename, Empty())],
                           body=body)
    result = Call("add", DotExpr(signal, Ident"onchange"), procNode)
    echo repr result
  else:
    error("Only a property can be slot, but type is: " & typeinst.repr)


# -----------------------------------------------------------------------------
# Parsing
# -----------------------------------------------------------------------------
proc isNElemDecl(n: NimNode): bool =
  n.matches Call[Ident(), StmtList()] | Asgn[Ident(), Call[Ident(), StmtList()]]

proc isConfig(n: NimNode): bool = n.kind == nnkCommand
proc isSlot(n: NimNode): bool =
  n.matches Call[ObjConstr[Ident(strVal: "slot"), _], StmtList()]

proc isPropertyBinding(n: NimNode): bool =
  n.kind == nnkInfix and n.name.strVal == "<-"


proc parsePropertyBinding(n: NimNode, parent: Option[DslElem]): Slot =
  assert n.isPropertyBinding

  let pName = n.left
  if pName.kind != nnkIdent:
    error "Left of a <- must be an Identifier"

  case n.right:
    of Ident(strVal: "parent"):
      echo "just parent"
    of DotExpr([@owner, @name]):
      echo owner, " ", name
    else:
      echo "More complex:"
      echo n.right.treeRepr


proc parseSlot(n: NimNode): Slot =
  assert n.isSlot
  Call[
    ObjConstr[
      Ident(strVal: "slot"),
      ExprColonExpr[ Ident(strVal: @argname), DotExpr[@sigowner, @signame]]],
    @body] := n

  Slot(signal: (owner: sigowner, name: signame), argname: argname.Ident, 
       body: body)


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
        error "Invalid DSL element encountered: " & entry.repr


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


#proc mkuiImpl(args: NimNode): NimNode =
macro mkui*(args: varargs[untyped]): untyped =
  assert args.len >= 2
  #echo args.treeRepr
  let 
    name = args[0]
    code = args[^1]
    ctor = newTree(nnkArglist, args[1 ..< ^1])

  #echo code.treeRepr
  let elems = collect newSeq():
    for i, node in code:
      parseNElem(node, none(DslElem))
  #echo "Output"
  #let foo = typeDefinition(name, ctor, elems.concat.elemsToAst)
  #echo foo.treerepr
  let finalElems = fillInSymbols(elems.concat)
  result = typeDefinition(name, ctor, elems.concat.elemsToAst)

