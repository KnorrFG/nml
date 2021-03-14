import sdl2, constructor
import os, sugar
import geometry

export color, Point


# -----------------------------------------------------------------------------
# utils
# -----------------------------------------------------------------------------

type 
  NmlError* = object of CatchableError
  EventResult* = enum
    erQuit, erConsumed, erIgnored


template onFail*(res: SDL_Return, code: untyped)=
  if res == SdlError:
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

converter geomToSdl*(g: NVec[2, cint]): sdl2.Point = (x: g.x, y: g.y)
converter geomToSdl*(g: NVec[4, cint]): sdl2.Rect =
  (x: g.x, y: g.y, w: g.w, h: g.h)

converter sdlToGeom*(r: sdl2.Rect): NVec[4, cint] = v(r.x, r.y, r.w, r.h)
converter sdlToGeom*(r: sdl2.Point): NVec[2, cint] = v(r.x, r.y)

# -----------------------------------------------------------------------------
# Property
# -----------------------------------------------------------------------------

type PropertyT*[ValT, EventT] = object
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

proc initProperty*[ValT, EventT](getter: () -> ValT,
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

defineEvent cint
defineEvent Rect
defineEvent Point
defineEvent Size
