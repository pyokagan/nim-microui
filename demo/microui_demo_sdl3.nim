import std/math
import ../extern/sdl3/src/sdl3
import ../src/[microui, microui_demoatlas]
import microui_demo_common

func sdl_fcolor(c: MuColor): SDL_FColor {.noinit, inline, raises: [].} =
  result.r = c.r.cfloat / 255.cfloat
  result.g = c.g.cfloat / 255.cfloat
  result.b = c.b.cfloat / 255.cfloat
  result.a = c.a.cfloat / 255.cfloat

proc pushQuad(verts: var seq[SDL_Vertex]; indices: var seq[cint]; srcRect, dstRect: MuRect; color: MuColor; texWidth, texHeight: cint) {.inline, raises: [].} =
  let
    color = sdl_fcolor(color)
    x0 = cfloat dstRect.x
    y0 = cfloat dstRect.y
    x1 = cfloat dstRect.x + dstRect.w
    y1 = cfloat dstRect.y + dstRect.h
    u0 = cfloat(srcRect.x) / texWidth.cfloat
    v0 = cfloat(srcRect.y) / texHeight.cfloat
    u1 = cfloat(srcRect.x + srcRect.w) / texWidth.cfloat
    v1 = cfloat(srcRect.y + srcRect.h) / texHeight.cfloat
    baseIdx = verts.len.cint
  verts.add SDL_Vertex(position: SDL_FPoint(x: x0, y: y0), color: color, tex_coord: SDL_FPoint(x: u0, y: v0))
  verts.add SDL_Vertex(position: SDL_FPoint(x: x1, y: y0), color: color, tex_coord: SDL_FPoint(x: u1, y: v0))
  verts.add SDL_Vertex(position: SDL_FPoint(x: x1, y: y1), color: color, tex_coord: SDL_FPoint(x: u1, y: v1))
  verts.add SDL_Vertex(position: SDL_FPoint(x: x0, y: y1), color: color, tex_coord: SDL_FPoint(x: u0, y: v1))
  indices.add baseIdx + 0
  indices.add baseIdx + 1
  indices.add baseIdx + 2
  indices.add baseIdx + 2
  indices.add baseIdx + 3
  indices.add baseIdx + 0

type
  MuSdl3InputGrab* = enum
    muSdl3GrabNone
    muSdl3GrabMouse
    muSdl3GrabTouch
  MuSdl3Input* = object
    grab*: MuSdl3InputGrab
    mouseId*: SDL_MouseID ## (when grab == muSdl3GrabMouse), the mouse ID
    touchId*: SDL_TouchID
    fingerId*: SDL_FingerID
    dpr*: float32

proc tryMapSdl3ButtonToMuMouseButton(x: uint8; o: var MuMouseButton): bool {.inline, raises: [].} =
  if x == SDL_BUTTON_LEFT:
    o = muMouseLeft
    result = true
  elif x == SDL_BUTTON_MIDDLE:
    o = muMouseMiddle
    result = true
  elif x == SDL_BUTTON_RIGHT:
    o = muMouseRight
    result = true

func sdlKeymodToMuKeySet(x: SDL_Keymod): set[MuKey] {.inline, raises: [].} =
  if (x and SDL_KMOD_SHIFT) != 0:
    result.incl muKeyShift
  if (x and SDL_KMOD_CTRL) != 0:
    result.incl muKeyCtrl
  if (x and SDL_KMOD_ALT) != 0:
    result.incl muKeyAlt

proc inputMouseMotion*(self: var MuSdl3Input; mu: var MuContext; mouseId: SDL_MouseID; x, y: cfloat) {.inline, raises: [].} =
  ## to be called on {SDL_EVENT_MOUSE_MOTION, SDL_EVENT_MOUSE_BUTTON_DOWN, SDL_EVENT_MOUSE_BUTTON_UP}
  let invDpr = if self.dpr != 0: 1'f32 / self.dpr else: 1'f32
  if self.grab == muSdl3GrabNone or (self.grab == muSdl3GrabMouse and self.mouseId == mouseId):
    mu.inputMouseMove(floor(x * invDpr).int32, floor(y * invDpr).int32, teleport = self.grab == muSdl3GrabNone)

proc inputMouseButtonDown*(self: var MuSdl3Input; mu: var MuContext; mouseId: SDL_MouseID; button: uint8) {.inline, raises: [].} =
  ## to be called on SDL_EVENT_MOUSE_BUTTON_DOWN
  var mubtn: MuMouseButton
  if (self.grab == muSdl3GrabNone or (self.grab == muSdl3GrabMouse and self.mouseId == mouseId)) and tryMapSdl3ButtonToMuMouseButton(button, mubtn):
    mu.inputMouseDown({ mubtn })
    self.grab = muSdl3GrabMouse
    self.mouseId = mouseId

proc inputMouseButtonUp*(self: var MuSdl3Input; mu: var MuContext; mouseId: SDL_MouseID; button: uint8) {.inline, raises: [].} =
  ## to be called on SDL_EVENT_MOUSE_BUTTON_UP
  var mubtn: MuMouseButton
  if self.grab == muSdl3GrabMouse and self.mouseId == mouseId and tryMapSdl3ButtonToMuMouseButton(button, mubtn):
    mu.inputMouseUp({ mubtn })
    if mu.mouseDown == {}:
      self.grab = muSdl3GrabNone

proc inputMouseWheel*(self: var MuSdl3Input; mu: var MuContext; x, y: cfloat) {.inline, raises: [].} =
  mu.inputScroll(int32 x * 30.cfloat, int32 -y * 30.cfloat)

proc inputTextInput*(self: var MuSdl3Input; mu: var MuContext; text: cstring) {.inline, raises: [].} =
  let l = len(text)
  inputText(mu, toOpenArray(text, 0, l - 1))

proc inputKeyEvent*(self: var MuSdl3Input; mu: var MuContext; key: SDL_Keycode; keymod: SDL_Keymod; keyIsDown: bool) {.inline, raises: [].} =
  if key == SDLK_BACKSPACE:
    mu.inputKeyUpOrDown(muKeyBackspace, keyIsDown)
  elif key == SDLK_RETURN:
    mu.inputKeyUpOrDown(muKeyReturn, keyIsDown)
  mu.inputKeyState(mu.keyDown - sdlKeymodToMuKeySet(SDL_Keymod.high) + sdlKeymodToMuKeySet(keymod))

proc main() =
  const
    WindowWidth = 800
    WindowHeight = 600
  var
    window: SDL_Window
    renderer: SDL_Renderer
    atlasTexture: SDL_Texture
    mu: MuContext
    muSdl3: MuSdl3Input
    muDemo: MuDemo

  if not SDL_Init(SDL_INIT_VIDEO):
    quit("SDL_Init failed: " & $SDL_GetError())

  if not SDL_CreateWindowAndRenderer(nil, WindowWidth, WindowHeight, 0, window, renderer):
    quit("SDL_CreateWindowAndRenderer failed: " & $SDL_GetError())

  muSdl3.dpr = SDL_GetWindowDisplayScale(window)
  if muSdl3.dpr != 1:
    SDL_SetWindowSize(window, cint WindowWidth * muSdl3.dpr, cint WindowHeight * muSdl3.dpr)
    SDL_SetRenderScale(renderer, muSdl3.dpr, muSdl3.dpr)

  # Upload atlas texture
  block:
    var pixels {.noinit.}: array[MuDemoAtlasWidth * MuDemoAtlasHeight * 4, uint8]
    muUnpackDemoAtlasPixelsRgba(pixels, premultiplied = false)
    let surface = SDL_CreateSurfaceFrom(MuDemoAtlasWidth, MuDemoAtlasHeight, SDL_PIXELFORMAT_RGBA32, pixels[0].addr, MuDemoAtlasWidth * 4)
    if surface.isNil:
      quit("SDL_CreateSurfaceFrom failed: " & $SDL_GetError())

    atlasTexture = SDL_CreateTextureFromSurface(renderer, surface)
    if atlasTexture.isNil:
      quit("SDL_CreateTextureFromSurface failed: " & $SDL_GetError())
    SDL_SetTextureScaleMode(atlasTexture, SDL_SCALEMODE_NEAREST)

    SDL_DestroySurface(surface)

  mu.textWidth = muDemoAtlasTextWidthCb
  mu.textHeight = muDemoAtlasTextHeightCb
  muInit(mu)
  muDemoInit(muDemo)

  var
    running = true
    sdlVerts: seq[SDL_Vertex]
    sdlIndices: seq[cint]
  while running:
    var ev {.noinit.}: SDL_Event
    while SDL_PollEvent(ev):
      case ev.type
      of SDL_EVENT_QUIT:
        running = false
      of SDL_EVENT_MOUSE_MOTION:
        muSdl3.inputMouseMotion(mu, ev.motion.which, ev.motion.x, ev.motion.y)
      of SDL_EVENT_MOUSE_BUTTON_DOWN:
        muSdl3.inputMouseMotion(mu, ev.button.which, ev.button.x, ev.button.y)
        muSdl3.inputMouseButtonDown(mu, ev.button.which, ev.button.button)
      of SDL_EVENT_MOUSE_BUTTON_UP:
        muSdl3.inputMouseMotion(mu, ev.button.which, ev.button.x, ev.button.y)
        muSdl3.inputMouseButtonUp(mu, ev.button.which, ev.button.button)
      of SDL_EVENT_MOUSE_WHEEL:
        muSdl3.inputMouseWheel(mu, ev.wheel.x, ev.wheel.y)
      of SDL_EVENT_TEXT_INPUT:
        muSdl3.inputTextInput(mu, ev.text.text)
      of SDL_EVENT_KEY_DOWN:
        muSdl3.inputKeyEvent(mu, ev.key.key, ev.key.mod, true)
      of SDL_EVENT_KEY_UP:
        muSdl3.inputKeyEvent(mu, ev.key.key, ev.key.mod, false)
      else: discard

    muBegin(mu)
    runMuDemo(muDemo, mu)
    muEnd(mu)

    if mu.wantTextInput:
      discard SDL_StartTextInput(window)
    else:
      discard SDL_StopTextInput(window)

    SDL_SetRenderDrawColorFloat(renderer, muDemo.bg[0].cfloat / 255.cfloat, muDemo.bg[1].cfloat / 255.cfloat, muDemo.bg[2].cfloat / 255.cfloat, 1.cfloat)
    SDL_RenderClear(renderer)

    sdlVerts.setLen(0)
    sdlIndices.setLen(0)
    for (kind, nbytes, p) in mu.cmds.iterFollowJumps:
      case kind
      of muCommandRect:
        let v = cast[ptr MuRectCommand](p)
        pushQuad(sdlVerts, sdlIndices, MuDemoAtlasWhite, v.rect, v.color, MuDemoAtlasWidth, MuDemoAtlasHeight)

      of muCommandText, muCommandTextClipped:
        let v = cast[ptr MuTextCommand](p)
        let ss_len = nbytes - sizeof(MuTextCommand)
        for (srcRect, dstRect) in muDemoAtlasTextAsTexRectsClipped(v.str.addr, ss_len, v.pos, v.clipRect):
          pushQuad(sdlVerts, sdlIndices, srcRect, dstRect, v.color, MuDemoAtlasWidth, MuDemoAtlasHeight)

      of muCommandIcon, muCommandIconClipped:
        let v = cast[ptr MuIconCommand](p)
        let (srcRect, dstRect) = muDemoAtlasIconAsTexRectClipped(v.id, v.rect, v.clipRect)
        pushQuad(sdlVerts, sdlIndices, srcRect, dstRect, v.color, MuDemoAtlasWidth, MuDemoAtlasHeight)

      else: discard

    if sdlIndices.len > 0:
      SDL_RenderGeometry(renderer, atlasTexture, sdlVerts[0].addr, sdlVerts.len.cint, sdlIndices[0].addr, sdlIndices.len.cint)
    SDL_RenderPresent(renderer)

when isMainModule:
  main()
