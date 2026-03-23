## App functions
##
## Copyright (C) 2025-2026 Trayambak Rai (xtrayambak@disroot.org)
import std/[importutils, options]
import pkg/surfer/[platform, types]
import pkg/vmath

when usingPlatform(Wayland):
  import backend/wayland/prelude

privateAccess(types.App)

proc initialize*(app: App) =
  # echo "App::initialize"
  when usingPlatform(Wayland):
    initializeWaylandBackend(app)

proc createWindow*(app: App, dimensions: vmath.IVec2, renderer: Renderer) =
  # echo "App::createWindow(" & $dimensions & ", Renderer." & $renderer & ')'
  app.windowSize = dimensions

  when usingPlatform(Wayland):
    createWaylandWindow(app, dimensions, renderer)

when usingPlatform(Wayland):
  export prelude.Anchor, prelude.Layer, prelude.KeyboardInteractivity

  {.push inline.}
  proc createLayerSurface*(
      app: App,
      layer: Layer,
      anchors: set[Anchor],
      keyboardInteractivity: KeyboardInteractivity,
      namespace: string,
      renderer: Renderer,
      requestedSize: IVec2 = ivec2(0, 0),
  ) {.inline.} =
    createWaylandLayerSurface(
      app, layer, anchors, keyboardInteractivity, namespace, renderer, requestedSize
    )

  proc createLayerSurface*(
      app: App,
      layer: Layer,
      anchors: set[Anchor],
      keyboardInteractivity: KeyboardInteractivity,
      renderer: Renderer,
  ) =
    createWaylandLayerSurface(
      app, layer, anchors, keyboardInteractivity, app.appId, renderer
    )

  proc createLayerSurface*(
      app: App,
      layer: Layer,
      anchor: Anchor,
      keyboardInteractivity: KeyboardInteractivity,
      renderer: Renderer,
  ) =
    createLayerSurface(app, layer, {anchor}, keyboardInteractivity, renderer)

  proc createLayerSurface*(
      app: App,
      layer: Layer,
      keyboardInteractivity: KeyboardInteractivity = KeyboardInteractivity.OnDemand,
      renderer: Renderer,
  ) =
    createLayerSurface(app, layer, {}, keyboardInteractivity, renderer)

  {.pop.}

proc flushQueue*(app: App): Option[Event] =
  # echo "App::flushQueue()"
  when usingPlatform(Wayland):
    flushWaylandKeyboardEvents(app)
    flushWaylandQueue(app)

proc queueRedraw*(app: App) =
  # echo "App::queueRedraw()"
  when usingPlatform(Wayland):
    queueRedrawWayland(app)

proc setTitle*(app: App, title: string) =
  when usingPlatform(Wayland):
    setWaylandTitle(app, title)

proc markDamaged*(app: App) =
  when usingPlatform(Wayland):
    markWaylandDamaged(app)

proc newApp*(title: string = "Surfer", appId: string = "xyz.xtrayambak.surfer"): App =
  App(title: title, appId: appId)

export types
