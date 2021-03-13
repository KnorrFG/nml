import macros except name
import macroutils, constructor, sugar, sequtils
import core, engine

type 
  DslElem = object
    ident, elemType, parent: NimNode
    config: seq[tuple[name, val: NimNode]]

DslElem.construct false:
  (parent, elemType): required
  ident: Ident(genSym().strVal)
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
  let body = @[Command("new", Ident"result")] & code
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
  result = collect newSeq():
    for confPair in e.config:
      Asgn(DotExpr(e.ident, confPair.name), confPair.val)
  result.add(Call(DotExpr(e.parent, Ident"add"), e.ident))


proc elemsToAst(elems: seq[DslElem]): seq[NimNode] =
  ## generates var statement + elem.toAst
  let varContents = collect newSeq():
    for elem in elems:
      assert elem.elemType.kind == nnkIdent
      IdentDefs(elem.ident, Empty(), Call("new" & elem.elemType.strVal))
  result.add(VarSection(varContents)) 
  for elem in elems:
    result.insert(elem.toAst, result.len)


# -----------------------------------------------------------------------------
# Parsing
# -----------------------------------------------------------------------------
proc isColonCall(n: NimNode): bool =
  n.kind == nnkCall and n[^1].kind == nnkStmtList


proc isNElemDecl(n: NimNode): bool =
  n.isColonCall or (n.kind == nnkAsgn and n[1].isColonCall)
  

proc isConfig(n: NimNode): bool = n.kind == nnkCommand


proc parseNElem(n: NimNode, parent: NimNode): seq[DslElem] =
  ## parses one Nelem. Creates the DslElem node and reads the config.
  ## recursive call for child elems
  assert n.isNElemDecl

  result = if n.isColonCall:
    @[initDslElem(parent, n.name)]
  else:
    @[initDslElem(parent, n.right.name, n.left)] 

  let body = if n.isColonCall: n[^1] else: n.right[^1]
  for entry in body:
    if entry.isNElemDecl:
      result.insert(entry.parseNElem result[0].ident, result.len)
    elif entry.isConfig:
      assert entry.len == 2
      result[0].config.add((name: entry[0], val: entry[1]))
    else:
        error "Invalid DSL element encountered: " & entry.repr


# -----------------------------------------------------------------------------
# Macro + Tests
# -----------------------------------------------------------------------------

#proc mkuiImpl(args: NimNode): NimNode =
macro mkui*(args: varargs[untyped]): untyped =
  assert args.len >= 2
  #echo args.treeRepr
  let 
    name = args[0]
    code = args[^1]
    ctor = newTree(nnkArglist, args[1 ..< ^1])
    resultIdent = Ident"result"

  #echo code.treeRepr
  let elems = collect newSeq():
    for i, node in code:
      parseNElem(node, resultIdent)
  #echo "Output"
  #let foo = typeDefinition(name, ctor, elems.concat.elemsToAst)
  #echo foo.treerepr
  result = typeDefinition(name, ctor, elems.concat.elemsToAst)

