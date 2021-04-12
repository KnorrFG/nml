import sdl2 except rect, Rect, Point
import sdl2 / ttf
import core, engine, geometry, sequtils, std / with
import sugar, strutils
import zero_functional


# -----------------------------------------------------------------------------
# Rectangle
# -----------------------------------------------------------------------------

defineEvent Color

type Rectangle* = ref object of NElem
  pColor: Color
  color*: Property(Color)

proc newRectangle*(): Rectangle =
  new result
  result.initNElem()

  let me = result

  proc setColor(c: Color) =
    me.pcolor = c
    me.requireRedraw

  result.color = newProperty[Color, EventColor](proc(): Color = me.pColor,
                                                setColor)
method draw*(r: Rectangle, parentRect: core.Rect, renderer: RendererPtr) =
  let 
    innerRect = r.rect.get() 
    innerPos = innerRect.pos
    innerSize = innerRect.size
    targetPos = if innerPos == defaultRect.pos: parentRect.pos else: innerPos
    targetSize = if innerSize == defaultRect.size: parentRect.size
                 else: innerSize
    targetRect: sdl2.Rect = targetPos & targetSize
  renderer.setDrawColor r.pColor
  renderer.fillRect unsafeAddr targetRect

  for c in r.children:
    c.draw targetRect, renderer


# -----------------------------------------------------------------------------
# MouseArea
# -----------------------------------------------------------------------------
type MouseArea* = ref object of NElem
  onLClick*, onLPress*, onLClickEnd*, onLRelease*: EventEmpty ##\
    ## There are subtle differences between these events. On LPress is simply a
    ## mouse down event on the area, and onLRelease is simply a left mouse up
    ## event on the area. onLClick only triggers when a lpress followed by an
    ## lrelease occurs with nothing inbetween except for mouse motion within
    ## the area, this will also triffer an onLClickEnd. Leaving the area or
    ## pressing another button after an lclick will also trigger an lClickEnd,
    ## but not onLClick. So long story short: button styling while it is
    ## pressed as reaction to onLPress, button back to normal as reaction to
    ## onLClickEnd and buisness logic as reaction to onClick. onLRelease in
    ## onlry there for completeness
  lpressActive: bool

proc newMouseArea*(): MouseArea =
  new result
  result.initNElem()
  result.onLClick = EventEmpty()
  result.onLClickEnd = EventEmpty()
  result.onLPress = EventEmpty()
  result.onLRelease = EventEmpty()
  result.lpressActive = false


method processEvent*(m: MouseArea, ev: Event): EventResult=
  if ev.kind == MouseButtonDown:
    if ev.button.button == BUTTON_LEFT and 
        m.rect.get().contains(v(ev.button.x, ev.button.y)):
      m.lpressActive = true
      m.onLPress.invoke
      erConsumed
    else:
      m.lpressActive = false
      m.onLClickEnd.invoke
      erIgnored
  elif ev.kind == MouseButtonUp and ev.button.button == BUTTON_LEFT and
      m.rect.get().contains(v(ev.button.x, ev.button.y)):
    m.onLRelease.invoke
    if m.lPressActive:
      m.lpressActive = false
      m.onLClick.invoke
      m.onLClickEnd.invoke
    erConsumed
  elif ev.kind == MouseMotion and m.lpressActive:
    let ev = ev.motion
    if not m.rect.get().contains(v(ev.x, ev.y)):
      m.lpressActive = false
      m.onLClickEnd.invoke
      erConsumed
    else:
      erIgnored
  else:
    erIgnored


# -----------------------------------------------------------------------------
# Image
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Flickable
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Text
# -----------------------------------------------------------------------------

# Text is rendered to surfaces (RAM) by the ttf library using fonts, and then
# needs to be coppied to the GPU which means I have a surface, which will then
# be displayed during draw.  There are 3 levels of rendering, im going to use
# the one that looks best, but is slowest, as text does not change regularily.
# Rendering text to surfaces requires an initiated ttf library, and creating a
# texture requires an existing renderer, which in turn means, an existing
# window. I can only be sure that one exists in the draw method. Therefore, the
# way to go will be a getTexture() proc, which will actually cache the texture
# and only recompute it if need be. Ttf does require a ttf font file, which in
# turn means a user of the library will always have to provide one.
# 
# Changeable attribs of text: the actual text, its color, the font file, the
# pointsize, the style (italic, bold, ...), the hinting  (light, monospace,
# ...), and whether the glyphs have an outline (and maybe the color of the
# outline)
#
# Additionally to consider: generated text is an image. The image will be
# larger, the larger the fontsize is. If the space that was intended for the
# text is smaller than the generated image it will have to clip, be scaled,
# ignore the bounds, or ideally get scroll bars. It might also be desirable to
# break the text so that it fits, which puts me into the world of type setting,
# and if I do this, text alignment becomes a thing, and then it gets really
# fucking complex, but also interesting
#
# For text input the glyphs should be cached one by one as textures, and then
# blitted manually for performance reasons. If I want to get really nice
# looking text, I can probably get the kerning values from the font using
# freetype.

type 
  Font = ref FontObj
  FontObj = object
    data: FontPtr

proc `=destroy`(x: var FontObj) =
  close x.data


proc newFont(f: string, size: cint): Font =
  let rawPtr = openFont(f, size).onFail:
    raise newException(NmlError, "Couldn't load font:\p" & $getError())
  result = Font(data: rawPtr)



type 
  Texture = ref TextureObj
  TextureObj = object
    data: TexturePtr

proc `=destroy`(x: var TextureObj) =
  destroy x.data


proc newTexture(renderer: RendererPtr; format: uint32; access, w, h: cint):
    Texture = Texture(data: createTexture(renderer, format, access, w, h))


proc fromSurface(renderer: RendererPtr, surface: SurfacePtr): Texture =
  Texture(data: createTextureFromSurface(renderer, surface))


template withTarget(renderer: RendererPtr, target: Texture, code: untyped):
    untyped =
  renderer.setRenderTarget target.data
  code
  renderer.setRenderTarget nil


proc copy[T1, T2](renderer: RendererPtr, texture: Texture, srcRect: NVec[4, T1],
    targetRect: NVec[4, T2]) =
  let 
    srcrect: sdl2.Rect = srcRect
    targetRect: sdl2.Rect = targetRect
  renderer.copy texture.data, srcrect.unsafeAddr, targetRect.unsafeAddr


type Alignment* = enum
    aLeft, aCenter, aRight, aTop, aBottom

proc getX(a: Alignment, srcW, destW: cint): cint =
  case a:
    of aLeft: 0
    of aCenter: cint((destW - srcW) / 2)
    of aRight: cint(destW - srcW)
    else:
      raiseNmlError "Invalid alignment for x value computation: " & a.repr

proc getY(a: Alignment, srcH, destH: cint): cint =
  case a:
    of aTop: 0
    of aCenter: cint((destH - srcH) / 2)
    of aBottom: cint(destH - srcH)
    else:
      raiseNmlError "Invalid alignment for y value computation: " & a.repr


defineEvent Alignment

type Text* = ref object of NElem
  pText, pFontFile: string
  pPointSize: cint
  pHAlign, pVAlign: Alignment
  pColor: Color
  textureW, textureH: cint
  font: Font
  rerenderText: bool
  textTexture: Texture
  text*: Property(string)
  vAlign*, hAlign*: Property(Alignment)
  fontFile*: Property(string)
  pointSize*: Property(cint)
  color*: Property(Color)

proc newText*(): Text =
  new result
  result.initNElem()
  with result:
    pColor = cBlack
    pPointSize = 12
    pVAlign = aTop
    pHAlign = aLeft
    rerenderText = true

  let me = result

  proc requireRedraw(t: Text) =
    t.rerenderText = true
    engine.requireRedraw t

  proc setFontFile(f: string) =
    me.pFontFile = f
    me.font = newFont(f, me.pPointSize)
    me.requireRedraw

  proc setPointSize(s: cint) =
    me.pPointSize = s
    me.font = newFont(me.pFontFile, s)
    me.requireRedraw
   
  proc setText(t: string) =
    me.pText = t
    me.requireRedraw

  proc setHAlign(a: Alignment) =
    me.pHAlign = a
    me.requireRedraw

  proc setVAlign(a: Alignment) =
    me.pVAlign = a
    me.requireRedraw

  proc setColor(c: Color) =
    me.pColor = c
    me.requireRedraw

  result.text = newproperty[string, Eventstring](
    proc(): string = me.ptext, setText)
  result.vAlign = newproperty[Alignment, EventAlignment](
    proc(): Alignment = me.pVAlign, setVAlign)
  result.hAlign = newproperty[Alignment, EventAlignment](
    proc(): Alignment = me.pHAlign, setHAlign)
  result.fontFile = newProperty[string, Eventstring](
    proc(): string = me.pFontFile, setFontFile)
  result.pointSize = newProperty[cint, Eventcint](
    proc(): cint = me.pPointSize, setPointSize)
  result.color = newProperty[Color, EventColor](
    proc(): Color = me.pColor, setColor)


method draw(t: Text, parentRect: Rect, renderer: RendererPtr) =
  ## Renders the text, which is stored on a texture with transparent surface,
  ## if something changes that Texture needs to be recreated. Sdl ttf does not
  ## support multiline text, so the text needs to be split, into lines, the
  ## lines are rendered as surfaces, which need to be made into textures, and
  ## will then be rendererd onto the internal texture
  if t.rerenderText:
    t.rerenderText = false
    let 
      lines = t.pText.splitlines.mapIt(
        renderUtf8Blended(t.font.data, it.cstring, t.pColor))
      textures = lines.mapIt(renderer.fromSurface(it))
      widths = lines.mapIt(it.w)
      heights = lines.mapIt(it.h)
    t.textureW = widths.max
    t.textureH = heights --> sum()

    for line in lines:
      line.freeSurface

    t.textTexture = renderer.newTexture(SDL_PIXELFORMAT_RGBA8888,
      SDL_TEXTUREACCESS_TARGET, t.textureW, t.textureH)
    t.textTexture.data.setTextureBlendMode BlendMode_Blend
    renderer.withTarget(t.textTexture):
      var bgColor = t.pColor
      bgColor.a = 0
      renderer.setDrawColor bgColor
      renderer.clear
      var y: cint = 0
      for (line, w, h) in zip(textures, widths, heights) --> to(seq):
        renderer.copy line, v(0, 0, w, h),
          v(t.pHAlign.getX(w, t.textureW), y, w, h)
        y += h

  # One gotcha here is that the texture that holds the text does probably not
  # have the same dimension as the Text-NElem. And to prevent auto-scaling
  # (because that would mess up the point size) we need to compute which part
  # of the internal texture will be blit, and where it will be blit, depending
  # on the alignments
  let tr = t.rect.get()  # targetRect
  renderer.copy t.textTexture, v(0, 0, t.textureW, t.textureH),
    (t.pos.get() +
    v(t.pHAlign.getX(t.textureW, tr.w), t.pVAlign.getY(t.textureH, tr.h))) &
    v(t.textureW, t.textureH)

