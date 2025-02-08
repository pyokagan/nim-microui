import microui

{.stackTrace:off, boundChecks:off, overflowChecks:off, rangeChecks:off.}

proc currentSourceDir(): string {.compileTime.} =
  var s1 = currentSourcePath()
  let l = s1.len
  result = newString(l)
  var i = 0
  while i < l:
    let c = s1[i]
    result[i] = if c == '\\': '/' else: c
    inc(i)
  var slashIdx = -1
  i = result.high
  while i >= 0:
    if result[i] == '/':
      slashIdx = i
      break
    dec(i)
  if slashIdx >= 0:
    result = result[0 ..< slashIdx]

const
  MuDemoAtlasWidth* = 128
  MuDemoAtlasHeight* = 128

  CurrentSourceDir = currentSourceDir()
  CompressedAtlasPixelData = readFile(CurrentSourceDir & "/microui_demoatlas_image.bin.fastlz")

func fastlz1Decompress(ops: openArray[uint8]; dst: var openArray[uint8]): int {.raises: [].} =
  ## Decompress a FastLZ Level 1 block.
  ## WARNING: Assumes input is valid FastLZ level 1 block! Only use on trusted inputs!
  var
    opIdx = 0
    dstIdx = 0
  while opIdx < len(ops):
    let op0 = ops[opIdx]; inc opIdx
    if op0 <= 31: # literal run
      for i in 0 .. op0.int:
        dst[dstIdx] = ops[opIdx]
        inc opIdx
        inc dstIdx
    elif op0 >= 224: # long match
      let matchLen = int(ops[opIdx]) + 9; inc opIdx
      let op2 = ops[opIdx]; inc opIdx
      let refOffset = (((op0 and 31).uint32 shl 8) or op2.uint32) + 1
      var srcIdx = dstIdx - refOffset.int
      for i in 0 ..< matchLen:
        dst[dstIdx] = dst[srcIdx]
        inc srcIdx
        inc dstIdx
    else: # short match
      let op1 = ops[opIdx]; inc opIdx
      let
        matchLen = int(op0 shr 5) + 2
        refOffset = (((op0 and 31).uint32 shl 8) or op1.uint32) + 1
      var srcIdx = dstIdx - refOffset.int
      for i in 0 ..< matchLen:
        dst[dstIdx] = dst[srcIdx]
        inc srcIdx
        inc dstIdx
  result = dstIdx

proc muUnpackDemoAtlasPixels*(dst: var openArray[uint8]) {.raises: [].} =
  assert len(dst) == (MuDemoAtlasWidth * MuDemoAtlasHeight)
  let decompLen {.used.} = fastlz1Decompress(toOpenArrayByte(CompressedAtlasPixelData, 0, CompressedAtlasPixelData.high), dst)
  assert decompLen == (MuDemoAtlasWidth * MuDemoAtlasHeight)

proc muUnpackDemoAtlasPixelsRgba*(dst: var openArray[uint8]; premultiplied = true) {.raises: [].} =
  assert len(dst) == (MuDemoAtlasWidth * MuDemoAtlasHeight * 4)

  # Unpack to end of buffer
  const Len = MuDemoAtlasWidth * MuDemoAtlasHeight
  muUnpackDemoAtlasPixels(toOpenArray(dst, Len * 3, Len * 4 - 1))

  # Convert to RGBA
  var
    srcIdx = Len * 3
    dstIdx = 0
  if premultiplied:
    for i in 0 ..< Len:
      let gray = dst[srcIdx]; inc srcIdx
      dst[dstIdx] = gray; inc dstIdx
      dst[dstIdx] = gray; inc dstIdx
      dst[dstIdx] = gray; inc dstIdx
      dst[dstIdx] = gray; inc dstIdx
  else:
    for i in 0 ..< Len:
      let gray = dst[srcIdx]; inc srcIdx
      dst[dstIdx] = 255; inc dstIdx
      dst[dstIdx] = 255; inc dstIdx
      dst[dstIdx] = 255; inc dstIdx
      dst[dstIdx] = gray; inc dstIdx

const
  MuDemoAtlasWhite* = MuRect(x: 126, y: 69, w: 1, h: 1)
  MuDemoAtlasFontHeight* = 18
  MuDemoAtlasFont*: array['\x20'..'\x7f', MuRect] = [
    MuRect(x: 84, y: 68, w: 2, h: 17),
    MuRect(x: 39, y: 68, w: 3, h: 17),
    MuRect(x: 114, y: 51, w: 5, h: 17),
    MuRect(x: 34, y: 17, w: 7, h: 17),
    MuRect(x: 28, y: 34, w: 6, h: 17),
    MuRect(x: 58, y: 0, w: 9, h: 17),
    MuRect(x: 103, y: 0, w: 8, h: 17),
    MuRect(x: 86, y: 68, w: 2, h: 17),
    MuRect(x: 42, y: 68, w: 3, h: 17),
    MuRect(x: 45, y: 68, w: 3, h: 17),
    MuRect(x: 34, y: 34, w: 6, h: 17),
    MuRect(x: 40, y: 34, w: 6, h: 17),
    MuRect(x: 48, y: 68, w: 3, h: 17),
    MuRect(x: 51, y: 68, w: 3, h: 17),
    MuRect(x: 54, y: 68, w: 3, h: 17),
    MuRect(x: 124, y: 34, w: 4, h: 17),
    MuRect(x: 46, y: 34, w: 6, h: 17),
    MuRect(x: 52, y: 34, w: 6, h: 17),
    MuRect(x: 58, y: 34, w: 6, h: 17),
    MuRect(x: 64, y: 34, w: 6, h: 17),
    MuRect(x: 70, y: 34, w: 6, h: 17),
    MuRect(x: 76, y: 34, w: 6, h: 17),
    MuRect(x: 82, y: 34, w: 6, h: 17),
    MuRect(x: 88, y: 34, w: 6, h: 17),
    MuRect(x: 94, y: 34, w: 6, h: 17),
    MuRect(x: 100, y: 34, w: 6, h: 17),
    MuRect(x: 57, y: 68, w: 3, h: 17),
    MuRect(x: 60, y: 68, w: 3, h: 17),
    MuRect(x: 106, y: 34, w: 6, h: 17),
    MuRect(x: 112, y: 34, w: 6, h: 17),
    MuRect(x: 118, y: 34, w: 6, h: 17),
    MuRect(x: 119, y: 51, w: 5, h: 17),
    MuRect(x: 18, y: 0, w: 10, h: 17),
    MuRect(x: 41, y: 17, w: 7, h: 17),
    MuRect(x: 48, y: 17, w: 7, h: 17),
    MuRect(x: 55, y: 17, w: 7, h: 17),
    MuRect(x: 111, y: 0, w: 8, h: 17),
    MuRect(x: 0, y: 35, w: 6, h: 17),
    MuRect(x: 6, y: 35, w: 6, h: 17),
    MuRect(x: 119, y: 0, w: 8, h: 17),
    MuRect(x: 18, y: 17, w: 8, h: 17),
    MuRect(x: 63, y: 68, w: 3, h: 17),
    MuRect(x: 66, y: 68, w: 3, h: 17),
    MuRect(x: 62, y: 17, w: 7, h: 17),
    MuRect(x: 12, y: 51, w: 6, h: 17),
    MuRect(x: 28, y: 0, w: 10, h: 17),
    MuRect(x: 67, y: 0, w: 9, h: 17),
    MuRect(x: 76, y: 0, w: 9, h: 17),
    MuRect(x: 69, y: 17, w: 7, h: 17),
    MuRect(x: 85, y: 0, w: 9, h: 17),
    MuRect(x: 76, y: 17, w: 7, h: 17),
    MuRect(x: 18, y: 51, w: 6, h: 17),
    MuRect(x: 24, y: 51, w: 6, h: 17),
    MuRect(x: 26, y: 17, w: 8, h: 17),
    MuRect(x: 83, y: 17, w: 7, h: 17),
    MuRect(x: 38, y: 0, w: 10, h: 17),
    MuRect(x: 90, y: 17, w: 7, h: 17),
    MuRect(x: 30, y: 51, w: 6, h: 17),
    MuRect(x: 36, y: 51, w: 6, h: 17),
    MuRect(x: 69, y: 68, w: 3, h: 17),
    MuRect(x: 124, y: 51, w: 4, h: 17),
    MuRect(x: 72, y: 68, w: 3, h: 17),
    MuRect(x: 42, y: 51, w: 6, h: 17),
    MuRect(x: 15, y: 68, w: 4, h: 17),
    MuRect(x: 48, y: 51, w: 6, h: 17),
    MuRect(x: 54, y: 51, w: 6, h: 17),
    MuRect(x: 97, y: 17, w: 7, h: 17),
    MuRect(x: 0, y: 52, w: 5, h: 17),
    MuRect(x: 104, y: 17, w: 7, h: 17),
    MuRect(x: 60, y: 51, w: 6, h: 17),
    MuRect(x: 19, y: 68, w: 4, h: 17),
    MuRect(x: 66, y: 51, w: 6, h: 17),
    MuRect(x: 111, y: 17, w: 7, h: 17),
    MuRect(x: 75, y: 68, w: 3, h: 17),
    MuRect(x: 78, y: 68, w: 3, h: 17),
    MuRect(x: 72, y: 51, w: 6, h: 17),
    MuRect(x: 81, y: 68, w: 3, h: 17),
    MuRect(x: 48, y: 0, w: 10, h: 17),
    MuRect(x: 118, y: 17, w: 7, h: 17),
    MuRect(x: 0, y: 18, w: 7, h: 17),
    MuRect(x: 7, y: 18, w: 7, h: 17),
    MuRect(x: 14, y: 34, w: 7, h: 17),
    MuRect(x: 23, y: 68, w: 4, h: 17),
    MuRect(x: 5, y: 52, w: 5, h: 17),
    MuRect(x: 27, y: 68, w: 4, h: 17),
    MuRect(x: 21, y: 34, w: 7, h: 17),
    MuRect(x: 78, y: 51, w: 6, h: 17),
    MuRect(x: 94, y: 0, w: 9, h: 17),
    MuRect(x: 84, y: 51, w: 6, h: 17),
    MuRect(x: 90, y: 51, w: 6, h: 17),
    MuRect(x: 10, y: 68, w: 5, h: 17),
    MuRect(x: 31, y: 68, w: 4, h: 17),
    MuRect(x: 96, y: 51, w: 6, h: 17),
    MuRect(x: 35, y: 68, w: 4, h: 17),
    MuRect(x: 102, y: 51, w: 6, h: 17),
    MuRect(x: 108, y: 51, w: 6, h: 17),
  ]

func muDemoAtlasIcon*(icon: int32): MuRect {.inline, raises: [].} =
  case icon
  of muIconClose: result = MuRect(x: 88, y: 68, w: 16, h: 16)
  of muIconCheck: result = MuRect(x: 0, y: 0, w: 18, h: 18)
  of muIconExpanded: result = MuRect(x: 118, y: 68, w: 7, h: 5)
  of muIconCollapsed: result = MuRect(x: 113, y: 68, w: 5, h: 7)
  else: discard

func muDemoAtlasTextWidthCb*(ctx: var MuContext; font: MuFont; str: openArray[char]): int32 {.nimcall, gcsafe, raises: [].} =
  for c in str:
    if c >= low(MuDemoAtlasFont) and c <= high(MuDemoAtlasFont):
      result.inc MuDemoAtlasFont[c].w

func muDemoAtlasTextHeightCb*(ctx: var MuContext; font: MuFont): int32 {.nimcall, gcsafe, raises: [].} =
  result = MuDemoAtlasFontHeight

func clipRects(clipRect, srcRect, dstRect: MuRect): tuple[srcRect, dstRect: MuRect] {.noinit, inline, raises: [].} =
  var
    clipRect_x1 = clipRect.x + clipRect.w
    clipRect_y1 = clipRect.y + clipRect.h
    dstRect_x1 = dstRect.x + dstRect.w
    dstRect_y1 = dstRect.y + dstRect.h
  result.dstRect.x = dstRect.x + max(clipRect.x - dstRect.x, 0'i32)
  result.srcRect.x = srcRect.x + max(clipRect.x - dstRect.x, 0'i32)
  result.dstRect.y = dstRect.y + max(clipRect.y - dstRect.y, 0'i32)
  result.srcRect.y = srcRect.y + max(clipRect.y - dstRect.y, 0'i32)
  dstRect_x1 = dstRect_x1 - max(dstRect_x1 - clipRect_x1, 0'i32)
  dstRect_y1 = dstRect_y1 - max(dstRect_y1 - clipRect_y1, 0'i32)
  result.dstRect.w = max(dstRect_x1 - result.dstRect.x, 0'i32)
  result.dstRect.h = max(dstRect_y1 - result.dstRect.y, 0'i32)
  result.srcRect.w = result.dstRect.w
  result.srcRect.h = result.dstRect.h

func muDemoAtlasIconAsTexRect*(id: int32; rect: MuRect): tuple[srcRect, dstRect: MuRect] {.noinit, inline, raises: [].} =
  let src = muDemoAtlasIcon(id)
  result.srcRect = src
  result.dstRect.x = rect.x + (rect.w - src.w) shr 1
  result.dstRect.y = rect.y + (rect.h - src.h) shr 1
  result.dstRect.w = src.w
  result.dstRect.h = src.h

func muDemoAtlasIconAsTexRectClipped*(id: int32; rect, clipRect: MuRect): tuple[srcRect, dstRect: MuRect] {.noinit, inline, raises: [].} =
  result = muDemoAtlasIconAsTexRect(id, rect)
  result = clipRects(clipRect, result.srcRect, result.dstRect)

iterator muDemoAtlasTextAsTexRects*(s: ptr UncheckedArray[char]; sLen: int; pos: MuVec2): tuple[srcRect, dstRect: MuRect] =
  var
    i = 0
    x = pos.x
  while i < sLen:
    let c = s[i]
    if c >= low(MuDemoAtlasFont) and c <= high(MuDemoAtlasFont):
      let srcRect = MuDemoAtlasFont[c]
      yield (srcRect: srcRect, dstRect: MuRect(x: x, y: pos.y, w: srcRect.w, h: srcRect.h))
      inc(x, srcRect.w)
    inc i

iterator muDemoAtlasTextAsTexRectsClipped*(s: ptr UncheckedArray[char]; sLen: int; pos: MuVec2; clipRect: MuRect): tuple[srcRect, dstRect: MuRect] =
  var
    i = 0
    x = pos.x
  while i < sLen:
    let c = s[i]
    if c >= low(MuDemoAtlasFont) and c <= high(MuDemoAtlasFont):
      let origSrcRect = MuDemoAtlasFont[c]
      let (srcRect, dstRect) = clipRects(clipRect, origSrcRect, MuRect(x: x, y: pos.y, w: origSrcRect.w, h: origSrcRect.h))
      if dstRect.w > 0 and dstRect.h > 0:
        yield (srcRect: srcRect, dstRect: dstRect)
      inc(x, origSrcRect.w)
    inc i
