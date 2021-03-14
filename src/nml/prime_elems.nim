import sdl2 except rect
import core, engine, geometry


# -----------------------------------------------------------------------------
# NElem Impls
# -----------------------------------------------------------------------------

type Rectangle* = ref object of NElem
  color*: Color

addNew Rectangle

method draw*(r: Rectangle, parentRect: core.Rect, renderer: RendererPtr) =
  let 
    innerRect = r.rect.get() 
    innerPos = innerRect.pos
    innerSize = innerRect.size
    targetPos = if innerPos == defaultRect.pos: parentRect.pos else: innerPos
    targetSize = if innerSize == defaultRect.size: parentRect.size
                 else: innerSize
    targetRect: sdl2.Rect = targetPos & targetSize
  renderer.setDrawColor r.color
  renderer.fillRect unsafeAddr targetRect

  for c in r.children:
    c.draw targetRect, renderer
