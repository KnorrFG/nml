import sdl2 except rect, Rect, Point
import sdl2 / ttf
import core, engine, geometry, sequtils, std / with, sdlwrapper
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
type DragMode* = enum
    dmNone, dmVertical, dmHorizontal, dmFree

defineEvent DragMode

proc diff(dm: DragMode, a, b: Point): Point =
  case dm:
    of dmFree: a - b
    of dmHorizontal: v((a - b).x, 0.cint)
    of dmVertical: v(0.cint, (a - b).y)
    of dmNone: v(0.cint, 0.cint)


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
  onDragStart*, onDragEnd*: EventEmpty
  lpressActive, dragActive: bool
  pDragMode: DragMode
  lastMousePos: Point
  dragMode*: Property(DragMode)

proc newMouseArea*(): MouseArea =
  new result
  result.initNElem()
  result.onLClick = EventEmpty()
  result.onLClickEnd = EventEmpty()
  result.onLPress = EventEmpty()
  result.onLRelease = EventEmpty()
  result.onDragStart = EventEmpty()
  result.onDragEnd = EventEmpty()
  result.lpressActive = false
  result.dragActive = false
  result.pDragMode = dmNone
  
  let me = result
  result.dragMode = newProperty[DragMode, EventDragMode](
    proc(): DragMode = me.pDragMode,
    proc(x: DragMode) = me.pDragMode = x)


proc checkLClickStart(m: MouseArea, ev: Event): bool =
  ev.kind == MouseButtonDown and ev.button.button == BUTTON_LEFT and 
    m.rect.get().contains(v(ev.button.x, ev.button.y))


proc checkLRelease(m: MouseArea, ev: Event, within = true): bool =
  ev.kind == MouseButtonUp and ev.button.button == BUTTON_LEFT and
      (not within or m.rect.get().contains(v(ev.button.x, ev.button.y)))


proc checkLClickCancel(m: MouseArea, ev: Event): bool =
  if ev.kind == MouseButtonDown: return true
  elif ev.kind == MouseMotion:
    let ev = ev.motion
    return not m.rect.get().contains(v(ev.x, ev.y))
  false


proc checkDragStart(m: MouseArea, ev: Event): bool =
  if ev.kind == MouseMotion:
    let pos = v(ev.motion.x, ev.motion.y) 
    return abs(pos - m.lastMousePos) > 10
  false

   
method processEvent*(m: MouseArea, ev: Event): EventResult=
  result = erIgnored
  let dragable = m.pDragMode != dmNone

  if m.checkLRelease(ev):
    m.onLRelease.invoke
    result = erConsumed

  # I know this could be organized differtently, but the way it's ornized now
  # will allow me to split this off into a state machine if need be
  if not m.lpressActive and not m.dragActive:
    if m.checkLClickStart(ev):
      m.lpressActive = true
      m.onLPress.invoke
      m.lastMousePos = v(ev.button.x, ev.button.y)
      result = erConsumed
  elif m.lpressActive and not dragable:
    if m.checkLRelease(ev):
      m.lpressactive = false
      m.onlclick.invoke
      m.onlclickend.invoke
    elif m.checkLClickCancel(ev):
      m.lpressactive = false
      m.onlclickend.invoke
      result = erconsumed
  elif m.lpressActive and dragable:
    if m.checkLRelease(ev):
      m.lpressactive = false
      m.onlclick.invoke
      m.onlclickend.invoke
      result = erconsumed
    elif m.checkDragStart(ev):
      m.lpressactive = false
      m.dragActive = true
      m.onlclickend.invoke
      m.onDragStart.invoke
      result = erconsumed
  elif m.dragActive:
    if m.checkLRelease(ev, within=false):
      m.dragActive = false
      m.onDragEnd.invoke
      result = erconsumed
    if ev.kind == MouseMotion:
      let 
        pos = v(ev.motion.x, ev.motion.y)
        diff = m.pDragMode.diff(pos, m.lastMousePos)
      m.lastMousePos = pos
      m.pos.set m.pos.get() + diff



# -----------------------------------------------------------------------------
# Image
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Flickable
# -----------------------------------------------------------------------------

type Flickable* = ref object of NElem
  inner: Texture
  innerW, innerH: cint
  innerRedrawRequired*: bool
  innerVAlign*, innerHAlign*: Alignment

proc inner*(f: Flickable): Texture = f.inner

proc recreateInnerTexture*(f: Flickable, renderer: RendererPtr, w, h: cint) =
  f.innerW = w
  f.innerH = h
  
  f.inner = renderer.newTexture(SDL_PIXELFORMAT_RGBA8888,
    SDL_TEXTUREACCESS_TARGET, w, h)
  f.inner.data.setTextureBlendMode BlendMode_Blend

proc innerW*(f: Flickable): cint = f.innerW
proc innerH*(f: Flickable): cint = f.innerH

method drawInner*(f: Flickable, renderer: RendererPtr) {.base, locks: 0.} =
  doAssert false, "Not Implemented"

method draw*(f: Flickable, parentRect: Rect, renderer: RendererPtr) =
  if f.innerRedrawRequired:
    f.innerRedrawRequired = false
    f.drawInner(renderer)
  let tr = f.rect.get()  # targetRect
  renderer.withClip tr:
    renderer.copy f.inner, v(0, 0, f.innerW, f.innerH),
      (tr.pos +
      v(f.innerHAlign.getX(f.innerW, tr.w),
        f.innerVAlign.getY(f.innerH, tr.h))) & v(f.innerW, f.innerH)



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

type Text* = ref object of Flickable
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
    # these decide how the lines are layed out within the inner texture
    pVAlign = aTop
    pHAlign = aLeft
    # these decide how the inner canvas is placed within the actual drawing
    # area
    innerVAlign = aTop
    innerHAlign = aLeft
    rerenderText = true
    innerRedrawRequired = true

  let me = result

  proc requireRedraw(t: Text) =
    t.innerRedrawRequired = true
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
    me.innerHAlign = a
    me.requireRedraw

  proc setVAlign(a: Alignment) =
    me.pVAlign = a
    me.innerVAlign = a
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


method drawInner(t: Text, renderer: RendererPtr) =
  ## Renders the text, which is stored on a texture with transparent surface,
  ## if something changes that Texture needs to be recreated. Sdl ttf does not
  ## support multiline text, so the text needs to be split, into lines, the
  ## lines are rendered as surfaces, which need to be made into textures, and
  ## will then be rendererd onto the internal texture
  let 
    lines = t.pText.splitlines.mapIt(
      renderUtf8Blended(t.font.data, it.cstring, t.pColor))
    textures = lines.mapIt(renderer.fromSurface(it))
    widths = lines.mapIt(it.w)
    heights = lines.mapIt(it.h)
    w = widths.max
    h = heights --> sum()

  for line in lines:
    line.freeSurface

  t.recreateInnerTexture(renderer, w, h)
  renderer.withTarget(t.inner):
    var bgColor = t.pColor
    bgColor.a = 0
    renderer.setDrawColor bgColor
    renderer.clear
    var y: cint = 0
    for (line, w, h) in zip(textures, widths, heights) --> to(seq):
      renderer.copy line, v(0, 0, w, h),
        v(t.pHAlign.getX(w, t.innerW), y, w, h)
      y += h
