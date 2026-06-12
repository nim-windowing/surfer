import pkg/surfer/app, pkg/[shakar, vmath]
import common/triangle

proc main() {.inline.} =
  let app = newApp(title = "Vulkan Triangle")
  app.initialize()
  app.createWindow(ivec2(800, 600), Renderer.Vulkan)

  var initializedVk = false

  while not app.closureRequested:
    let eventOpt = app.flushQueue()
    if !eventOpt:
      continue

    let event = &eventOpt
    case event.kind
    of EventKind.WindowResized:
      echo "Resize " & $event.windowSize.x & 'x' & $event.windowSize.y
      if not initializedVk:
        init(app.vkSurface, app.vkInstance)
        initializedVk = true

      tick()
    of EventKind.RedrawRequested:
      tick()
    else:
      discard

when isMainModule:
  main()
