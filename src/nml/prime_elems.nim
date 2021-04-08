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
  result.color = newProperty[Color, EventColor](proc(): Color = me.pColor,
                                                 proc(c: Color) = me.pcolor = c)
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
  onClicked*: EventEmpty
  lastMouseDownWasInsideMe: bool

proc newMouseArea*(): MouseArea =
  new result
  result.initNElem()
  result.onClicked = EventEmpty()
  result.lastMouseDownWasInsideMe = false

method processEvent*(m: MouseArea, ev: Event): EventResult=
  ## Triggers onClicked, but only if a left down followed by a left up within
  ## the area occured. A mouse down within and a mouse up outside of it
  ## wont trigger the event. Neither will a mouse down outside, and a mouse up
  ## within
  if ev.kind == MouseButtonDown:
    if ev.button.button == BUTTON_LEFT and 
        m.rect.get().contains(v(ev.button.x, ev.button.y)):
      m.lastMouseDownWasInsideMe = true
    else:
      m.lastMouseDownWasInsideMe = false
    erIgnored
  elif ev.kind == MouseButtonUp and ev.button.button == BUTTON_LEFT and
      m.rect.get().contains(v(ev.button.x, ev.button.y)) and 
      m.lastMouseDownWasInsideMe:
    m.onClicked.invoke()
    erConsumed
  else:
    erIgnored




