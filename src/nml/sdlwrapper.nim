import sdl2 except rect, Rect, Point
import sdl2 / ttf

import core, geometry
# -----------------------------------------------------------------------------
# Font
# -----------------------------------------------------------------------------

type 
  Font* = ref FontObj
  FontObj = object
    data: FontPtr

proc `=destroy`*(x: var FontObj) =
  close x.data


proc newFont*(f: string, size: cint): Font =
  let rawPtr = openFont(f, size).onFail:
    raise newException(NmlError, "Couldn't load font:\p" & $getError())
  result = Font(data: rawPtr)


proc data*(f: Font): FontPtr = 
  if f.isNil:
    raiseNmlError "No Font Specified"
  f.data

# -----------------------------------------------------------------------------
# Texture
# -----------------------------------------------------------------------------

type 
  Texture* = ref TextureObj
  TextureObj = object
    data*: TexturePtr

proc `=destroy`*(x: var TextureObj) =
  destroy x.data


proc newTexture*(renderer: RendererPtr; format: uint32; access, w, h: cint):
    Texture = Texture(data: createTexture(renderer, format, access, w, h))


proc fromSurface*(renderer: RendererPtr, surface: SurfacePtr): Texture =
  Texture(data: createTextureFromSurface(renderer, surface))


proc copy*[T1, T2](renderer: RendererPtr, texture: Texture, srcRect: NVec[4, T1],
    targetRect: NVec[4, T2]) =
  let 
    srcrect: sdl2.Rect = srcRect
    targetRect: sdl2.Rect = targetRect
  renderer.copy texture.data, srcrect.unsafeAddr, targetRect.unsafeAddr


# -----------------------------------------------------------------------------
# Renderer
# -----------------------------------------------------------------------------

template withTarget*(renderer: RendererPtr, target: Texture, code: untyped):
    untyped =
  renderer.setRenderTarget target.data
  code
  renderer.setRenderTarget nil

template withClip*(renderer: RendererPtr, rect: Rect, code: typed): untyped =
  let r: sdl2.Rect = rect
  renderer.setClipRect(r.unsafeAddr).onFail:
    raiseNmlError "Couldnt set renderer clip: " & $getError()
  code
  renderer.setClipRect(nil).onFail:
    raiseNmlError "Couldnt reset renderer clip: " & $getError()

proc fillRect*(r: RendererPtr, target: Rect) =
  let t: sdl2.Rect = target
  r.fillRect t.unsafeaddr
