import ../src/microui

type
  MuDemo* = object
    checks*: array[3, bool]
    bg*: array[3, MuReal]
    logbuf*: string
    logbufUpdated*: bool
    logInputBuf*: string

func hexU8(value: uint8): string {.inline, raises: [].} =
  const
    HexLut: array[16, char] = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f']
  result = newString(2)
  result[0] = HexLut[(value shr 4) and 15]
  result[1] = HexLut[value and 15]

proc writeLog(self: var MuDemo; ctx: var MuContext; text: string) {.raises: [].} =
  if self.logbuf.len > 0:
    self.logbuf.add '\n'
  self.logbuf.add text
  self.logbufUpdated = true

proc logWindow(self: var MuDemo; ctx: var MuContext) {.raises: [].} =
  if ctx.beginWindow(ctx.lineId, "Log Window", muRect(350, 40, 300, 200)):
    # output text panel
    ctx.layoutRow([ -1'i32 ], -25)
    ctx.beginPanel(ctx.lineId)
    let panel = ctx.topContainer
    ctx.layoutRow([-1'i32], -1)
    ctx.Text(self.logbuf)
    ctx.endPanel()
    if self.logbufUpdated:
      panel[].scroll.y = panel[].contentSize.y
      self.logbufUpdated = false

    # input textbox + submit button
    ctx.layoutRow([ -70'i32, -1'i32 ], 0)
    var submitted = false
    let textboxId = ctx.lineId
    if ctx.Textbox(textboxId, self.logInputBuf).contains(muResSubmit):
      ctx.setFocus(textboxId)
      submitted = true
    submitted = ctx.Button(ctx.lineId, "Submit") or submitted
    if submitted:
      writeLog(self, ctx, self.logInputBuf)
      self.logInputBuf.setLen(0)
    ctx.endWindow()

proc testWindow(self: var MuDemo; ctx: var MuContext) {.raises: [].} =
  # do window
  if ctx.beginWindow(ctx.lineId, "Demo Window", muRect(40, 40, 300, 450)):
    let win = ctx.topContainer
    win[].rect.w = max(win[].rect.w, 240)
    win[].rect.h = max(win[].rect.h, 240)

    # window info
    if ctx.Header(ctx.lineId, "Window Info"):
      let win = ctx.topContainer
      ctx.layoutRow([ 54'i32, -1'i32 ], 0)
      ctx.Label("Position:"); ctx.Label($win[].rect.x & ", " & $win[].rect.y)
      ctx.Label("Size: "); ctx.Label($win[].rect.w & ", " & $win[].rect.h)

    # labels + buttons
    if ctx.Header(ctx.lineId, "Test Buttons", {muOptExpanded}):
      ctx.layoutRow([ 86'i32, -110'i32, -1'i32 ], 0)
      ctx.Label("Test buttons 1:")
      if ctx.Button(ctx.lineId, "Button 1"):
        self.writeLog(ctx, "Pressed button 1")
      if ctx.Button(ctx.lineId, "Button 2"):
        self.writeLog(ctx, "Pressed button 2")
      ctx.Label("Test buttons 2:")
      if ctx.Button(ctx.lineId, "Button 3"):
        self.writeLog(ctx, "Pressed button 3")
      let testPopup = ctx.lineId
      if ctx.Button(ctx.lineId, "Popup"):
        ctx.openPopup(testPopup)
      if ctx.beginPopup(testPopup):
        ctx.Button(ctx.lineId, "Hello")
        ctx.Button(ctx.lineId, "World")
        ctx.endPopup()

    # tree
    if ctx.Header(ctx.lineId, "Tree and Text", {muOptExpanded}):
      ctx.layoutRow([ 140'i32, -1'i32 ], 0)
      ctx.layoutBeginColumn()
      if ctx.beginTreeNode(ctx.lineId, "Test 1"):
        if ctx.beginTreeNode(ctx.lineId, "Test 1a"):
          ctx.Label("Hello")
          ctx.Label("world")
          ctx.endTreeNode()
        if ctx.beginTreeNode(ctx.lineId, "Test 1b"):
          if ctx.Button(ctx.lineId, "Button 1"):
            self.writeLog(ctx, "Pressed button 1")
          if ctx.Button(ctx.lineId, "Button 2"):
            self.writeLog(ctx, "Pressed button 2")
          ctx.endTreeNode()
        ctx.endTreeNode()
      if ctx.beginTreeNode(ctx.lineId, "Test 2"):
        ctx.layoutRow([ 54'i32, 54'i32 ], 0)
        if ctx.Button(ctx.lineId, "Button 3"):
          self.writeLog(ctx, "Pressed button 3")
        if ctx.Button(ctx.lineId, "Button 4"):
          self.writeLog(ctx, "Pressed button 4")
        if ctx.Button(ctx.lineId, "Button 5"):
          self.writeLog(ctx, "Pressed button 5")
        if ctx.Button(ctx.lineId, "Button 6"):
          self.writeLog(ctx, "Pressed button 6")
        ctx.endTreeNode()
      if ctx.beginTreeNode(ctx.lineId, "Test 3"):
        ctx.Checkbox(ctx.lineId, "Checkbox 1", self.checks[0])
        ctx.Checkbox(ctx.lineId, "Checkbox 2", self.checks[1])
        ctx.Checkbox(ctx.lineId, "Checkbox 3", self.checks[2])
        ctx.endTreeNode()
      ctx.layoutEndColumn()

      ctx.layoutBeginColumn()
      ctx.layoutRow([ -1'i32 ], 0)
      ctx.Text("Lorem ipsum dolor sit amet, consectetur adipiscing " & "elit. Maecenas lacinia, sem eu lacinia molestie, mi risus faucibus " & "ipsum, eu varius magna felis a nulla.")
      ctx.layoutEndColumn()
    # end tree

    # background color slides
    if ctx.Header(ctx.lineId, "Background Color", {muOptExpanded}):
      ctx.layoutRow([ -78'i32, -1'i32 ], 74)
      # slides
      ctx.layoutBeginColumn()
      ctx.layoutRow([ 46'i32, -1'i32 ], 0)
      ctx.Label("Red:"); ctx.Slider(ctx.lineId, self.bg[0], 0, 255, 0)
      ctx.Label("Green:"); ctx.Slider(ctx.lineId, self.bg[1], 0, 255, 0)
      ctx.Label("Blue:"); ctx.Slider(ctx.lineId, self.bg[2], 0, 255, 0)
      ctx.layoutEndColumn()
      # color preview
      let r = ctx.layoutNext()
      let
        color_r = uint8 self.bg[0]
        color_g = uint8 self.bg[1]
        color_b = uint8 self.bg[2]
      ctx.drawRect(r, muColor(uint8 self.bg[0], uint8 self.bg[1], uint8 self.bg[2], 255))
      ctx.drawControlText("#" & hexU8(color_r) & hexU8(color_g) & hexU8(color_b), r, muColorText, {muOptAlignCenter})

    ctx.endWindow()

proc Uint8Slider(ctx: var MuContext; id: MuId; value: var uint8; lo, hi: uint8): bool {.discardable, raises: [].} =
  var tmp = value.MuReal
  result = Slider(ctx, id, tmp, MuReal(lo), MuReal(hi), 0, {muOptAlignCenter})
  value = uint8 tmp

proc styleWindow(self: var MuDemo; ctx: var MuContext) {.raises: [].} =
  const Labels: array[MuStyleColor, string] = [
    muColorText: "text:",
    muColorBorder: "border:",
    muColorWindowBg: "windowbg:",
    muColorTitleBg: "titlebg:",
    muColorTitleText: "titletext:",
    muColorPanelBg: "panelbg:",
    muColorButton: "button:",
    muColorButtonHover: "buttonhover:",
    muColorButtonFocus: "buttonfocus:",
    muColorBase: "base:",
    muColorBaseHover: "basehover:",
    muColorBaseFocus: "basefocus:",
    muColorScrollBase: "scrollbase:",
    muColorScrollThumb: "scrollthumb:"
  ]
  if ctx.beginWindow(ctx.lineId, "Style Editor", muRect(350, 250, 300, 240)):
    let sw = int32 ctx.topContainer[].body.w.float32 * 0.14'f32
    ctx.layoutRow([ 80'i32, sw, sw, sw, sw, -1'i32 ], 0)
    for color in MuStyleColor:
      ctx.pushId(ctx.getIdFromInt(color.int))
      ctx.Label(Labels[color])
      ctx.Uint8Slider(ctx.lineId, ctx.style.colors[color].r, 0, 255)
      ctx.Uint8Slider(ctx.lineId, ctx.style.colors[color].g, 0, 255)
      ctx.Uint8Slider(ctx.lineId, ctx.style.colors[color].b, 0, 255)
      ctx.Uint8Slider(ctx.lineId, ctx.style.colors[color].a, 0, 255)
      let rr = ctx.layoutNext()
      ctx.drawRect(rr, ctx.style.colors[color])
      ctx.popId()
    ctx.endWindow()

proc muDemoInit*(self: var MuDemo) {.raises: [].} =
  self.bg[0] = 90
  self.bg[1] = 95
  self.bg[2] = 100

proc runMuDemo*(self: var MuDemo; ctx: var MuContext) {.raises: [].} =
  styleWindow(self, ctx)
  logWindow(self, ctx)
  testWindow(self, ctx)
