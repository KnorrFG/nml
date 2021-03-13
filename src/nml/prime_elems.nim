import sdl2
import core, engine

# -----------------------------------------------------------------------------
# NElem Impls
# -----------------------------------------------------------------------------

type Rectangle* = ref object of NElem
  color*: Color

addNew Rectangle

method draw*(r: Rectangle, targetArea: Rect, renderer: RendererPtr) =
  renderer.setDrawColor r.color
  renderer.fillRect unsafeAddr targetArea
