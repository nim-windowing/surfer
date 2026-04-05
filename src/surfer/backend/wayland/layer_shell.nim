## Routines to handle layer-shell based surfaces
##
## Copyright (C) 2026 Trayambak Rai (xtrayambak@disroot.org)
import std/[importutils]
import
  pkg/nayland/types/protocols/wlr/layer_shell/prelude,
  pkg/nayland/types/protocols/core/[callback, compositor, surface]
import pkg/surfer/types, pkg/surfer/backend/wayland/windows
import pkg/vmath
export Anchor, KeyboardInteractivity, Layer

privateAccess(types.App)

type
  LayerShellError* = AppError
  LayerShellNotSupported* = object of LayerShellError

proc createWaylandLayerSurface*(
    app: App,
    layer: Layer,
    anchors: set[Anchor],
    interactivity: KeyboardInteractivity,
    namespace: string,
    renderer: Renderer,
    requestedSize: IVec2 = ivec2(0, 0),
) =
  if app.layerShell == nil:
    raise newException(
      LayerShellNotSupported,
      "The compositor under which this program is running does not support wlr-layer-shell-unstable-v1",
    )

  # Firstly, we'll create a `wl_surface`.
  # This is basically what we'll be blitting to.
  let surface = app.compositor.createSurface()
  app.surfaces &= surface

  let layerSurface = app.layerShell.getLayerSurface(
    surface = surface, layer = layer, namespace = namespace
  ) # TODO: Support for `Output`
  layerSurface.anchor = anchors
  layerSurface.keyboardInteractivity = interactivity

  app.renderer = renderer

  layerSurface.onConfigure = proc(
      layerSurf: LayerSurface, serial, width, height: uint32
  ) =
    layerSurf.ackConfigure(serial)
    initializeSurfaceRenderer(app, surface, ivec2(int32(width), int32(height)))
    resizeWaylandWindow(app, ivec2(int32(width), int32(height)))

  layerSurface.onClosed = proc(_: LayerSurface) =
    app.closureRequested = true
    app.queue &= Event(kind: EventKind.ClosureRequested)

  layerSurface.attachCallbacks()

  app.layerSurfaces &= layerSurface

  surface.frame.listen(cast[ptr AppObj](app), frameCallback)

  surface.commit()
