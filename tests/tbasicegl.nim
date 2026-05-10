## basic EGL drawing example with surfer
import std/[math]
#!fmt: off
import pkg/surfer/app,
       pkg/surfer/backend/wayland/bindings/[egl, gles2],
       pkg/[shakar, vmath]
#!fmt: on

proc main() {.inline.} =
  let app = newApp("OpenGL ES + EGL example", appId = "xyz.xtrayambak.surfer")
  app.initialize()
  app.createWindow(ivec2(640, 480), Renderer.GLES)

  var
    i = 0
    j = 1337
    k = 6767

  while not app.closureRequested:
    let eventOpt = app.flushQueue()
    if !eventOpt:
      continue

    let event = &eventOpt
    case event.kind
    of EventKind.RedrawRequested:
      glViewport(0, 0, app.windowSize.x, app.windowSize.y)
      glClearColor(
        math.sin(i.float32 / 256),
        math.sin(j.float32 / 256),
        math.sin(k.float32 / 256),
        255,
      )
      glClear(GL_DEPTH_BUFFER_BIT or GL_COLOR_BUFFER_BIT)

      app.queueRedraw()

      inc i
      inc j
      inc k
    else:
      discard

when isMainModule:
  main()
