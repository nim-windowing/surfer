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

  var font = readFont("tests/IBMPlexSans-Regular.ttf") # Replace this with a font path
  font.size = 20

  image.fillText(
    font.typeset("im feeling sleepy -o-", vec2(180, 180)), translate(vec2(10, 10))
  )

  app.setIdleInhibit(true)

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
      app.ringSystemBell()
      echo "Keyboard focus on surface"
    of EventKind.KeyboardFocusLost:
      app.ringSystemBell()
      echo "Keyboard focus lost"
    of EventKind.KeyReleased:
      echo "Key released: " & $event.key.code
    of EventKind.KeyPressed:
      echo "Key pressed: " & $event.key.code
    of EventKind.KeyRepeated:
      echo "Key repeated: " & $event.key.code
    of EventKind.ClosureRequested:
      echo "Window needs to close"
    of EventKind.PreferredRenderScale:
      echo "Preferred rendering scale: " & $event.preferredScale
    else:
      discard

when isMainModule:
  main()
