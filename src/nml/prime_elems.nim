import sdl2 except rect
import core, engine, geometry
import sugar


# -----------------------------------------------------------------------------
# NElem Impls
# -----------------------------------------------------------------------------

defineEvent Color

type Rectangle* = ref object of NElem
  pColor: Color
  color*: Property(Color)

proc newRectangle*(): Rectangle =
  new result
  result.initNElem()

  let me = result
  result.color = initProperty[Color, EventColor](proc(): Color = me.pColor,
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
