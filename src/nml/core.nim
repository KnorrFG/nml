import sdl2
import os

export color

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


template addNew*(name: untyped) =
  proc `new name`*(): name = new result

