import core, geometry
import sdl2 except rect, Rect, Point
import sdl2 / ttf
import times, os

const frameDur = int((1 / 60) * 1000)

type 
  Point = core.Point
  Rect = core.Rect
  Size = core.Size
  NElem* = ref NElemObj
  NElemObj = object of RootObj
    parent*: NElem
    children*: seq[NElem]
    pWindow: Window
    pRect: Rect
    x*, y*, w*, h*, right*, bottom*, centerX*, centerY*: Property(cint)
    # left and top are procs that return x and y
    size*: Property(Size)
    center*, pos*: Property(Point)
    rect*: Property(Rect)
  Window = ref WindowObj
  WindowObj = object
    win: WindowPtr
    renderer: RendererPtr
    rootElem: NElem
    needsRedraw: bool
  Engine* = ref EngineObj
  EngineObj = object
    windows: seq[Window]
    

const defaultRect* = v(-1.cint, -1.cint, -1.cint, -1.cint)


proc `=destroy`(x: var EngineObj) =
  sdl2.quit()


proc `=destroy`(x: var WindowObj) =
  destroy x.renderer
  destroyWindow x.win


# -----------------------------------------------------------------------------
# NElem
# -----------------------------------------------------------------------------

defineEvent NElem

proc window*(e: NElem): Window =
  if e.parent.isNil: e.pWindow
  else: e.parent.window


proc requireRedraw*(me: NElem) =
  if not me.window.isNil and (not me.window.needsRedraw):
    me.window.needsRedraw = true
    

proc initNElem*(me: NElem) =
  me.pRect = defaultRect

  proc setX(x: cint) =
    me.pRect.x = x
    me.x.onChange.invoke(x)
    me.right.onChange.invoke(me.pRect.right)
    me.centerX.onChange.invoke(me.pRect.centerX)
    me.center.onChange.invoke(me.pRect.center)
    me.pos.onChange.invoke(me.pRect.pos)
    me.rect.onChange.invoke(me.pRect)
    me.requireRedraw

  proc setY(y: cint) =
    me.pRect.y = y
    me.y.onChange.invoke(y)
    me.bottom.onChange.invoke(me.pRect.bottom)
    me.centerY.onChange.invoke(me.pRect.centerY)
    me.center.onChange.invoke(me.pRect.center)
    me.pos.onChange.invoke(me.pRect.pos)
    me.rect.onChange.invoke(me.pRect)
    me.requireRedraw

  proc setW(w: cint) =
    me.pRect.w = w
    me.size.onChange.invoke(me.pRect.size)
    me.right.onChange.invoke(me.pRect.right)
    me.centerX.onChange.invoke(me.pRect.centerX)
    me.center.onChange.invoke(me.pRect.center)
    me.rect.onChange.invoke(me.pRect)
    me.requireRedraw

  proc setH(h: cint) =
    me.pRect.h = h
    me.size.onChange.invoke(me.pRect.size)
    me.bottom.onChange.invoke(me.pRect.bottom)
    me.centerY.onChange.invoke(me.pRect.centerY)
    me.center.onChange.invoke(me.pRect.center)
    me.rect.onChange.invoke(me.pRect)
    me.requireRedraw

  me.x = newProperty[cint, EventCint](proc(): cint = me.pRect.x, setX, true)
  me.y = newProperty[cint, EventCint](proc(): cint = me.pRect.y, setY, true)
  me.w = newProperty[cint, EventCint](proc(): cint = me.pRect.w, setW, true)
  me.h = newProperty[cint, EventCint](proc(): cint = me.pRect.h, setH, true)

  proc setRight(nr: cint) = me.x.set nr - me.pRect.w
  proc setBottom(nb: cint) = me.y.set nb - me.pRect.h
  proc setCenterX(cx: cint) = me.x.set cx - cint(me.pRect.w/ 2)
  proc setCenterY(cy: cint) = me.y.set cy - cint(me.pRect.h/ 2)

  me.right = newProperty[cint, EventCint](
    proc(): cint = me.pRect.right, setRight, true)
  me.bottom = newProperty[cint, EventCint](
    proc(): cint = me.pRect.bottom, setBottom, true)
  me.centerX = newProperty[cint, EventCint](
    proc(): cint = me.pRect.centerX, setCenterX, true)
  me.centerY = newProperty[cint, EventCint](
    proc(): cint = me.pRect.centerY, setCenterY, true)

  proc setSize(size: Size) =
    ## its done like this, instead of setting w and h via the setters, to avoid
    ## having center and size invoke 2 events
    me.pRect.w = size.w
    me.pRect.h = size.h
    me.w.onChange.invoke size.w
    me.h.onChange.invoke size.h
    me.size.onChange.invoke(me.pRect.size)
    me.right.onChange.invoke(me.pRect.right)
    me.bottom.onChange.invoke(me.pRect.bottom)
    me.centerX.onChange.invoke(me.pRect.centerX)
    me.centerY.onChange.invoke(me.pRect.centerY)
    me.center.onChange.invoke(me.pRect.center)
    me.rect.onChange.invoke(me.pRect)
    me.requireRedraw

  me.size = newProperty[Size, EventSize](
    proc(): Size = me.pRect.size, setSize, true)

  proc setCenter(c: Point) =
    me.pRect.x = c.x - cint(me.pRect.w / 2)
    me.pRect.y = c.y - cint(me.pRect.h / 2)
    me.x.onChange.invoke me.pRect.x
    me.y.onChange.invoke me.pRect.y
    me.right.onChange.invoke(me.pRect.right)
    me.bottom.onChange.invoke(me.pRect.bottom)
    me.centerX.onChange.invoke(me.pRect.centerX)
    me.centerY.onChange.invoke(me.pRect.centerY)
    me.center.onChange.invoke(me.pRect.center)
    me.pos.onChange.invoke(me.pRect.pos)
    me.rect.onChange.invoke(me.pRect)
    me.requireRedraw

  me.center = newProperty[Point, EventPoint](
    proc(): Point = me.pRect.center, setCenter, true)

  proc setPos(p: Point) =
    me.pRect.x = p.x
    me.pRect.y = p.y
    me.x.onChange.invoke p.x
    me.y.onChange.invoke p.y
    me.right.onChange.invoke(me.pRect.right)
    me.bottom.onChange.invoke(me.pRect.bottom)
    me.centerX.onChange.invoke(me.pRect.centerX)
    me.centerY.onChange.invoke(me.pRect.centerY)
    me.center.onChange.invoke(me.pRect.center)
    me.pos.onChange.invoke(me.pRect.pos)
    me.rect.onChange.invoke(me.pRect)
    me.requireRedraw

  me.pos = newProperty[Point, EventPoint](
    proc(): Point = me.pRect.pos, setPos, true)

  proc setRect(r: Rect) =
    me.pRect = r
    me.w.onChange.invoke r.w
    me.h.onChange.invoke r.h
    me.size.onChange.invoke(me.pRect.size)
    me.x.onChange.invoke r.x
    me.y.onChange.invoke r.y
    me.right.onChange.invoke(me.pRect.right)
    me.bottom.onChange.invoke(me.pRect.bottom)
    me.centerX.onChange.invoke(me.pRect.centerX)
    me.centerY.onChange.invoke(me.pRect.centerY)
    me.center.onChange.invoke(me.pRect.center)
    me.pos.onChange.invoke(me.pRect.pos)
    me.rect.onChange.invoke(me.pRect)
    me.requireRedraw

  me.rect = newProperty[Rect, EventRect](
    proc(): Rect = me.pRect, setRect, true)


proc newNElem*(): NElem =
  new result
  result.initNElem()


proc left*(e: NElem): var Property(cint) = e.x
proc top*(e: NElem): var Property(cint) = e.y

method draw*(e: NElem, parentRect: Rect, renderer: RendererPtr) 
  {.base, locks: 0.} =
  for c in e.children:
    c.draw(parentRect, renderer)


template processEventDefaultImpl*(e: NElem, ev: Event): EventResult =
  for c in e.children:
    let res = c.processEvent(ev)
    if res != erIgnored:
      return res
  erIgnored


method processEvent*(e: NElem, ev: Event): EventResult {.base, locks: 0.} =
  e.processEventDefaultImpl ev


proc add*(e: NElem, child: NElem) =
  child.parent = e
  e.children.add(child)

# -----------------------------------------------------------------------------
# Engine and Window
# -----------------------------------------------------------------------------

proc newEngine*(): Engine =
  new result
  init(INIT_TIMER or INIT_AUDIO or INIT_VIDEO).onFail:
    raise newException(NmlError, "Couldnt init SDL")
  ttfInit().onFail:
    raise newException(NmlError, "Couldnt init ttf")


proc createWindow*(e: Engine, w, h: int, root: NElem, title = "",
                flags: uint32 = SDL_WINDOW_RESIZABLE or 
                  SDL_WINDOW_INPUT_GRABBED or SDL_WINDOW_ALLOW_HIGHDPI,
                x = SDL_WINDOWPOS_UNDEFINED,
                y = SDL_WINDOWPOS_UNDEFINED)=
  let win = Window()
  win.win = createWindow(title, x, y, w.cint, h.cint, flags).onFail:
    raise newException(NmlError, "Couldnt create window")
  win.renderer = createRenderer(win.win, -1, Renderer_TargetTexture)
  win.renderer.setDrawBlendMode BlendMode_Blend
  root.pWindow = win
  win.rootElem = root
  root.rect.set(v(0.cint, 0.cint, w.cint, h.cint))
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


proc close*(w: Window) =
  let ev = QuitEventObj(kind: QuitEvent, timestamp: getTime().toUnix.uint32)
  if pushEvent(cast[ptr Event](ev.unsafeAddr)) != 1:
    raise newException(NmlError, "Window.close: " & $getError())


proc processWindowEvent(w: Window, ev: WindowEventPtr): EventResult =
  case ev.event:
    of WindowEvent_Shown, WindowEvent_Exposed, WindowEvent_Maximized,
        WindowEvent_Resized, WindowEvent_Restored, WindowEvent_SizeChanged:
      let winSize = w.win.getSize
      w.rootElem.rect.set((x: 0.cint, y: 0.cint, w: winSize.x, h: winSize.y))
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


proc pollEvents(): seq[Event] =
  var ev: Event
  while pollEvent(ev):
    result.add(ev)


proc run*(e: var Engine) =
  while e.windows.len > 0:
    let events = pollEvents() 

    if events.len == 0:
      sleep(frameDur)
      continue

    for ev in events:
      for i, w in e.windows:
        case w.processEvent ev:
          of erQuit:
            w.win.destroyWindow
            e.windows.delete i
            break
          of erConsumed: break
          of erIgnored: discard

    for w in e.windows:
      w.redrawIfNecessary()
