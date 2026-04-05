# surfer
Surfer is a high-level, opinionated windowing library written in Nim.

It has one simple goal: **Do one thing (windowing), and do it better than any other Nim windowing library.**

It does not try to be your networking stack, your rendering stack or anything else. It handles windowing, input and buffer management. That's it.

Currently, it only supports a Wayland backend through the `nayland` library. On its Wayland backend, Surfer can be used to write desktop shells, launchers, status bars, notification daemons and other layer-based programs using the `zwlr-layer-shell-unstable-v1` protocol.

# installation
Surfer can be installed via [Neo](https://github.com/xTrayambak/neo), as well as Nimble.
```bash
$ neo add gh:nim-windowing/surfer
```

# basic example
```nim
import pkg/[vmath, shakar, surfer, chroma, pixie]

proc main() {.inline.} =
  let app = newApp("Surfer Example", appId = "xyz.xtrayambak.surfer")
  app.initialize()
  app.createWindow(ivec2(680, 480), Renderer.Software)

  echo "Has keyboard: " & $hasKeyboard(app)
  echo "Has cursor: " & $hasCursor(app)

  # Use ControlFlow.Wait for simple GUI apps that don't need
  # precise timing, and use ControlFlow.Async for high-performance
  # apps like game engines that need precise timing, at the cost
  # of increased CPU usage.
  app.controlFlow = ControlFlow.Wait

  # Create a Pixie image
  let image = newImage(680, 480)
  for i in 0 ..< image.data.len:
    image.data[i] = rgbx(255, 255, 255, 255) # Make the image fully white

  var font = readFont("IBMPlexSans-Regular.ttf") # Replace this with a font path
  font.size = 20
  
  # Just add some text for fun :^)
  image.fillText(font.typeset("Hello, surfer!", vec2(180, 180)), translate(vec2(10, 10)))

  while not app.closureRequested:
    let eventOpt = app.flushQueue()
    if !eventOpt:
      # If we have no event to consume, continue.
      continue

    let event = &eventOpt
    case event.kind
    of EventKind.RedrawRequested:
      # Redrawing logic
      let stride = image.width * sizeof(ColorRGBX)
      
      # Wayland specific logic: Copy pixie image buffer to the mapped buffer
      # that surfer allocated.
      for y in 0 ..< image.height:
        copyMem(
          cast[pointer](cast[uint](app.pools.surfaceDest) + uint(y * stride)),
          addr image.data[y * image.width],
          stride,
        )
    
      app.markDamaged()

      # Tell the compositor that we're ready to draw another frame, if it wishes so.
      app.queueRedraw()
    of EventKind.KeyboardFocusObtained:
      echo "Keyboard focus on surface"
    of EventKind.KeyboardFocusLost:
      echo "Keyboard focus lost"
    of EventKind.KeyReleased:
      echo "Key released: " & $event.key.code
    of EventKind.KeyPressed:
      echo "Key pressed: " & $event.key.code
    of EventKind.KeyRepeated:
      echo "Key repeated: " & $event.key.code
    else:
      discard

when isMainModule: main()
```

# roadmap
The items here are non-sequential.
- [X] Software rendering support
- [X] Keyboard input support (repeating is handled internally by Surfer, while respecting the compositor's repeat hints)
- [X] Automatic libxkbcommon initialization
- [ ] Pointer input support
- [X] OpenGL ES rendering support
- [X] Layer shell support
- [X] Idle inhibit support
- [X] System bell support
- [ ] Presentation time support
- [ ] Tablet support
- [X] Fractional scale support

# distant roadmap
- [ ] win32 backend
- [ ] Cocoa backend

# non-goals
- **X11 support**: It's an old protocol, the reference server (Xorg) is unmaintained, and Wayland is the future, so there's no point in supporting it anymore.
