import std/[hashes, parseutils]
when NimMajor >= 2:
  import std/formatfloat
else:
  import system/formatfloat

const
  MuCommandListSize* = 256 * 1024
  MuRootListSize* = 32
  MuContainerStackSize* = 32
  MuClipStackSize* = 32
  MuIdStackSize* = 32
  MuLayoutStackSize* = 16
  MuContainerPoolSize* = 48
  MuTreeNodePoolSize* = 48
  MuMaxWidths* = 16

type
  MuReal* = float32
  MuFont* = distinct pointer
  MuFrameIdx = uint32

  MuVec2* = object
    x*, y*: int32

  MuRect* = object
    x*, y*, w*, h*: int32

  MuColor* = object
    r*, g*, b*, a*: uint8

func muVec2*(x, y: int32): MuVec2 {.noinit, inline, raises: [].} =
  result.x = x
  result.y = y

func `+`*(a, b: MuVec2): MuVec2 {.noinit, inline, raises: [].} =
  result.x = a.x + b.x
  result.y = a.y + b.y

func `+=`*(self: var MuVec2; b: MuVec2) {.inline, raises: [].} =
  self.x.inc b.x
  self.y.inc b.y

func `-`*(a, b: MuVec2): MuVec2 {.noinit, inline, raises: [].} =
  result.x = a.x - b.x
  result.y = a.y - b.y

func muRect*(x, y, w, h: int32): MuRect {.noinit, inline, raises: [].} =
  result.x = x
  result.y = y
  result.w = w
  result.h = h

func topLeft(r: MuRect): MuVec2 {.noinit, inline, raises: [].} =
  result.x = r.x
  result.y = r.y

func expand(r: MuRect; n: int32): MuRect {.noinit, inline, raises: [].} =
  result.x = r.x - n
  result.y = r.y - n
  result.w = r.w + (n + n)
  result.h = r.h + (n + n)

func intersection(r1, r2: MuRect): MuRect {.noinit, inline, raises: [].} =
  let
    x1 = max(r1.x, r2.x)
    y1 = max(r1.y, r2.y)
    x2 = max(min(r1.x + r1.w, r2.x + r2.w), x1)
    y2 = max(min(r1.y + r1.h, r2.y + r2.h), y1)
  result.x = x1
  result.y = y1
  result.w = x2 - x1
  result.h = y2 - y1

func intersects(r: MuRect; p: MuVec2): bool {.inline, raises: [].} =
  p.x >= r.x and p.x < (r.x + r.w) and p.y >= r.y and p.y < (r.y + r.h)

func muColor*(r, g, b, a: uint8): MuColor {.noinit, inline, raises: [].} =
  result.r = r
  result.g = g
  result.b = b
  result.a = a

type
  MuId* = distinct uint32

func `$`*(x: MuId): string {.borrow.}
func `==`*(x, y: MuId): bool {.borrow.}

# Render commands

type
  MuCommandHeader {.pure, union.} = object
    u64: uint64
    u: tuple[kind, nbytes: int32]

  MuJumpCommand {.pure.} = object
    dst: int32 ## destination into `cmds`

  MuRectCommand* {.pure.} = object
    rect*: MuRect
    color*: MuColor

  MuTextCommand* {.pure.} = object
    clipRect*: MuRect
    font*: MuFont # pointer
    pos*: MuVec2
    color*: MuColor
    str*: UncheckedArray[char]

  MuIconCommand* {.pure.} = object
    clipRect*: MuRect
    rect*: MuRect
    id*: int32
    color*: MuColor

  MuCommandList* = object
    idx*: int32 # in `elems`
    data*: array[(MuCommandListSize + 7) div 8, MuCommandHeader]

const
  muCommandJump* = 1
  muCommandRect* = 2
  muCommandText* = 3
  muCommandTextClipped* = 4
  muCommandIcon* = 5
  muCommandIconClipped* = 6
  muCommandUser* = 7

func muCommandHeader(kind, nbytes: int32): MuCommandHeader {.noinit, inline, raises: [].} =
  result.u.kind = kind
  result.u.nbytes = nbytes

func allocCommand*(self: var MuCommandList; kind, nbytes: int32): pointer {.inline, raises: [].} =
  ## 1. call `pushCommand()`
  ## 2. Write your command's data into the returned pointer
  assert kind > 0
  let nelems = ((nbytes + 7) shr 3)
  assert((len(self.data) - self.idx) >= nelems + 1)
  self.data[self.idx] = muCommandHeader(kind, nbytes)
  inc(self.idx)
  result = self.data[self.idx].addr
  inc(self.idx, nelems)

func addCommand*[T](self: var MuCommandList; kind: int32; cmd: T) {.inline, raises: [].} =
  let cmd_p = cast[ptr T](self.allocCommand(kind, int32 sizeof(T)))
  {.cast(noSideEffect).}: # store is into array embedded in MuCommandList
    cmd_p[] = cmd

func addTextCommand*(self: var MuCommandList; kind: int32; clipRect: MuRect; font: MuFont; pos: MuVec2; color: MuColor; str: openArray[char]) {.inline, raises: [].} =
  let l = len(str).int32
  let cmd_p = cast[ptr MuTextCommand](self.allocCommand(kind, int32 sizeof(MuTextCommand) + l))
  {.cast(noSideEffect).}: # stores are into array embedded in MuCommandList
    cmd_p.clipRect = clipRect
    cmd_p.font = font
    cmd_p.pos = pos
    cmd_p.color = color
    if l > 0:
      copyMem(cmd_p.str[0].addr, str[0].unsafeAddr, l)

func backpatchJump(self: var MuCommandList; cmdIdx, dst: int32) {.inline, raises: [].} =
  let p = cast[ptr MuJumpCommand](self.data[cmdIdx + 1].addr)
  {.cast(noSideEffect).}: # store is into array embedded in MuCommandList
    p[] = MuJumpCommand(dst: dst)

iterator iterFollowJumps*(self: MuCommandList): tuple[kind, nbytes: int32; p: pointer] =
  let l = self.idx
  var i = 0
  while i < l:
    let hdr = self.data[i]; inc i
    if hdr.u.kind == muCommandJump:
      i = cast[ptr MuJumpCommand](self.data[i].unsafeAddr)[].dst
      continue
    yield (kind: hdr.u.kind, nbytes: hdr.u.nbytes, p: self.data[i].unsafeAddr.pointer)
    inc(i, (hdr.u.nbytes + 7) shr 3)

type
  MuPoolItem = object
    id*: MuId
    lastUpdate*: MuFrameIdx

func poolAlloc(its: var openArray[MuPoolItem]; id: MuId; frame: MuFrameIdx): int {.inline, raises: [].} =
  assert(len(its) > 0)
  var maxAgeSoFar = frame - its[0].lastUpdate
  result = 0
  for i in 1 ..< len(its):
    let age = frame - its[i].lastUpdate
    if age >= maxAgeSoFar:
      maxAgeSoFar = age
      result = i
  its[result].id = id
  its[result].lastUpdate = frame

func poolGet(its: openArray[MuPoolItem]; id: MuId): int {.inline, raises: [].} =
  for i in 0 ..< len(its):
    if its[i].id == id:
      return i
  result = -1

func poolUpdate(its: var openArray[MuPoolItem]; idx: int; frame: MuFrameIdx) {.inline, raises: [].} =
  its[idx].lastUpdate = frame

type
  MuStack[N: static int; T] = object
    idx*: int32
    its*: array[N, T]

func push[N, T](stk: var MuStack[N, T]; val: T) {.inline, raises: [].} =
  assert(stk.idx < stk.its.len)
  stk.its[stk.idx] = val
  inc stk.idx

func pop[N, T](stk: var MuStack[N, T]) {.inline, raises: [].} =
  assert(stk.idx > 0)
  dec stk.idx

type
  MuMouseButton* = enum
    muMouseLeft
    muMouseRight
    muMouseMiddle

  MuKey* = enum
    muKeyShift
    muKeyCtrl
    muKeyAlt
    muKeyBackspace
    muKeyReturn

  MuRes* = enum
    muResActive
    muResSubmit
    muResChange

  MuLayoutNextKind = enum
    muLayoutNextIsAuto
    muLayoutNextIsRelative
    muLayoutNextIsAbsolute

  MuLayout* = object
    body*: MuRect
      ## (absolute coords)
    next*: MuRect
      ## (if nextKind in {muLayoutNextIsRelative, muLayoutNextIsAbsolute}), next rect
    position*: MuVec2
    size*: MuVec2
    max*: MuVec2
      ## (absolute coords)
    widths*: array[MuMaxWidths, int32]
    nitems*: int32
    itemIndex*: int32
    nextRow*: int32
    nextKind*: MuLayoutNextKind
    indent*: int32

  MuContainer* = object
    head, tail: int32 ## idx into cmds
    rect*: MuRect
    body*: MuRect
    contentSize*: MuVec2
    scroll*: MuVec2
    zindex*: int32
    open*: bool

  MuContainerIdx* = int32
  MuContainerRef* = object
    ctx*: ptr MuContext
    idx*: MuContainerIdx

  MuStyleColor* = enum
    muColorText
    muColorBorder
    muColorWindowBg
    muColorTitleBg
    muColorTitleText
    muColorPanelBg
    muColorButton
    muColorButtonHover
    muColorButtonFocus
    muColorBase
    muColorBaseHover
    muColorBaseFocus
    muColorScrollBase
    muColorScrollThumb

  MuStyle* = object
    font*: MuFont
    size*: MuVec2
    padding*: int32
    spacing*: int32
    indent*: int32
    titleHeight*: int32
    scrollbarSize*: int32
    thumbSize*: int32
    colors*: array[MuStyleColor, MuColor]

  MuOpt* = enum
    muOptAlignCenter
    muOptAlignRight
    muOptNoInteract
    muOptNoFrame
    muOptNoResize
    muOptNoScroll
    muOptNoClose
    muOptNoTitle
    muOptHoldFocus
    muOptAutoSize
    muOptPopup
    muOptClosed
    muOptExpanded
    muOptTextInput

  MuContext* = object
    # callbacks
    userdata*: pointer
    textWidth*: proc (ctx: var MuContext; font: MuFont; str: openArray[char]): int32 {.noSideEffect, nimcall, gcsafe, raises: [].}
    textHeight*: proc (ctx: var MuContext; font: MuFont): int32 {.noSideEffect, nimcall, gcsafe, raises: [].}
    drawFrame*: proc (ctx: var MuContext; rect: MuRect; color: MuStyleColor) {.noSideEffect, nimcall, gcsafe, raises: [].}

    # core state
    style*: MuStyle
    hover*, focus*: MuId
    lastZindex*: int32
    updatedFocus*: bool
    frame*: MuFrameIdx
    hoverRoot*, nextHoverRoot*, scrollTarget*: MuContainerIdx
      ## idx into `containers`
    wantTextInput*: bool
      ## whether a widget desires inputText

    cmds*: MuCommandList

    # stacks
    rootList*: MuStack[MuRootListSize, MuContainerIdx]
    containerStack*: MuStack[MuContainerStackSize, MuContainerIdx]
    clipStack*: MuStack[MuClipStackSize, MuRect]
    idStack*: MuStack[MuIdStackSize, MuId]
    layoutStack*: MuStack[MuLayoutStackSize, MuLayout]

    # retained state pools
    containerPool*: array[MuContainerPoolSize, MuPoolItem]
    cnt*: array[MuContainerPoolSize, MuContainer]
    treenodePool*: array[MuTreeNodePoolSize, MuPoolItem]

    # input state
    mousePos*: MuVec2
    lastMousePos*: MuVec2
    mouseDelta*: MuVec2
    scrollDelta*: MuVec2
    mouseDown*, mousePressed*: set[MuMouseButton]
    keyDown*, keyPressed*: set[MuKey]
    inputText*: array[32, char]
    inputTextLen*: int32

    # state storage for numberTextbox
    numberEditBuf: array[128, char]
    numberEditBufLen: int
    numberEdit: MuId

const
  muIconClose* = 1
  muIconCheck* = 2
  muIconCollapsed* = 3
  muIconExpanded* = 4

  MuDefaultStyle* = MuStyle(
    size: MuVec2(x: 68, y: 10),
    padding: 5,
    spacing: 4,
    indent: 24,
    titleHeight: 24,
    scrollbarSize: 12,
    thumbSize: 8,
    colors: [
      muColorText: MuColor(r: 230, g: 230, b: 230, a: 255),
      muColorBorder: MuColor(r: 25, g: 25, b: 25, a: 255),
      muColorWindowBg: MuColor(r: 50, g: 50, b: 50, a: 255),
      muColorTitleBg: MuColor(r: 25, g: 25, b: 25, a: 255),
      muColorTitleText: MuColor(r: 240, g: 240, b: 240, a: 255),
      muColorPanelBg: MuColor(r: 0, g: 0, b: 0, a: 0),
      muColorButton: MuColor(r: 75, g: 75, b: 75, a: 255),
      muColorButtonHover: MuColor(r: 95, g: 95, b: 95, a: 255),
      muColorButtonFocus: MuColor(r: 115, g: 115, b: 115, a: 255),
      muColorBase: MuColor(r: 30, g: 30, b: 30, a: 255),
      muColorBaseHover: MuColor(r: 35, g: 35, b: 35, a: 255),
      muColorBaseFocus: MuColor(r: 40, g: 40, b: 40, a: 255),
      muColorScrollBase: MuColor(r: 43, g: 43, b: 43, a: 255),
      muColorScrollThumb: MuColor(r: 30, g: 30, b: 30, a: 255),
    ])

  UnclippedRect = MuRect(x: 0, y: 0, w: 0x1000000, h: 0x1000000)

func setFocus*(ctx: var MuContext; id: MuId) {.inline, raises: [].} =
  ctx.focus = id
  ctx.updatedFocus = true

# Input handlers

func inputMouseMove*(ctx: var MuContext; x, y: int32; teleport = false) {.inline, raises: [].} =
  ctx.mousePos = muVec2(x, y)
  if teleport:
    ctx.lastMousePos = muVec2(x, y)

func inputMouseDown*(ctx: var MuContext; btns: set[MuMouseButton]) {.inline, raises: [].} =
  ctx.mouseDown = ctx.mouseDown + btns
  ctx.mousePressed = ctx.mousePressed + btns

func inputMouseDown*(ctx: var MuContext; x, y: int32; btns: set[MuMouseButton]) {.inline, raises: [].} =
  ctx.inputMouseMove(x, y)
  ctx.inputMouseDown(btns)

func inputMouseUp*(ctx: var MuContext; btns: set[MuMouseButton]) {.inline, raises: [].} =
  ctx.mouseDown = ctx.mouseDown - btns

func inputMouseUp*(ctx: var MuContext; x, y: int32; btns: set[MuMouseButton]) {.inline, raises: [].} =
  ctx.inputMouseMove(x, y)
  ctx.inputMouseUp(btns)

func inputScroll*(ctx: var MuContext; x, y: int32) {.inline, raises: [].} =
  ctx.scrollDelta.x = ctx.scrollDelta.x + x
  ctx.scrollDelta.y = ctx.scrollDelta.y + y

func inputKeyDown*(ctx: var MuContext; key: MuKey) {.inline, raises: [].} =
  ctx.keyPressed.incl key
  ctx.keyDown.incl key

func inputKeyUp*(ctx: var MuContext; key: MuKey) {.inline, raises: [].} =
  ctx.keyDown.excl key

func inputKeyUpOrDown*(ctx: var MuContext; key: MuKey; down: bool) {.inline, raises: [].} =
  if down:
    ctx.inputKeyDown(key)
  else:
    ctx.inputKeyUp(key)

func inputKeyState*(ctx: var MuContext; keys: set[MuKey]) {.inline, raises: [].} =
  ctx.keyPressed = ctx.keyPressed + (keys - ctx.keyDown)
  ctx.keyDown = keys

func inputText*(ctx: var MuContext; text: openArray[char]) {.inline, raises: [].} =
  let l = len(text)
  if l <= 0:
    return
  let nbytesToCopy = min(len(ctx.inputText) - ctx.inputTextLen, l)
  copyMem(ctx.inputText[ctx.inputTextLen].addr, text[0].unsafeAddr, nbytesToCopy)
  inc(ctx.inputTextLen, nbytesToCopy)

# ID Stack

const
  HashInitial = 2_166_136_261'u32

func getId*(ctx: var MuContext; data: pointer; size: int): MuId {.inline, raises: [].} =
  let idx = ctx.idStack.idx
  var h = if idx > 0: ctx.idStack.its[idx - 1].uint32 else: HashInitial
  let data_p = cast[ptr UncheckedArray[uint8]](data)
  for i in 0 ..< size:
    h = (h xor data_p[i]) * 16777619'u32
  result = MuId h

func getIdFromInt*(ctx: var MuContext; data: int): MuId {.inline, raises: [].} =
  type
    IntUnion {.pure, union.} = object
      i: int
      e: array[sizeof(int), uint8]
  var tmp {.noinit.}: IntUnion
  tmp.i = data
  result = getId(ctx, tmp.e[0].addr, sizeof(tmp.e))

func getId*(ctx: var MuContext; data: openArray[char]): MuId {.inline, raises: [].} =
  let l = len(data)
  ctx.getId(if l > 0: data[0].unsafeAddr else: nil, l)

func pushId*(ctx: var MuContext; id: MuId) {.inline, raises: [].} =
  ctx.idStack.push id

func popId*(ctx: var MuContext) {.inline, raises: [].} =
  ctx.idStack.pop()

func muMakeLineHash(info: tuple[filename: string; line, column: int]): Hash =
  var s = info.filename & ":" & $info.line & ":" & $info.column
  result = hash(s) # use nim hash because nim VM implements it natively

template lineId*(ctx: var MuContext): MuId =
  bind getIdFromInt, muMakeLineHash, instantiationInfo
  getIdFromInt(ctx, static(muMakeLineHash(instantiationInfo(fullPaths = true))))

# Clipping

func getClipRect*(ctx: MuContext): MuRect {.noinit, inline, raises: [].} =
  assert(ctx.clipStack.idx > 0)
  result = ctx.clipStack.its[ctx.clipStack.idx - 1]

func pushClipRect*(ctx: var MuContext; r: MuRect) {.inline, raises: [].} =
  let last = ctx.getClipRect()
  ctx.clipStack.push intersection(r, last)

func popClipRect*(ctx: var MuContext) {.inline, raises: [].} =
  ctx.clipStack.pop()

type
  MuClipResult* = enum
    muNotClipped
    muClipAll
    muClipPart

func checkClip*(ctx: MuContext; r: MuRect): MuClipResult {.inline, raises: [].} =
  let cr = ctx.getClipRect()
  if r.x > (cr.x + cr.w) or (r.x + r.w) < cr.x or r.y > (cr.y + cr.h) or (r.y + r.h) < cr.y:
    result = muClipAll
  elif r.x >= cr.x and (r.x + r.w) <= (cr.x + cr.w) and r.y >= cr.y and (r.y + r.h) <= (cr.y + cr.h):
    result = muNotClipped
  else:
    result = muClipPart

# Layout

template topLayout(ctx: MuContext): untyped =
  ctx.layoutStack.its[ctx.layoutStack.idx - 1]

func layoutRow(topLayout: var MuLayout) {.inline, raises: [].} =
  topLayout.position = muVec2(topLayout.indent, topLayout.nextRow)
  topLayout.itemIndex = 0

func layoutRow*(ctx: var MuContext) {.inline, raises: [].} =
  ## begin a new row
  assert(ctx.layoutStack.idx > 0)
  ctx.topLayout.layoutRow()

func layoutRow(topLayout: var MuLayout; widths: openArray[int32]; height: int32) {.inline, raises: [].} =
  let nitems = min(len(widths), len(topLayout.widths))
  for i in 0 ..< nitems:
    topLayout.widths[i] = widths[i]
  topLayout.nitems = nitems.int32
  topLayout.size.y = height
  topLayout.layoutRow()

func layoutRow*(ctx: var MuContext; widths: openArray[int32]; height: int32) {.inline, raises: [].} =
  ## begin a new row, and configure its items
  assert(ctx.layoutStack.idx > 0)
  ctx.topLayout.layoutRow(widths, height)

func layoutWidth*(ctx: var MuContext; width: int32) {.inline, raises: [].} =
  ## set width of current layout
  assert(ctx.layoutStack.idx > 0)
  ctx.topLayout.size.x = width

func layoutHeight*(ctx: var MuContext; height: int32) {.inline, raises: [].} =
  ## set height of current layout
  assert(ctx.layoutStack.idx > 0)
  ctx.topLayout.size.y = height

func layoutSetNext(topLayout: var MuLayout; r: MuRect; relative: bool) {.inline, raises: [].} =
  topLayout.next = r
  topLayout.nextKind = if relative: muLayoutNextIsRelative else: muLayoutNextIsAbsolute

func layoutSetNext*(ctx: var MuContext; r: MuRect; relative: bool) {.inline, raises: [].} =
  assert(ctx.layoutStack.idx > 0)
  ctx.topLayout.layoutSetNext(r, relative)

func layoutNext(layout: var MuLayout; style: MuStyle): MuRect {.noinit, raises: [].} =
  if layout.nextKind != muLayoutNextIsAuto:
    # handle rect set by `layoutSetNext()`
    let isAbsolute = layout.nextKind == muLayoutNextIsAbsolute
    layout.nextKind = muLayoutNextIsAuto
    result = layout.next
    if isAbsolute:
      return
  else:
    # handle next row
    if layout.itemIndex >= layout.nitems:
      layout.layoutRow()

    # position
    result.x = layout.position.x
    result.y = layout.position.y

    # size
    result.w = if layout.nitems > 0: layout.widths[layout.itemIndex] else: layout.size.x
    result.h = layout.size.y

    if result.w == 0:
      result.w = style.size.x + style.padding * 2
    if result.h == 0:
      result.h = style.size.y + style.padding * 2
    if result.w < 0:
      result.w = result.w + layout.body.w - result.x + 1
    if result.h < 0:
      result.h = result.h + layout.body.h - result.y + 1

    inc layout.itemIndex

  # update position
  layout.position.x = layout.position.x + result.w + style.spacing
  layout.nextRow = max(layout.nextRow, result.y + result.h + style.spacing)

  # apply body offset
  result.x = result.x + layout.body.x
  result.y = result.y + layout.body.y

  # update max position
  layout.max.x = max(layout.max.x, result.x + result.w)
  layout.max.y = max(layout.max.y, result.y + result.h)

func layoutNext*(ctx: var MuContext): MuRect {.noinit, raises: [].} =
  assert(ctx.layoutStack.idx > 0)
  ctx.topLayout.layoutNext(ctx.style)

func pushLayout(ctx: var MuContext; body: MuRect; scroll: MuVec2) {.inline, raises: [].} =
  let body = muRect(body.x - scroll.x, body.y - scroll.y, body.w, body.h)
  ctx.layoutStack.push MuLayout(body: body, max: muVec2(-0x1000000, -0x1000000))
  ctx.layoutRow([0'i32], 0)

func layoutBeginColumn*(ctx: var MuContext) {.raises: [].} =
  let body = ctx.layoutNext()
  ctx.pushLayout(body, muVec2(0, 0))

func layoutEndColumn*(a: var MuLayout; b: MuLayout) {.inline, raises: [].} =
  # inherit position/nextRow/max from child layout if they are greater
  a.position.x = max(a.position.x, b.position.x + b.body.x - a.body.x)
  a.nextRow = max(a.nextRow, b.nextRow + b.body.y - a.body.y)
  a.max.x = max(a.max.x, b.max.x)
  a.max.y = max(a.max.y, b.max.y)

func layoutEndColumn*(ctx: var MuContext) {.inline, raises: [].} =
  let b = ctx.topLayout
  ctx.layoutStack.pop()
  layoutEndColumn(ctx.topLayout, b)

# Drawing

func drawRect*(ctx: var MuContext; rect: MuRect; color: MuColor) {.inline, raises: [].} =
  let rect = intersection(rect, ctx.getClipRect())
  if rect.w > 0 and rect.h > 0:
    let cmd = cast[ptr MuRectCommand](ctx.cmds.allocCommand(muCommandRect, int32 sizeof(MuRectCommand)))
    {.cast(noSideEffect).}:
      cmd[] = MuRectCommand(rect: rect, color: color)

func drawBox*(ctx: var MuContext; rect: MuRect; color: MuColor) {.inline, raises: [].} =
  ctx.drawRect(muRect(rect.x + 1, rect.y, rect.w - 2, 1), color)
  ctx.drawRect(muRect(rect.x + 1, rect.y + rect.h - 1, rect.w - 2, 1), color)
  ctx.drawRect(muRect(rect.x, rect.y, 1, rect.h), color)
  ctx.drawRect(muRect(rect.x + rect.w - 1, rect.y, 1, rect.h), color)

func drawText*(ctx: var MuContext; font: MuFont; s: openArray[char]; pos: MuVec2; color: MuColor) {.raises: [].} =
  let rect = muRect(pos.x, pos.y, ctx.textWidth(ctx, font, s), ctx.textHeight(ctx, font))
  let clipped = ctx.checkClip(rect)
  if clipped != muClipAll:
    ctx.cmds.addTextCommand(if clipped == muClipPart: muCommandTextClipped else: muCommandText, ctx.getClipRect(), font, pos, color, s)

func drawIcon*(ctx: var MuContext; id: int32; rect: MuRect; color: MuColor) {.raises: [].} =
  let clipped = ctx.checkClip(rect)
  if clipped != muClipAll:
    ctx.cmds.addCommand(if clipped == muClipPart: muCommandIconClipped else: muCommandIcon, MuIconCommand(clipRect: ctx.getClipRect(), id: id, rect: rect, color: color))

# Controls

func defaultDrawFrame(ctx: var MuContext; rect: MuRect; color: MuStyleColor) {.raises: [].} =
  ctx.drawRect(rect, ctx.style.colors[color])
  if color in {muColorScrollBase, muColorScrollThumb, muColorTitleBg}:
    return # these colors have no border
  if ctx.style.colors[muColorBorder].a > 0:
    ctx.drawBox(rect.expand(1), ctx.style.colors[muColorBorder])

func drawControlFrame*(ctx: var MuContext; id: MuId; rect: MuRect; color: MuStyleColor; opts: set[MuOpt]) {.raises: [].} =
  assert(color == muColorBase or color == muColorButton)
  if opts.contains(muOptNoFrame):
    return
  var color = color
  if ctx.focus == id:
    color = MuStyleColor color.ord + 2
  elif ctx.hover == id:
    color = MuStyleColor color.ord + 1
  ctx.drawFrame(ctx, rect, color)

func drawControlText*(ctx: var MuContext; str: openArray[char]; rect: MuRect; color: MuStyleColor; opts: set[MuOpt]) {.raises: [].} =
  let font = ctx.style.font
  let tw = ctx.textWidth(ctx, font, str)
  ctx.pushClipRect(rect)
  let pos_y = rect.y + (rect.h - ctx.textHeight(ctx, font)) shr 1
  let pos_x =
    if opts.contains(muOptAlignCenter):
      rect.x + (rect.w - tw) shr 1
    elif opts.contains(muOptAlignRight):
      rect.x + rect.w - tw - ctx.style.padding
    else:
      rect.x + ctx.style.padding
  ctx.drawText(font, str, muVec2(pos_x, pos_y), ctx.style.colors[color])
  ctx.popClipRect()

func topContainer*(ctx: var MuContext): MuContainerRef {.inline, raises: [].} =
  assert ctx.containerStack.idx > 0
  result.ctx = ctx.addr
  result.idx = ctx.containerStack.its[ctx.containerStack.idx - 1]

func inHoverRoot(ctx: MuContext): bool {.inline, raises: [].} =
  if ctx.hoverRoot < 0:
    return false
  # find our current root container
  for i in countdown(ctx.containerStack.idx - 1, 0'i32):
    let cntIdx = ctx.containerStack.its[i]
    if cntIdx == ctx.hoverRoot:
      return true
    # only root containers have their `head` field set;
    # stop searching if we've reached the current root container
    if ctx.cnt[cntIdx].head >= 0:
      break

func mouseOver*(ctx: MuContext; rect: MuRect): bool {.inline, raises: [].} =
  rect.intersects(ctx.mousePos) and ctx.getClipRect().intersects(ctx.mousePos) and ctx.inHoverRoot

func updateControl*(ctx: var MuContext; id: MuId; rect: MuRect; opts: set[MuOpt]) {.raises: [].} =
  assert id.int != 0

  if ctx.focus == id:
    ctx.updatedFocus = true # control is still alive!

  if opts.contains(muOptNoInteract):
    return

  let hover = ctx.mouseOver(rect)
  if hover and ctx.mouseDown == {}:
    ctx.hover = id

  # clear focus conditions
  if ctx.focus == id:
    let
      clickOutOfRect = ctx.mousePressed != {} and (not hover)
      mouseIsUp = ctx.mouseDown == {} and (muOptHoldFocus notin opts)
    if clickOutOfRect or mouseIsUp:
      ctx.setFocus(MuId(0)) # clear focus

  # grab focus conditions
  if hover and ctx.mousePressed != {}:
    ctx.setFocus(id)

  if ctx.hover == id and (not hover):
    ctx.hover = MuId(0)

  if ctx.focus == id and opts.contains(muOptTextInput):
    ctx.wantTextInput = true

func Label*(ctx: var MuContext; text: openArray[char]) {.raises: [].} =
  let rect = ctx.layoutNext()
  ctx.drawControlText(text, rect, muColorText, {})

func findEndOfWord(text: openArray[char]; idx: int): int {.inline, raises: [].} =
  result = idx
  while result < len(text) and text[result] notin {'\n', ' '}:
    inc result

func Text*(ctx: var MuContext; text: openArray[char]) {.raises: [].} =
  let
    font = ctx.style.font
    color = ctx.style.colors[muColorText]
    textHeight = ctx.textHeight(ctx, font)
  ctx.layoutBeginColumn()
  ctx.layoutRow([ -1'i32 ], textHeight)
  if len(text) <= 0:
    discard ctx.layoutNext()
  var idx = 0
  while idx < len(text):
    let r = ctx.layoutNext()
    let lineStartIdx = idx
    var lineEndIdx = idx
    var w = 0'i32
    while idx < len(text):
      let wordEndIdx = findEndOfWord(text, idx)
      w.inc ctx.textWidth(ctx, font, toOpenArray(text, idx, wordEndIdx - 1))
      if w > r.w and lineEndIdx > lineStartIdx:
        break # don't use this word -- it exceeds line width
      idx = wordEndIdx # use this word
      lineEndIdx = idx
      if idx < len(text):
        if text[idx] == '\n':
          inc idx
          break
        w.inc ctx.textWidth(ctx, font, toOpenArray(text, idx, idx))
        inc idx
    ctx.drawText(font, toOpenArray(text, lineStartIdx, lineEndIdx - 1), muVec2(r.x, r.y), color)
  ctx.layoutEndColumn()

func Button*(ctx: var MuContext; id: MuId; label: openArray[char]; icon = 0'i32; opts: set[MuOpt] = {muOptAlignCenter}): bool {.discardable, raises: [].} =
  var icon = icon
  let r = ctx.layoutNext()
  ctx.updateControl(id, r, opts)

  # handle click
  if ctx.mousePressed == {muMouseLeft} and ctx.focus == id:
    result = true

  # draw
  ctx.drawControlFrame(id, r, muColorButton, opts)
  if label.len > 0:
    ctx.drawControlText(label, r, muColorText, opts)
  if icon > 0:
    ctx.drawIcon(icon, r, ctx.style.colors[muColorText])

func Button*(ctx: var MuContext; label: openArray[char]; icon = 0'i32; opts: set[MuOpt] = {muOptAlignCenter}): bool {.discardable, raises: [].} =
  result = Button(ctx, ctx.getId(label), label, icon, opts)

func Checkbox*(ctx: var MuContext; id: MuId; label: openArray[char]; state: var bool): bool {.discardable, raises: [].} =
  let r = ctx.layoutNext()
  let box = muRect(r.x, r.y, r.h, r.h)
  ctx.updateControl(id, r, {})
  # handle click
  if ctx.mousePressed == {muMouseLeft} and ctx.focus == id:
    result = true
    state = not state
  # draw
  ctx.drawControlFrame(id, box, muColorBase, {})
  if state:
    ctx.drawIcon(muIconCheck, box, ctx.style.colors[muColorText])
  if label.len > 0:
    ctx.drawControlText(label, muRect(r.x + box.w, r.y, r.w - box.w, r.h), muColorText, {})

func Checkbox*(ctx: var MuContext; label: openArray[char]; state: var bool): bool {.discardable, raises: [].} =
  result = Checkbox(ctx, ctx.getId(label), label, state)

func TextboxRaw*(ctx: var MuContext; id: MuId; buf: var openArray[char]; bufLen: var int; r: MuRect; opts: set[MuOpt]): set[MuRes] {.raises: [].} =
  let bufCap = len(buf)
  bufLen = min(bufLen, bufCap)
  ctx.updateControl(id, r, opts + {muOptHoldFocus, muOptTextInput})

  if ctx.focus == id:
    # handle text input
    let nToCopy = min(ctx.inputTextLen.int, bufCap - bufLen)
    if nToCopy > 0:
      copyMem(buf[bufLen].addr, ctx.inputText[0].addr, nToCopy)
      inc(bufLen, nToCopy)
      result.incl muResChange

    # handle backspace
    if ctx.keyPressed.contains(muKeyBackspace) and bufLen > 0:
      # skip utf-8 continuation bytes
      while bufLen > 0:
        dec(bufLen)
        if (buf[bufLen].uint8 and 0xc0) != 0x80:
          break
      result.incl muResChange

    # handle return
    if ctx.keyPressed.contains(muKeyReturn):
      ctx.setFocus(MuId 0)
      result.incl muResSubmit

  # draw
  ctx.drawControlFrame(id, r, muColorBase, opts)
  if ctx.focus == id:
    let
      color = ctx.style.colors[muColorText]
      font = ctx.style.font
      textw = ctx.textWidth(ctx, font, toOpenArray(buf, 0, bufLen - 1))
      texth = ctx.textHeight(ctx, font)
      ofx = r.w - ctx.style.padding - textw - 1
      textx = r.x + min(ofx, ctx.style.padding)
      texty = r.y + (r.h - texth) shr 1
    ctx.pushClipRect(r)
    ctx.drawText(font, toOpenArray(buf, 0, bufLen - 1), muVec2(textx, texty), color)
    ctx.drawRect(muRect(textx + textw, texty, 1, texth), color)
    ctx.popClipRect()
  else:
    ctx.drawControlText(toOpenArray(buf, 0, bufLen - 1), r, muColorText, opts)

func numberTextbox(ctx: var MuContext; value: var MuReal; r: MuRect; id: MuId): bool {.raises: [].} =
  if ctx.mousePressed == {muMouseLeft} and ctx.keyDown.contains(muKeyShift) and ctx.hover == id:
    ctx.numberEdit = id
    var tmp {.noinit.}: array[65, char]
    ctx.numberEditBufLen = writeFloatToBuffer(tmp, value)
    copyMem(ctx.numberEditBuf[0].addr, tmp[0].addr, ctx.numberEditBufLen)

  if ctx.numberEdit == id:
    result = true # editing is active
    let res = TextboxRaw(ctx, id, ctx.numberEditBuf, ctx.numberEditBufLen, r, {})
    if res.contains(muResSubmit) and ctx.focus != id:
      var tmpFloat: BiggestFloat
      when NimMajor >= 2:
        let nparsed = parseBiggestFloat(toOpenArray(ctx.numberEditBuf, 0, ctx.numberEditBufLen - 1), tmpFloat)
      else:
        # No openArray parseFloat available -- create a temporary string
        var tmpStr = ""
        if ctx.numberEditBufLen > 0:
          tmpStr = newString(ctx.numberEditBufLen)
          copyMem(tmpStr[0].addr, ctx.numberEditBuf[0].addr, ctx.numberEditBufLen)
        let nparsed = parseBiggestFloat(tmpStr, tmpFloat)
      if nparsed != ctx.numberEditBufLen:
        tmpFloat = 0
      value = tmpFloat
      ctx.numberEdit = MuId(0)
      result = false # editing not active any more

func Textbox*(ctx: var MuContext; id: MuId; buf: var openArray[char]; bufLen: var int; opts: set[MuOpt] = {}): set[MuRes] {.discardable, raises: [].} =
  let r = ctx.layoutNext()
  result = TextboxRaw(ctx, id, buf, bufLen, r, opts)

func Textbox*(ctx: var MuContext; id: MuId; str: var string; opts: set[MuOpt] = {}): set[MuRes] {.discardable, raises: [].} =
  let r = ctx.layoutNext()
  let oldBufLen = str.len
  var bufLen = oldBufLen
  let expand = ctx.inputTextLen > 0
  if expand:
    str.setLen(bufLen + ctx.inputTextLen.int)
  result = TextboxRaw(ctx, id, str, bufLen, r, opts)
  if expand or (bufLen != oldBufLen):
    str.setLen(bufLen)

func Slider*(ctx: var MuContext; id: MuId; value: var MuReal; lo, hi, step: MuReal; opts: set[MuOpt] = {}): bool {.discardable, raises: [].} =
  let last = value
  let base = ctx.layoutNext()

  # handle text input mode
  if numberTextbox(ctx, value, base, id):
    return # text input is active

  # handle normal mode
  var v = value
  ctx.updateControl(id, base, opts)

  # handle input
  if ctx.focus == id and (ctx.mouseDown + ctx.mousePressed) == {muMouseLeft}:
    v = lo + MuReal(ctx.mousePos.x - base.x) * (hi - lo) / base.w.MuReal
    if step != 0:
      v = ((v + step / MuReal(2)) / step) * step

  # clamp and store value, update res
  v = clamp(v, lo, hi)
  value = v
  result = v != last

  # draw base
  ctx.drawControlFrame(id, base, muColorBase, opts)

  # draw thumb
  let
    w = ctx.style.thumb_size
    x = int32 (v - lo) * MuReal(base.w - w) / (hi - lo)
    thumb = muRect(base.x + x, base.y, int32 w, base.h)
  ctx.drawControlFrame(id, thumb, muColorButton, opts)

  # draw text
  var tmp {.noinit.}: array[65, char]
  let textLen = writeFloatToBuffer(tmp, v)
  ctx.drawControlText(toOpenArray(tmp, 0, textLen - 1), base, muColorText, opts)

proc Number*(ctx: var MuContext; id: MuId; value: var MuReal; step: MuReal; opts: set[MuOpt] = {}): bool {.discardable, raises: [].} =
  let base = ctx.layoutNext()
  let last = value

  # handle text input mode
  if numberTextbox(ctx, value, base, id):
    return # text input is active

  # handle normal mode
  ctx.updateControl(id, base, opts)

  # handle input
  if ctx.focus == id and ctx.mouseDown == {muMouseLeft}:
    value = value + MuReal(ctx.mouseDelta.x) * step

  # set flag if value changed
  result = value != last

  # draw base
  ctx.drawControlFrame(id, base, muColorBase, opts)

  # draw text
  var tmp {.noinit.}: array[65, char]
  let textLen = writeFloatToBuffer(tmp, value)
  ctx.drawControlText(toOpenArray(tmp, 0, textLen - 1), base, muColorText, opts)

func headerAux(ctx: var MuContext; id: MuId; label: openArray[char]; isTreeNode: bool; opts: set[MuOpt]): bool {.raises: [].} =
  var idx = poolGet(ctx.treenodePool, id)
  ctx.layoutRow([-1'i32], 0)

  var
    active = idx >= 0
    r = ctx.layoutNext()
  ctx.updateControl(id, r, {})

  result = if opts.contains(muOptExpanded): (not active) else: active

  # handle click
  active = active xor (ctx.mousePressed == {muMouseLeft} and ctx.focus == id)

  # update pool ref
  if idx >= 0:
    if active:
      poolUpdate(ctx.treenodePool, idx, ctx.frame)
    else:
      reset ctx.treenodePool[idx]
  elif active:
    idx = poolAlloc(ctx.treenodePool, id, ctx.frame)

  # draw
  if isTreeNode:
    if ctx.hover == id:
      ctx.drawFrame(ctx, r, muColorButtonHover)
  else:
    ctx.drawControlFrame(id, r, muColorButton, {})
  ctx.drawIcon(if result: muIconExpanded else: muIconCollapsed, muRect(r.x, r.y, r.h, r.h), ctx.style.colors[muColorText])

  r.x = r.x + (r.h - ctx.style.padding)
  r.w = r.w - (r.h - ctx.style.padding)
  ctx.drawControlText(label, r, muColorText, {})

func Header*(ctx: var MuContext; id: MuId; label: openArray[char]; opts: set[MuOpt] = {}): bool {.raises: [].} =
  result = headerAux(ctx, id, label, false, opts)

func Header*(ctx: var MuContext; label: openArray[char]; opts: set[MuOpt] = {}): bool {.raises: [].} =
  result = Header(ctx, ctx.getId(label), label, opts)

func beginTreeNode*(ctx: var MuContext; id: MuId; label: openArray[char]; opts: set[MuOpt] = {}): bool {.raises: [].} =
  result = headerAux(ctx, id, label, true, opts)
  if result:
    ctx.topLayout.indent.inc ctx.style.indent
    ctx.idStack.push id

func beginTreeNode*(ctx: var MuContext; label: openArray[char]; opts: set[MuOpt] = {}): bool {.raises: [].} =
  result = beginTreeNode(ctx, ctx.getId(label), label, opts)

func endTreeNode*(ctx: var MuContext) {.raises: [].} =
  ctx.topLayout.indent.dec ctx.style.indent
  ctx.idStack.pop()

# Containers

func bringToFront(ctx: var MuContext; containerIdx: MuContainerIdx) {.inline, raises: [].} =
  inc(ctx.lastZindex)
  ctx.cnt[containerIdx].zindex = ctx.lastZindex

proc bringToFront*(r: MuContainerRef) {.inline, raises: [].} =
  bringToFront(r.ctx[], r.idx)

func `[]`*(r: MuContainerRef): var MuContainer {.inline, raises: [].} =
  result = r.ctx[].cnt[r.idx]

func getOrAllocContainerIfOpen(ctx: var MuContext; id: MuId; closed: bool): MuContainerIdx {.raises: [].} =
  ## can return -1
  # try to get existing container from pool
  var idx = poolGet(ctx.containerPool, id)
  if idx >= 0:
    if ctx.cnt[idx].open or (not closed):
      poolUpdate(ctx.containerPool, idx, ctx.frame) # I'm alive!
    return cast[MuContainerIdx](idx)

  if closed:
    return -1

  # container not found in pool: init new container
  idx = poolAlloc(ctx.containerPool, id, ctx.frame)
  ctx.cnt[idx] = MuContainer(head: -1, open: true)
  result = cast[MuContainerIdx](idx)
  ctx.bringToFront(result)

func doScrollbars(ctx: var MuContext; containerIdx: MuContainerIdx; cnt: var MuContainer; body: MuRect): MuRect {.inline, raises: [].} =
  ## Returns new body (with space removed for scrollbars)
  var body = body

  let scrollbarSize = ctx.style.scrollbarSize
  let cs = cnt.contentSize + muVec2(ctx.style.padding * 2, ctx.style.padding * 2)
  ctx.pushClipRect(body)
  let
    needVertScrollbar = cs.y > cnt.body.h and cnt.body.h > 0 # need V scrollbar at right
    needHorzScrollbar = cs.x > cnt.body.w and cnt.body.w > 0 # need H scrollbar at bottom
  if needVertScrollbar:
    body.w.dec scrollbarSize
  else:
    cnt.scroll.y = 0
  if needHorzScrollbar:
    body.h.dec scrollbarSize
  else:
    cnt.scroll.x = 0

  # to create a horizontal or vertical scrollbar almost-identical code is used;
  # only the references to `x|y` `w|h` need to be switched.
  template scrollbarLogic(identName, x, y, w, h) {.dirty.} =
    let maxscroll = cs.y - body.h
    if maxscroll > 0 and body.h > 0:
      let id = ctx.getId(identName)
      # get sizing / positioning
      var base = body
      base.x = body.x + body.w
      base.w = ctx.style.scrollbarSize

      # handle input
      ctx.updateControl(id, base, {})
      if ctx.focus == id and ctx.mouseDown == {muMouseLeft}:
        cnt.scroll.y.inc (ctx.mouseDelta.y * cs.y) div base.h

      # clamp scroll to limits
      cnt.scroll.y = clamp(cnt.scroll.y, 0, maxscroll)

      # draw base and thumb
      ctx.drawFrame(ctx, base, muColorScrollBase)

      var thumb = base
      thumb.h = max(ctx.style.thumbSize, (base.h * body.h) div cs.y)
      thumb.y.inc cnt.scroll.y * (base.h - thumb.h) div maxscroll
      ctx.drawFrame(ctx, thumb, muColorScrollThumb)

      # set this as scrollTarget (will get scrolled on mousewheel) if the mouse is over it
      if ctx.mouseOver(body):
        ctx.scrollTarget = containerIdx
    else:
      cnt.scroll.y = 0

  if needVertScrollbar:
    scrollbarLogic("!scrollbarv", x, y, w, h)
  if needHorzScrollbar:
    scrollbarLogic("!scrollbarh", y, x, h, w)

  ctx.popClipRect()
  result = body

func pushContainerBody(ctx: var MuContext; containerIdx: MuContainerIdx; body: MuRect; noScroll: bool) {.inline, raises: [].} =
  let body = if noScroll: body else: doScrollbars(ctx, containerIdx, ctx.cnt[containerIdx], body)
  ctx.pushLayout(body.expand(-ctx.style.padding), ctx.cnt[containerIdx].scroll)
  ctx.cnt[containerIdx].body = body

func popContainer(ctx: var MuContext) {.raises: [].} =
  assert ctx.containerStack.idx > 0
  let containerIdx = ctx.containerStack.its[ctx.containerStack.idx - 1]
  let newContentSize = ctx.topLayout.max - ctx.topLayout.body.topLeft
  ctx.cnt[containerIdx].contentSize = newContentSize

  # pop container, layout and id
  ctx.containerStack.pop()
  ctx.layoutStack.pop()
  ctx.popId()

func beginRootContainer(ctx: var MuContext; containerIdx: MuContainerIdx) {.raises: [].} =
  let cnt = ctx.cnt[containerIdx]
  ctx.containerStack.push containerIdx

  # push container to roots list
  ctx.rootList.push containerIdx

  # push head command
  ctx.cnt[containerIdx].head = cast[int32](ctx.cmds.idx)
  ctx.cmds.addCommand(muCommandJump, MuJumpCommand(dst: -1))

  # set as next-frame hover root if mouse is overlapping this container and it has a higher zindex than the current hover root
  if cnt.rect.intersects(ctx.mousePos) and (ctx.nextHoverRoot < 0 or cnt.zindex > ctx.cnt[ctx.nextHoverRoot].zindex):
    ctx.nextHoverRoot = containerIdx

  # clipping is reset here in case a root-container is made within another root container's begin/end block;
  # this prevents the inner root-container being clipped to the outer.
  ctx.clipStack.push UnclippedRect

func endRootContainer(ctx: var MuContext) {.raises: [].} =
  assert ctx.containerStack.idx > 0
  let containerIdx = ctx.containerStack.its[ctx.containerStack.idx - 1]

  # push tail 'goto' jump command and set head 'skip' command.
  # the final steps on initing these are done in muEnd()
  ctx.cnt[containerIdx].tail = cast[int32](ctx.cmds.idx)
  ctx.cmds.addCommand(muCommandJump, MuJumpCommand(dst: -1))

  ctx.cmds.backpatchJump(ctx.cnt[containerIdx].head, cast[int32](ctx.cmds.idx))
  const JumpCommandSize = (sizeof(MuCommandHeader) + sizeof(MuJumpCommand) + 7) shr 3
  ctx.cnt[containerIdx].head.inc(JumpCommandSize)

  # pop base clip rect and container
  ctx.popClipRect()
  ctx.popContainer()

func beginWindow*(ctx: var MuContext; id: MuId; title: openArray[char]; rect: MuRect; opts: set[MuOpt] = {}): bool {.raises: [].} =
  let cntIdx = ctx.getOrAllocContainerIfOpen(id, muOptClosed in opts)
  if cntIdx < 0 or (not ctx.cnt[cntIdx].open):
    return false

  ctx.idStack.push(id)

  if ctx.cnt[cntIdx].rect.w == 0:
    ctx.cnt[cntIdx].rect = rect

  ctx.beginRootContainer(cntIdx)

  var
    rect = ctx.cnt[cntIdx].rect
    body = rect

  # draw frame
  if muOptNoFrame notin opts:
    ctx.drawFrame(ctx, rect, muColorWindowBg)

  # do title bar
  if muOptNoTitle notin opts:
    var tr = rect
    tr.h = ctx.style.titleHeight
    ctx.drawFrame(ctx, tr, muColorTitleBg)

    # do title text
    if muOptNoTitle notin opts:
      let id = ctx.getId("!title")
      var trt = tr
      if muOptNoClose notin opts:
        # make space for the close button
        trt.w = trt.w - trt.h
      ctx.updateControl(id, trt, opts)
      ctx.drawControlText(title, trt, muColorTitleText, opts)
      if ctx.focus == id and ctx.mouseDown == {muMouseLeft}:
        ctx.cnt[cntIdx].rect.x.inc ctx.mouseDelta.x
        ctx.cnt[cntIdx].rect.y.inc ctx.mouseDelta.y
      body.y.inc trt.h
      body.h.dec trt.h

    # do close button
    if muOptNoClose notin opts:
      let id = ctx.getId("!close")
      let r = muRect(tr.x + tr.w - tr.h, tr.y, tr.h, tr.h)
      tr.w.dec r.w
      ctx.drawIcon(muIconClose, r, ctx.style.colors[muColorTitleText])
      ctx.updateControl(id, r, opts)
      if ctx.focus == id and ctx.mousePressed == {muMouseLeft}:
        ctx.cnt[cntIdx].open = false

  ctx.pushContainerBody(cntIdx, body, muOptNoScroll in opts)

  # do `resize` handle
  if muOptNoResize notin opts:
    let sz = ctx.style.titleHeight
    let id = ctx.getId("!resize")
    let r = muRect(rect.x + rect.w - sz, rect.y + rect.h - sz, sz, sz)
    ctx.updateControl(id, r, opts)
    if ctx.focus == id and ctx.mouseDown == {muMouseLeft}:
      let cnt = ctx.cnt[cntIdx]
      ctx.cnt[cntIdx].rect.w = max(96'i32, cnt.rect.w + ctx.mouseDelta.x)
      ctx.cnt[cntIdx].rect.h = max(64'i32, cnt.rect.h + ctx.mouseDelta.y)

  # resize to content size
  if muOptAutoSize in opts:
    let r = ctx.topLayout.body
    let cnt = ctx.cnt[cntIdx]
    ctx.cnt[cntIdx].rect.w = cnt.contentSize.x + (cnt.rect.w - r.w)
    ctx.cnt[cntIdx].rect.h = cnt.contentSize.y + (cnt.rect.h - r.h)

  # close if this is a popup window and elsewhere was clicked
  if (muOptPopup in opts) and ctx.mousePressed != {} and ctx.hoverRoot != cntIdx:
    ctx.cnt[cntIdx].open = false

  ctx.pushClipRect(ctx.cnt[cntIdx].body)
  result = true

func beginWindow*(ctx: var MuContext; title: openArray[char]; rect: MuRect; opts: set[MuOpt] = {}): bool {.raises: [].} =
  result = beginWindow(ctx, ctx.getId(title), title, rect, opts)

func endWindow*(ctx: var MuContext) {.raises: [].} =
  ctx.popClipRect()
  ctx.endRootContainer()

func openPopup*(ctx: var MuContext; id: MuId) {.raises: [].} =
  let cntIdx = ctx.getOrAllocContainerIfOpen(id, closed = false)
  # set as hover root so popup isn't closed in beginWindow()
  ctx.hoverRoot = cntIdx
  ctx.nextHoverRoot = cntIdx
  # position at mouse cursor, open and bring-to-front
  ctx.cnt[cntIdx].rect = muRect(ctx.mousePos.x, ctx.mousePos.y, 1, 1)
  ctx.cnt[cntIdx].open = true

func beginPopup*(ctx: var MuContext; id: MuId): bool {.raises: [].} =
  result = beginWindow(ctx, id, "", MuRect(), {muOptPopup, muOptAutoSize, muOptNoResize, muOptNoScroll, muOptNoTitle, muOptClosed})

func endPopup*(ctx: var MuContext) {.raises: [].} =
  ctx.endWindow()

func beginPanel*(ctx: var MuContext; id: MuId; opts: set[MuOpt] = {}) {.raises: [].} =
  ctx.pushId(id)
  let cntIdx = ctx.getOrAllocContainerIfOpen(id, closed = false)
  let r = ctx.layoutNext()
  ctx.cnt[cntIdx].rect = r
  if muOptNoFrame notin opts:
    ctx.drawFrame(ctx, r, muColorPanelBg)
  ctx.containerStack.push cntIdx
  ctx.pushContainerBody(cntIdx, r, muOptNoScroll in opts)
  ctx.pushClipRect(r)

func endPanel*(ctx: var MuContext) {.raises: [].} =
  ctx.popClipRect()
  ctx.popContainer()

func muInit*(ctx: var MuContext) {.raises: [].} =
  ctx.drawFrame = defaultDrawFrame
  ctx.style = MuDefaultStyle
  ctx.hoverRoot = -1
  ctx.nextHoverRoot = -1
  ctx.scrollTarget = -1

func muBegin*(ctx: var MuContext) {.raises: [].} =
  assert((not ctx.textWidth.isNil) and (not ctx.textHeight.isNil))
  ctx.cmds.idx = 0
  ctx.scrollTarget = -1

  # find hover root
  ctx.hoverRoot = -1
  for i in countdown(ctx.rootList.idx - 1, 0):
    let cntIdx = ctx.rootList.its[i]
    if ctx.cnt[cntIdx].rect.intersects(ctx.mousePos):
      ctx.hoverRoot = cntIdx
      break
  ctx.rootList.idx = 0

  ctx.nextHoverRoot = -1
  ctx.wantTextInput = false
  ctx.mouseDelta = ctx.mousePos - ctx.lastMousePos
  inc ctx.frame

func muEnd*(ctx: var MuContext) {.raises: [].} =
  # check stacks
  assert(ctx.containerStack.idx == 0)
  assert(ctx.clipStack.idx == 0)
  assert(ctx.idStack.idx == 0)
  assert(ctx.layoutStack.idx == 0)

  # handle scroll input
  if ctx.scrollTarget >= 0 and (ctx.scrollDelta.x != 0 or ctx.scrollDelta.y != 0):
    ctx.cnt[ctx.scrollTarget].scroll += ctx.scrollDelta

  # unset focus if focus id was not touched in this frame
  if (not ctx.updatedFocus) and ctx.focus != MuId(0):
    ctx.focus = MuId(0)
  ctx.updatedFocus = false

  # bring hover root to front if mouse was pressed
  if ctx.mousePressed != {} and ctx.nextHoverRoot >= 0 and ctx.cnt[ctx.nextHoverRoot].zindex >= 0 and ctx.cnt[ctx.nextHoverRoot].zindex < ctx.lastZindex:
    ctx.bringToFront(ctx.nextHoverRoot)

  # reset input state
  ctx.keyPressed = {}
  ctx.inputTextLen = 0
  ctx.mousePressed = {}
  ctx.scrollDelta = muVec2(0, 0)
  ctx.lastMousePos = ctx.mousePos

  # sort root containers by zindex using insertion sort
  for i in 1 ..< ctx.rootList.idx:
    let
      containerIdx = ctx.rootList.its[i]
      zindex = ctx.cnt[containerIdx].zindex
    var j = i
    while j > 0 and ctx.cnt[ctx.rootList.its[j - 1]].zindex > zindex:
      ctx.rootList.its[j] = ctx.rootList.its[j - 1]
      dec j
    ctx.rootList.its[j] = containerIdx

  # re-number container zindexes so that zindexes do not increase without bound
  ctx.lastZindex = 0
  for i in 0 ..< ctx.rootList.idx:
    ctx.cnt[ctx.rootList.its[i]].zindex = ctx.lastZindex
    inc ctx.lastZindex

  # set root container jump commands
  if ctx.rootList.idx > 0:
    # Make the first command jump to the first container
    let firstCntIdx = ctx.rootList.its[0]
    ctx.cmds.backpatchJump(0, ctx.cnt[firstCntIdx].head)

    # Make the last container jump to the end of the command list
    let lastCntIdx = ctx.rootList.its[ctx.rootList.idx - 1]
    ctx.cmds.backpatchJump(ctx.cnt[lastCntIdx].tail, ctx.cmds.idx)

  # For each container `i`, make its tail jump to the next container
  for i in 0'i32 ..< ctx.rootList.idx - 1:
    let
      thisCntIdx = ctx.rootList.its[i]
      nextCntIdx = ctx.rootList.its[i+1]
    ctx.cmds.backpatchJump(ctx.cnt[thisCntIdx].tail, ctx.cnt[nextCntIdx].head)
