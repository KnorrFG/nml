import core
import sdl2

# -----------------------------------------------------------------------------
# Engine and Window
# -----------------------------------------------------------------------------

type 
  NElem* = ref NElemObj
  NElemObj = object of RootObj
    children*: seq[NElem]
    window*: Window
    rect*: Rect
  Window = ref WindowObj
  WindowObj = object
    win: WindowPtr
    renderer: RendererPtr
    rootElem: NElem
    needsRedraw: bool
  Engine* = ref EngineObj
  EngineObj = object
    windows: seq[Window]
    

proc `=destroy`(x: var EngineObj) =
  sdl2.quit()


proc `=destroy`(x: var WindowObj) =
  destroy x.renderer
  destroyWindow x.win


addNew NElem


method draw*(e: NElem, parentRect: Rect, renderer: RendererPtr) 
  {.base, locks: 0.} =
  for c in e.children:
    c.draw(parentRect, renderer)


method processEvent*(e: NElem, ev: Event): EventResult
  {.base, locks: 0.} =
  for c in e.children:
    let res = c.processEvent(ev)
    if res != erIgnored:
      return res

  erIgnored


proc add*(e: NElem, child: NElem) =
  child.window = e.window
  e.children.add(child)


proc newEngine*(): Engine =
  new result
  init(INIT_TIMER or INIT_AUDIO or INIT_VIDEO).onFail:
    raise newException(NmlError, "Couldnt init SDL")


proc createWindow*(e: Engine, w, h: int, root: NElem, title = "",
                flags: uint32 = SDL_WINDOW_RESIZABLE or 
                  SDL_WINDOW_INPUT_GRABBED or SDL_WINDOW_ALLOW_HIGHDPI,
                x = SDL_WINDOWPOS_UNDEFINED,
                y = SDL_WINDOWPOS_UNDEFINED)=
  let win = Window()
  win.win = createWindow(title, x, y, w.cint, h.cint, flags).onFail:
    raise newException(NmlError, "Couldnt create window")
  win.renderer = createRenderer(win.win, -1, 0)
  win.rootElem = root
  e.windows.add win


proc draw(w: Window) =
  w.renderer.clear
  let winSize = w.win.getSize
  w.rootElem.draw((x: 0.cint, y: 0.cint, w: winSize.x, h: winSize.y),
                  w.renderer)
  w.renderer.present


proc redrawIfNecessary(w: Window) =
  if w.needsRedraw:
    w.needsRedraw = false
    w.draw()


proc processWindowEvent(w: Window, ev: WindowEventPtr): EventResult =
  case ev.event:
    of WindowEvent_Shown, WindowEvent_Exposed, WindowEvent_Maximized,
        WindowEvent_Resized, WindowEvent_Restored, WindowEvent_SizeChanged:
      w.needsRedraw = true
      return erConsumed
    else:
      return erIgnored


proc processEvent(w: Window, ev: Event): EventResult =
  case ev.kind:
    of WindowEvent:
      if ev.window.windowId == w.win.getID():
        return w.processWindowEvent(ev.window)
      else:
        return erIgnored
    of QuitEvent:
      return erQuit
    else:
      return w.rootElem.processEvent(ev)


proc run*(e: Engine) =
  var event: Event
  block outer:
    while true:
      waitEvent(event).onFail:
        raise newException(NmlError, "waitEvent: " & $getError())
      for w in e.windows:
        case w.processEvent event:
          of erQuit: break outer
          of erConsumed: break
          of erIgnored: discard

      for w in e.windows:
        w.redrawIfNecessary()
