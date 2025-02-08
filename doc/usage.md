# Usage
_This document is an adaptation of the original microui documentation, modified for this Nim port._

* **[Overview](#overview)**
* **[Getting Started](#getting-started)**
* **[IDs](#ids)**
* **[Layout System](#layout-system)**
* **[Style Customisation](#style-customisation)**
* **[Custom Controls](#custom-controls)**

## Overview
The overall structure when using the library is as follows:
```
initialize `MuContext`

main loop:
  call `inputXXX()` functions
  call `muBegin()`
  process ui
  call `muEnd()`
  iterate commands using `iterFollowJumps()`
```

## Getting Started
Before use an `MuContext` should be initialized:
```nim
import microui

var ctx = MuContext()
muInit(ctx)
```

Following which the context's `textWidth` and `textHeight` callback functions
should be set:
```nim
ctx.textWidth = textWidth
ctx.textHeight = textHeight
```

In your main loop you should first pass user input to microui using the
`inputXXX()` functions. It is safe to call the input functions multiple times
if the same input event occurs in a single frame.

After handling the input the `muBegin()` function must be called before
processing your UI:
```nim
muBegin(ctx)
```

Before any controls can be used we must begin a window using `beginWindow()` or `beginPopup()`.
`beginWindow()` and `beginPopup()` return true if the window is open,
if this is not the case we should not process the window any further.
When we are finished processing the window's ui the `endWindow()` or `endPopup()` function should be called.
```nim
if ctx.beginWindow("My Window", muRect(10, 10, 300, 400)):
  # process ui here...
  ctx.endWindow()
```

It is safe to nest `beginWindow()` and `beginPopup()` calls,
this can be useful for things like context menus;
the windows will still render separate from one another like normal.

While inside a window block we can safely process controls.
Some controls that allow complex user interactions will return a `set[MuRes]`.
Other simpler controls, such as buttons, return a boolean:
```nim
if ctx.Button("My Button"):
  echo "'My Button' was pressed"
```

When we're finished processing the UI for this frame `muEnd()` should be called:
```nim
muEnd(ctx)
```

When we're ready to draw the UI `iterFollowJumps()` can be used to iterate
the resultant commands.
It is safe to iterate through the commands list any number of times:
```nim
for (commandType, commandNBytes, pointerToCommand) in ctx.cmds.iterFollowJumps:
  case commandType
  of muCommandRect:
    let cmd = cast[ptr MuRectCommand](pointerToCommand)
    renderRect(cmd.rect, cmd.color)

  of muCommandText, muCommandTextClipped:
    let cmd = cast[ptr MuTextCommand](pointerToCommand)
    let strLen = commandNBytes - sizeof(MuTextCommand)
    if commandType == muCommandTextClipped:
      renderTextClipped(toOpenArray(cmd.str.addr, 0, strLen - 1), cmd.font, cmd.pos, cmd.color, cmd.clipRect)
    else:
      renderText(toOpenArray(cmd.str.addr, 0, strLen - 1), cmd.font, cmd.pos, cmd.color)

  of muCommandIcon, muCommandIconClipped:
    let cmd = cast[ptr MuIconCommand](pointerToCommand)
    if commandType == muCommandIconClipped:
      renderIconClipped(cmd.id, cmd.rect, cmd.color, cmd.clipRect)
    else:
      renderIcon(cmd.id, cmd.rect, cmd.color)

  else: discard
```

See the [`demo`](../demo) directory for usage examples.

## IDs
microui requires unique IDs for controls to keep track of which are focused, hovered, etc.
These IDs typically can be implicitly generated from the name/label passed to the function:
```nim
if ctx.Button("My Button"): # ID is implicitly generated from the hash of "My Button"
  ...
```

However, several controls in a window or panel which use the same label will generate the same implicit ID,
sometimes leading to undesired behavior:
```nim
# Expanding/collapsing the first header will also expand/collapse the second header
if ctx.Header("Header"):
  ctx.Label("Header 1 expanded")
if ctx.Header("Header"):
  ctx.Label("Header 2 expanded")
```

One way of resolving this issue is by generating and passing the ID explicitly:
```nim
if ctx.Header(ctx.getId("Header 1"), "Header"):
  ctx.Label("Header 1 expanded")
if ctx.Header(ctx.getId("Header 2"), "Header"):
  ctx.Label("Header 2 expanded")
```

Alternatively, `pushId()` and `popId()` can be used to push additional data that will be mixed into generated IDs:
```nim
for i in 0 ..< 10:
  ctx.pushId(ctx.getIdFromInt(i))
  if ctx.Header("Header"):
    ctx.Label("Header " & $i & " expanded")
  ctx.popId()
```

## Layout System
The layout system is primarily based around *rows* -- Each row
can contain a number of *items* or *columns* each column can itself
contain a number of rows and so forth. A row is initialized using the
`layoutRow()` function, the user should specify an array containing the width of each item,
and the height of the row:
```nim
# initialize a row of 3 items: the first item with a width
# of 90 and the remaining two with the width of 100
ctx.layoutRow([90'i32, 100, 100], 0)
```
When a row is filled the next row is started, for example, in the above
code 6 buttons immediately after would result in two rows. The function
can be called again to begin a new row.

As well as absolute values, width and height can be specified as `0`
which will result in the Context's `style.size` value being used, or a
negative value which will size the item relative to the right/bottom edge,
thus if we wanted a row with a small button at the left, a textbox filling
most the row and a larger button at the right, we could do the following:
```nim
ctx.layoutRow([30'i32, -90, -1], 0)
ctx.Button("X")
ctx.Textbox(ctx.lineId, buf)
ctx.Button("Submit")
```

If an empty widths array is specified, controls will continue to be added to the row at the width last specified by `layoutWidth()` or `style.size.x` if this function has not been called:
```nim
ctx.layoutRow([], 0)
ctx.layoutWidth(-90)
ctx.Textbox(ctx.lineId, buf)
ctx.layoutWidth(-1)
ctx.Button("Submit")
```

A column can be started at any point on a row using the
`layoutBeginColumn()` function. Once begun, rows will act inside
the body of the column -- all negative size values will be relative to
the column's body as opposed to the body of the container. All new rows
will be contained within this column until the `layoutEndColumn()`
function is called.

Internally controls use the `layoutNext()` function to retrieve the
next screen-positioned-Rect and advance the layout system, you should use
this function when making custom controls or if you want to advance the
layout system without placing a control.

The `layoutSetNext()` function is provided to set the next layout
Rect explicitly. This will be returned by `layoutNext()` when it is
next called. By using the `relative` boolean you can choose to provide
a screen-space Rect or a Rect which will have the container's position
and scroll offset applied to it. You can peek the next Rect from the
layout system by using the `layoutNext()` function to retrieve it,
followed by `layoutSetNext()` to return it:
```nim
let rect = ctx.layoutNext()
ctx.layoutSetNext(rect, relative = false)
```

If you want to position controls arbitrarily inside a container the
`relative` argument of `layoutSetNext()` should be true:
```nim
# place a (40, 40) sized button at (300, 300) inside the container:
ctx.layoutSetNext(muRect(300, 300, 40, 40), relative = true)
ctx.Button("X")
```
A Rect set with `relative` true will also effect the `contentSize`
of the container, causing it to effect the scrollbars if it exceeds the
width or height of the container's body.


## Style Customisation
The library provides styling support via the `MuStyle` object and, if you
want greater control over the look, the `drawFrame()` callback function.

The `MuStyle` object contains spacing and sizing information, as well
as a `colors` array which maps `MuStyleColor` to `MuColor`. The library uses
the `style` field of the `MuContext` to resolve colors and spacing.
It is safe to modify the style at any point.

In addition to the style object the context stores a `drawFrame()`
callback function which is used whenever the *frame* of a control needs
to be drawn, by default this function draws a rectangle using the color
of the `MuSyleColor` argument, with a one-pixel border around it using the
`muColorBorder` color.

## Custom Controls
The library exposes the functions used by built-in controls to allow the
user to make custom controls. A control should take a `var MuContext` value
as its first argument and return a `set[MuRes]` value. Your control's
implementation should use `layoutNext()` to get its destination
Rect and advance the layout system.
`updateControl()` should be used to update the context's `hover`
and `focus` values based on the mouse input state.

The `muOptHoldFocus` opt value can be passed to `updateControl()`
if we want the control to retain focus when the mouse button is released
-- this behaviour is used by textboxes which we want to stay focused
to allow for text input.

A control that acts as a button which displays an integer and, when
clicked increments that integer, could be implemented as such:
```nim
proc Incrementer(ctx: var MuContext; id: MuId; value: var int32): set[MuRes] =
  let rect = ctx.layoutNext()
  updateControl(ctx, id, rect, {})

  # handle input
  if ctx.mousePressed == {muMouseLeft} and ctx.focus == id:
    inc value
    result.incl muResChange

  # draw
  ctx.drawControlFrame(id, rect, muColorButton, {})
  ctx.drawControlText($value, rect, muColorText, {muOptAlignCenter})
```
