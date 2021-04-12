import sdl2
import os, sugar, macros
import geometry


# -----------------------------------------------------------------------------
# utils
# -----------------------------------------------------------------------------

type 
  NmlError* = object of CatchableError
  EventResult* = enum
    erQuit, erConsumed, erIgnored


template raiseNmlError*(msg: string): untyped =
  raise newException(NmlError, msg)


template onFail*(res: SDL_Return, code: untyped)=
  if res == SdlError:
    code


template onFail*(res: cint, code: untyped)=
  if res != 0:
    code


template onFail*(res: bool, code: untyped)=
  if not res:
    code


template onFail*[T](res: ptr T, code: untyped): ptr T =
  let p = res
  if p == nil:
    code
  p


# -----------------------------------------------------------------------------
# Colors
# -----------------------------------------------------------------------------

const
  cBlack* = color(0, 0, 0, 255)
  cWhite* = color(255, 255, 255, 255)
  cRed* = color(255, 0, 0, 255)
  cGreen* = color(0, 255, 0, 255) 
  cBlue* = color(0, 0, 255, 255) 

# -----------------------------------------------------------------------------
# Rect compatibility
# -----------------------------------------------------------------------------
type 
  Rect* = AbstractRect[cint]
  Point* = AbstractPoint[cint]
  Size* = AbstractSize[cint]

proc point*(x, y: cint): Point = v(x, y)
proc size*(w, h: cint): Size = v(w, h)
proc rect*(x, y, w, h: cint): Rect = v(x, y, w, h)

converter geomToSdl*[T](g: NVec[2, T]): sdl2.Point = (x: g.x.cint, y: g.y.cint)
converter geomToSdl*[T](g: NVec[4, T]): sdl2.Rect =
  (x: g.x.cint, y: g.y.cint, w: g.w.cint, h: g.h.cint)

converter sdlToGeom*(r: sdl2.Rect): NVec[4, cint] = v(r.x, r.y, r.w, r.h)
converter sdlToGeom*(r: sdl2.Point): NVec[2, cint] = v(r.x, r.y)

converter anyToCint*[T: SomeNumber](x: T): cint = x.cint

# -----------------------------------------------------------------------------
# Event
# -----------------------------------------------------------------------------

type EventBase* = object of RootObj

macro event*(args: varargs[untyped]): untyped =
  let name = args[0]
  var
    procArgs = @[newEmptyNode()] #Holds the ident defs for formal params
    argIdents: seq[NimNode]      #Holds the ident names
  for i, arg in args[1..<args.len]:
    let varName = ident("var" & $i) #Generated name for passing to the listeners
    procArgs.add(newIdentDefs(varName, arg, newEmptyNode()))
    argIdents.add(varName)


  let
    params = newNimNode(nnkFormalParams).add(procArgs)         #formal params
    procTy = newNimNode(nnkProcTy).add(params).add(newEmptyNode()) #Generate proc type
    exportedName = postfix(name, "*") #We always export the event cause we're dumb

  result = newStmtList().add quote do:
    type `exportedName` = ref object of EventBase
      listeners: seq[`procTy`]
    proc add*(evt: var `name`, newProc: `procTy`) =
      let ind = evt.listeners.find(newProc)
      if ind < 0: evt.listeners.add(newProc)

    proc remove*(evt: var `name`, toRemove: `procTy`) =
      let ind = evt.listeners.find(toRemove)
      if ind >= 0: evt.listeners.delete(ind)

  #Sometimes in our lives we all have things we need to borrow
  #AST is sometimes easier than quoteDo
  procArgs.insert(newIdentDefs(ident("evt"), name, newEmptyNode()), 1)
  var procBody = newNimNode(nnkForStmt).add(ident("listen"), newDotExpr(ident(
      "evt"), ident("listeners")), newStmtList().add(newCall(ident("listen"))))
  procBody[2][0].add(argIdents)
  let invokeProc = newProc(postfix(ident("invoke"), "*"), procArgs, procBody)
  result.add(invokeProc)

# -----------------------------------------------------------------------------
# Property
# -----------------------------------------------------------------------------

type PropertyT*[ValT, EventT] = ref object
  ## A property *represents* a value, which can be updated, and inform about
  ## its change via callback. The lazy attribute determines whether a call to
  ## set will automatically produce this event or not. This is useful, because
  ## a change in position, will produce a change in x and y, which will then
  ## emit change events for x, y, pos, right and bottom, and this is done in
  ## the setter, not in the set proc
  onChange*: EventT
  get*: () -> ValT
  set: proc(x: ValT)
  lazy: bool

proc newProperty*[ValT, EventT](getter: () -> ValT,
                                 setter: proc(x: ValT),
                                 lazy = false):
    PropertyT[ValT, EventT] =
  PropertyT[ValT, EventT](onChange: EventT(), get: getter, set: setter,
                          lazy: lazy)


proc set*[ValT, EventT](p: PropertyT[ValT, EventT], value: ValT) =
  if value != p.get():
    p.set(value)
    if not p.lazy:
      p.onChange.invoke(value)


template Property*(typeName: untyped): untyped =
  PropertyT[typeName, `Event typeName`]


template defineEvent*(typeName: untyped): untyped =
  event `Event typeName`, typeName

event EventEmpty
defineEvent cint
defineEvent string
defineEvent Rect
defineEvent Point
defineEvent Size


# -----------------------------------------------------------------------------
# Alignment
# -----------------------------------------------------------------------------

type Alignment* = enum
    aLeft, aCenter, aRight, aTop, aBottom, aCustom

proc getX*(a: Alignment, srcW, destW: cint): cint =
  case a:
    of aLeft: 0
    of aCenter: cint((destW - srcW) / 2)
    of aRight: cint(destW - srcW)
    else:
      raiseNmlError "Invalid alignment for x value computation: " & a.repr

proc getY*(a: Alignment, srcH, destH: cint): cint =
  case a:
    of aTop: 0
    of aCenter: cint((destH - srcH) / 2)
    of aBottom: cint(destH - srcH)
    else:
      raiseNmlError "Invalid alignment for y value computation: " & a.repr


defineEvent Alignment
