import sdl2 except rect, Rect, Point
import sdl2 / ttf
import core, engine, geometry, sequtils, std / with, sdlwrapper, Options
import sugar, strutils
import zero_functional
import strformat


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
  let myRect = r.rect.get()
  renderer.setDrawColor r.pColor
  renderer.fillRect myRect

  for c in r.children:
    c.draw myRect, renderer


# -----------------------------------------------------------------------------
# MouseArea
# -----------------------------------------------------------------------------
type 
  DragMode* = enum
    dmNone, dmVertical, dmHorizontal, dmFree
  OptRect* = Option[Rect]


defineEvent DragMode
defineEvent OptRect

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
  dragRestrictionRect*: Property(OptRect)  ##\
    ## Setting this will make the object draggable within the defined rect, and
    ## ignore the dragMode
  pDragRestrictionRect: OptRect

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
  result.pDragRestrictionRect = none(Rect)
  
  let me = result
  result.dragMode = newProperty[DragMode, EventDragMode](
    proc(): DragMode = me.pDragMode,
    proc(x: DragMode) = me.pDragMode = x)

  result.dragRestrictionRect = newProperty[OptRect, EventOptRect](
    proc(): OptRect = me.pDragRestrictionRect,
    proc(x: OptRect) = me.pDragRestrictionRect = x)


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
  let dragable = m.pDragMode != dmNone or m.pDragRestrictionRect.isSome

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
      result = erConsumed
    if ev.kind == MouseMotion:
      result = erConsumed
      if m.pDragRestrictionRect.isSome:
        let rect = restrictTo(v(ev.motion.x, ev.motion.y) & m.size.get(),
                              m.pDragRestrictionRect.unsafeGet)
        m.pos.set rect.pos
      else:  # If a DragRestrictionRect is Set, the drag Mode is ignored
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
  innerX, innerY: cint ## \
    ## Holds the position of the inner texture in relation to the Flickable's
    ## Rect. This will always be less or equal than (0, 0). Only relevant when
    ## the Flickable has scrollbars and the texture is bigger than the
    ## Flickable
  innerRedrawRequired*: bool
  innerVAlign*, innerHAlign*: Alignment
  vBarMouseArea, hBarMouseArea: MouseArea
  scrollBarBackground*, scrollBarSlider*: Property(NElem)
  pScrollBarBackground, pScrollBarSlider: NElem
  pScrollBarThickness: cint
  scrollBarThickness*: Property(cint)
  viewRect: Rect
  vBarRect, hBarRect: Option[Rect]


proc getVSliderRect(f: Flickable): Rect =
  let viewRect = f.rect.get()
  if viewRect == v(0, 0, 0, 0) or f.innerH == 0:
    return viewRect

  let
    relativeOffset = -f.innerY / f.innerH
    sliderBGHeight = viewRect.h - f.pScrollBarThickness
    sliderY = sliderBGHeight * relativeOffset + viewRect.y
    sliderH: cint = viewRect.h.float / f.innerH.float * sliderBGHeight.float
  v(viewRect.right - f.pScrollBarThickness, sliderY, f.pScrollBarThickness,
    sliderH)


proc getHSliderRect(f: Flickable): Rect =
  let viewRect = f.rect.get()
  if viewRect == v(0, 0, 0, 0) or f.innerW == 0:
    return viewRect

  let
    relativeOffset = -f.innerX / f.innerW
    sliderBGWidth = viewRect.w - f.pScrollBarThickness
    sliderX = sliderBGWidth * relativeOffset + viewRect.x
    sliderW: cint = viewRect.w.float / f.innerW.float * sliderBGWidth.float
  v(sliderX, viewRect.bottom - f.pScrollBarThickness, sliderW,
    f.pScrollBarThickness)


template adjustInnerPos(f: Flickable, val: cint,
                        prefix, x_or_y, w_or_h: untyped) =
  let barRectOpt = f.`prefix BarRect`
  if barRectOpt.isSome:
    let
      barRect = barRectOpt.unsafeGet
      fRect = f.rect.get()
      relOffset = float(val - barRect.x_or_y) /
        float(barRect.w_or_h - f.`prefix BarMouseArea`.w_or_h.get())
      maxRange = f.`inner w_or_h` - fRect.w_or_h
    f.`inner x_or_y` = -maxRange.float * relOffset

proc updateDimensions(f: Flickable, myRect: Rect) =
  ## computes the Rects for the display of the inner texture, and both
  ## scrollbars. Gets called uppon resize
  let innerSize = v(f.innerW, f.innerH)

  proc vBarRect(): auto = some(v(myRect.right - f.pScrollBarThickness,
                                 myRect.top,
                                 f.pScrollBarThickness,
                                 myRect.h - f.pScrollBarThickness))

  proc hBarRect(): auto = some(v(myRect.left,
                                 myRect.bottom - f.pScrollBarThickness,
                                 myRect.w - f.pScrollBarThickness,
                                 f.pScrollBarThickness))

  proc displayRect(reduceW, reduceH: bool): Rect =
    myRect.pos & (myRect.size - v(if reduceW: f.pScrollBarThickness else: 0,
                                  if reduceH: f.pScrollBarThickness else: 0))
  
  template setVals(view, vert, horz): untyped =
    f.viewRect = view
    f.vBarRect = vert
    f.vBarMouseArea.dragRestrictionRect.set vert
    f.hBarRect = horz
    f.hBarMouseArea.dragRestrictionRect.set horz

  if innerSize.fitsIn(myRect.size):
    setVals(myRect, none(Rect), none(Rect))
  elif myRect.size.fitsIn(innerSize):
    # the inner rect is larger in both dimensions, both bars needed
    setVals(displayRect(true, true), vBarRect(), hBarRect())
  elif myRect.w < innerSize.w:
    # Needs a the horizontal scrollbar, but that costs vertical space, so I
    # need to check whether the vertival space - the bar is still large enoug
    if myRect.h - f.pScrollBarThickness >= innerSize.h:
      setVals(displayRect(false, true), none(Rect), hBarRect())
    else:
      setVals(displayRect(true, true), vBarRect(), hBarRect())
  elif myRect.h < innerSize.h:
    if myRect.w - f.pScrollBarThickness >= innerSize.w:
      setVals(displayRect(true, false), vBarRect(), none(Rect))
    else:
      setVals(displayRect(true, true), vBarRect(), hBarRect())


proc initFlickable*(f: Flickable) =
  f.initNElem()
  f.scrollBarBackground = newProperty[NElem, EventNElem](
    proc(): NElem = f.pScrollBarBackground,
    proc(n: NElem) = f.pScrollBarBackground = n)

  f.rect.onChange.add proc(r: Rect) =
    f.updateDimensions(r)
    f.hBarMouseArea.rect.set f.getHSliderRect()
    f.vBarMouseArea.rect.set f.getVSliderRect()

  f.vBarMouseArea = newMouseArea()
  f.hBarMouseArea = newMouseArea()

  proc setSlider(s: NElem) =
    f.pScrollBarSlider = s
    let 
      vertS = s
      horzS = s.deepCopy

    f.vBarMouseArea = newMouseArea()
    f.vBarMouseArea.parent = f
    f.vBarMouseArea.rect.onChange.add proc(r: Rect) =
      vertS.rect.set r
    f.vBarMouseArea.y.onChange.add proc(val: cint) =
      f.adjustInnerPos(val, v, y, h)
    f.vBarMouseArea.add vertS
    
    f.hBarMouseArea = newMouseArea()
    f.hBarMouseArea.parent = f
    f.hBarMouseArea.rect.onChange.add proc(r: Rect) =
      horzS.rect.set r
    f.hBarMouseArea.x.onChange.add proc(val: cint) =
      f.adjustInnerPos(val, h, x, w)
    f.hBarMouseArea.add horzS

  f.scrollBarSlider = newProperty[NElem, EventNElem](
    proc(): NElem = f.pScrollBarSlider,
    setSlider)

  f.scrollBarThickness = newProperty[cint, EventCint](
    proc(): cint = f.pScrollBarThickness,
    proc(i: cint) = f.pScrollBarThickness = i)
  f.pScrollBarThickness = 10

proc inner*(f: Flickable): Texture = f.inner

proc recreateInnerTexture*(f: Flickable, renderer: RendererPtr, w, h: cint) =
  f.innerW = w
  f.innerH = h
  
  f.inner = renderer.newTexture(SDL_PIXELFORMAT_RGBA8888,
    SDL_TEXTUREACCESS_TARGET, w, h)
  f.inner.data.setTextureBlendMode BlendMode_Blend

  f.updateDimensions(f.rect.get())
  f.hBarMouseArea.rect.set f.getHSliderRect()
  f.vBarMouseArea.rect.set f.getVSliderRect()

proc innerW*(f: Flickable): cint = f.innerW
proc innerH*(f: Flickable): cint = f.innerH

method drawInner*(f: Flickable, renderer: RendererPtr) {.base, locks: 0.} =
  doAssert false, "Not Implemented"


proc hasScrollBars(f: Flickable): bool =
  not f.pScrollBarBackground.isNil and not f.pScrollBarSlider.isNil


method draw*(f: Flickable, parentRect: Rect, renderer: RendererPtr) =
  if f.innerRedrawRequired:
    f.innerRedrawRequired = false
    f.drawInner(renderer)

  let tr = f.rect.get()  # targetRect
  if f.hasScrollBars:
    renderer.withClip f.viewRect:
      renderer.copy f.inner, v(0, 0, f.innerW, f.innerH),
        (tr.pos + v(f.innerX, f.innerY)) & v(f.innerW, f.innerH)
    if f.vBarRect.isSome:
      let r = f.vBarRect.unsafeget
      f.pScrollBarBackground.rect.set r
      f.pScrollBarBackground.draw(tr, renderer)
      f.vBarMouseArea.draw(tr, renderer)
    if f.hBarRect.isSome:
      let r = f.hBarRect.unsafeget
      f.pScrollBarBackground.rect.set r
      f.pScrollBarBackground.draw(tr, renderer)
      f.hBarMouseArea.draw(tr, renderer)
  else:
    renderer.withClip tr:
      renderer.copy f.inner, v(0, 0, f.innerW, f.innerH),
        (tr.pos +
        v(f.innerHAlign.getX(f.innerW, tr.w),
          f.innerVAlign.getY(f.innerH, tr.h))) & v(f.innerW, f.innerH)


template processSlider(f: Flickable, ev: Event, prefix: untyped): untyped =
  let areaOpt = f.`prefix BarRect`
  if areaOpt.isSome:
    let 
      slider = f.`prefix BarMouseArea`
      res = slider.processEvent ev

    if res != erIgnored:
      return res


method processEvent*(f: Flickable, ev: Event): EventResult =
  f.processSlider(ev, v)
  f.processSlider(ev, h)
  f.processEventDefaultImpl ev


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
  result.initFlickable()
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
