import sdl2 except rect
import core, engine, geometry
import sugar


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
  TextAlignment = enum
    taLeft, taCenter, taRight
  Text = ref object of NElem
    text: string
    align: TextAlignment
    ttf: string

