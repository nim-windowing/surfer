## Everything to do with input sources and events on Wayland
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak@disroot.org)
import std/[importutils, monotimes, options, posix, times]
import
  pkg/nayland/types/protocols/core/[keyboard, surface, pointer],
  pkg/[linux_input, shakar, vmath, xkb]
import pkg/surfer/types

privateAccess(types.App)

proc initializeWaylandKeymap(app: App, format: uint32, fd: int32, size: uint32) =
  app.xkbContext = newXkbContext(XkbContextFlags.NoFlags)

  # Now, we need to map the fd into memory.
  # TODO: The docs say that MAP_PRIVATE must be used after v7,
  # and no major compositor seems to be using any version below v9,
  # so I think we're good. Otherwise, we'd have to use MAP_SHARED.
  let buffer = posix.mmap(nil, size.int, PROT_READ, MAP_PRIVATE, fd, 0)
  if buffer == cast[pointer](-1):
    # TODO: This deserves its own error object.
    raise newException(
      CannotAllocateBuffer,
      "Cannot mmap XKB keymap provided by compositor (size=" & $size & ", fd=" & $fd &
        "): " & $strerror(errno) & " (errno " & $errno & ')',
    )

  app.keymap = newFromBufferXkbKeymap(
    app.xkbContext,
    cast[cstring](buffer),
    size.csize_t,
    XkbKeymapFormat(format),
    XkbKeymapCompileFlags.NoFlags,
  )

  if app.keymap == nil:
    raise newException(OSError, "Failed to compile keymap provided by compositor!")

  app.xkbState = newXkbState(app.keymap)

proc initializeWaylandKeyboard(app: App) =
  app.keyboard.onKeymap = proc(
      keyboard: Keyboard, fmt: uint32, fd: int32, size: uint32
  ) =
    initializeWaylandKeymap(app, format = fmt, fd = fd, size = size)

  app.keyboard.onEnter = proc(
      keyboard: Keyboard, serial: uint32, surface: Surface, keys: seq[uint32]
  ) =
    app.focused = true
    app.queue &= Event(kind: EventKind.KeyboardFocusObtained)

  app.keyboard.onLeave = proc(keyboard: Keyboard, serial: uint32, surface: Surface) =
    app.focused = false
    app.queue &= Event(kind: EventKind.KeyboardFocusLost)

  app.keyboard.onKey = proc(
      keyboard: Keyboard, serial: uint32, time: uint32, key: uint32, state: uint32
  ) =
    case KeyState(state)
    of KeyState.Released:
      if *app.repeatedKey and &app.repeatedKey == key:
        app.repeatedKey = none(uint32)
        app.repeaterStartTime.reset()
        app.lastRepeatSignal = 0'i64

      app.queue &=
        Event(kind: EventKind.KeyReleased, key: KeyEvent(code: key, time: time))
    of KeyState.Pressed:
      app.repeatedKey = some(key)
      app.repeaterStartTime = getMonoTime()

      app.queue &=
        Event(kind: EventKind.KeyPressed, key: KeyEvent(code: key, time: time))
    of KeyState.Repeated:
      app.queue &=
        Event(kind: EventKind.KeyRepeated, key: KeyEvent(code: key, time: time))

  app.keyboard.onModifiers = proc(
      keyboard: Keyboard,
      serial: uint32,
      modsDepressed, modsLatched, modsLocked, group: uint32,
  ) =
    discard app.xkbState.updateMask(
      cast[XkbModMask](modsDepressed),
      cast[XkbModMask](modsLatched),
      cast[XkbModMask](modsLocked),
      0'u32,
      0'u32,
      group,
    )

  app.keyboard.onRepeatInfo = proc(keyboard: Keyboard, rate, delay: int32) =
    assert(rate > 0'i32)
    assert(delay > 0'i32)

    app.keyboardRepeatRate = rate
    app.keyboardRepeatDelay = delay

  app.keyboard.attachCallbacks()

proc initializeWaylandPointer(app: App) =
  app.wpointer.onEnter = proc(
      _: Pointer, serial: uint32, surface: Surface, sx, sy: float
  ) =
    app.queue &=
      Event(kind: EventKind.CursorFocusObtained, cursor: CursorEvent(pos: vec2(sx, sy)))

  app.wpointer.onMotion = proc(_: Pointer, time: uint32, sx, sy: float) =
    app.queue &=
      Event(
        kind: EventKind.CursorMove, cursor: CursorEvent(pos: vec2(sx, sy), time: time)
      )

  app.wpointer.onFrame = proc(_: Pointer) =
    discard
      # TODO: Ideally we should batch together every other callback's data into one place before this is called, but I don't really see a reason to right now since it works _mostly_ fine. That being said, we should probably do that eventually.

  app.wpointer.onLeave = proc(_: Pointer, serial: uint32, surface: Surface) =
    app.queue &= Event(kind: EventKind.CursorFocusLost)

  app.wpointer.onAxis = proc(_: Pointer, time, axis: uint32, value: float) =
    app.queue &= Event(kind: EventKind.CursorScroll, cursor: CursorEvent(scroll: value))

  app.wpointer.onAxisSource = proc(_: Pointer, source: uint32) =
    discard # echo "axis source " & $source

  app.wpointer.onAxisRelativeDirection = proc(_: Pointer, axis, direction: uint32) =
    discard # echo "axis relative dir axis=" & $axis & " dir=" & $direction

  app.wpointer.onAxisValue120 = proc(_: Pointer, axis: uint32, value120: int32) =
    discard # echo "axis value120 axis=" & $axis & " value120=" & $value120

  app.wpointer.onButton = proc(
      _: Pointer, serial: uint32, time: uint32, button: uint32, state: ButtonState
  ) =
    app.queue &=
      Event(
        kind: EventKind.CursorClick,
        cursor: CursorEvent(time: time, state: state, button: toButton(button)),
      )

  app.wpointer.attachCallbacks()

proc flushWaylandKeyboardEvents*(app: App) =
  if !app.repeatedKey:
    return

  let elapsed = inMilliseconds(getMonoTime() - app.repeaterStartTime)

  if elapsed < int64(app.keyboardRepeatDelay):
    return

  if elapsed >= app.lastRepeatSignal + int64(app.keyboardRepeatRate):
    app.queue &=
      Event(kind: EventKind.KeyRepeated, key: KeyEvent(code: &app.repeatedKey))
    app.lastRepeatSignal = elapsed

proc initializeWaylandInput*(app: App) =
  if hasKeyboard(app):
    initializeWaylandKeyboard(app)

  if hasCursor(app):
    initializeWaylandPointer(app)
