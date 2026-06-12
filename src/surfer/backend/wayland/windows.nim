## Routines for creating and managing "windows" (XDG toplevels)
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak@disroot.org)
import std/[importutils, options, posix, strutils]
#!fmt: off
import
  pkg/nayland/types/[egl, display],
  pkg/nayland/types/protocols/core/[buffer, callback, compositor, shm, shm_pool, surface],
  pkg/nayland/types/protocols/xdg_shell/[wm_base, xdg_surface, xdg_toplevel],
  pkg/nayland/types/protocols/xdg_decoration/prelude,
  pkg/nayland/types/protocols/tearing_control/prelude
#!fmt: on
import pkg/[vmath, shakar]
import
  pkg/surfer/types,
  pkg/surfer/backend/wayland/[allocator, init],
  pkg/surfer/backend/wayland/bindings/[egl, vulkan]

privateAccess(types.App)

func calculatePoolSize*(size: IVec2): tuple[stride, poolSize: int32] =
  let stride = size.x * 4
  let poolSize = stride * size.y

  (stride: stride, poolSize: poolSize)

proc allocateShmemPool(app: App, size: IVec2) =
  let (_, poolSize) = calculatePoolSize(size)
  let shmem = allocateShmemFd(poolSize)

  app.pools.surfacePool = &app.shm.createPool(shmem.fd, poolSize)
  app.pools.surfaceDest = shmem.buffer
  app.pools.surfacePoolSize = poolSize
  app.pools.surfacePoolFd = shmem.fd

proc allocateSurfaceBuffer*(app: App, size: IVec2) =
  app.pools.surface = &app.pools.surfacePool.createBuffer(
    offset = 0'i32,
    width = size.x,
    height = size.y,
    stride = size.x * 4,
    format = ShmFormat.ARGB8888,
  )

proc queueRedrawWayland*(app: App) =
  if app.renderer == Renderer.Software and app.pools.surface != nil:
    app.surfaces[0].attach(app.pools.surface, 0, 0)
  elif app.renderer == Renderer.GLES:
    assert(
      eglSwapBuffers(app.eglDisplay, app.eglSurface),
      "eglSwapBuffers() failed! Code: 0x" & $toHex(eglGetError()),
    )

  app.surfaces[0].commit()

proc markWaylandDamaged*(app: App) =
  app.surfaces[0].damage(0, 0, app.windowSize.x, app.windowSize.y)

proc frameCallback*(callback: Callback, app: pointer, data: uint32) {.cdecl.} =
  let app = cast[App](app)

  # First, we can schedule another frame.
  # TODO: This will not work in a multi-window setup,
  # I gotta fix that when adding mutli-window support.
  let newCb = app.surfaces[0].frame()
  newCb.listen(cast[pointer](app), frameCallback)

  # Append a redraw event to the event queue.
  app.queue &= Event(kind: EventKind.RedrawRequested)

proc setWaylandTitle*(app: App, title: string) =
  app.xdgToplevels[0].title = title

proc resizeWaylandWindow*(app: App, dimensions: IVec2) =
  if dimensions.x == 0 or dimensions.y == 0:
    # If either of the dimensions are zero,
    # ignore this request. For now, atleast.
    return

  # Let the programmer know that our window size has changed,
  # so they can account for it in their own logic.
  app.windowSize = dimensions
  app.queue &= Event(kind: EventKind.WindowResized, windowSize: dimensions)

  case app.renderer
  of Renderer.Software:
    let oldSurfDest = app.pools.surfaceDest
    let oldSurfPoolFd = app.pools.surfacePoolFd
    let oldSurfPoolSize = app.pools.surfacePoolSize
    let oldSurfaceBuffer = app.pools.surface

    oldSurfaceBuffer.onRelease = proc(buff: Buffer) =
      discard posix.munmap(oldSurfDest, oldSurfPoolSize)
      discard close(oldSurfPoolFd)

    attachCallbacks(oldSurfaceBuffer)

    allocateShmemPool(app, dimensions)
    allocateSurfaceBuffer(app, dimensions)
    queueRedrawWayland(app)
  of Renderer.GLES:
    app.eglWindow.resize(dimensions.x, dimensions.y, 0'i32, 0'i32)
  of Renderer.Vulkan:
    discard

proc initializeWaylandEGL*(app: App) =
  # Mostly based on https://gist.github.com/Miouyouyou/ca15af1c7f2696f66b0e013058f110b4
  var
    majorVer, minorVer: EGLint
    config: EGLConfig
    #!fmt: off
    fbAttribs = [
      EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
      EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
      EGL_RED_SIZE, 8,
      EGL_GREEN_SIZE, 8,
      EGL_BLUE_SIZE, 8,
      EGL_ALPHA_SIZE, 8,
      EGL_NONE
    ]
    contextAttribs = [
      EGL_CONTEXT_CLIENT_VERSION, 2,
      EGL_NONE, EGL_NONE
    ]
    #!fmt: off

  when not defined(danger):
    assert(sizeof(fbAttribs) mod 2 == 0)
    assert(sizeof(contextAttribs) mod 2 == 0)

  app.eglDisplay = eglGetDisplay(app.display.handle)
  if app.eglDisplay == EGL_NO_DISPLAY:
    raise newException(EGLInitError, "eglGetDisplay() returned EGL_NO_DISPLAY")

  if not eglInitialize(app.eglDisplay, majorVer.addr, minorVer.addr):
    raise newException(EGLInitError, "Failed to initialize EGL!")
  
  if (var numConfigs: EGLint; not eglGetConfigs(app.eglDisplay, nil, 0, numConfigs.addr) or numConfigs < 1):
    raise newException(EGLInitError, "eglGetConfigs() has failed, or it returned zero configurations to choose from.")
  
  if (var numConfigs: EGLint; not eglChooseConfig(app.eglDisplay, fbAttribs[0].addr, config.addr, 1, numConfigs.addr) or numConfigs < 1):
    raise newException(EGLInitError, "eglChooseConfig() has failed")

  app.eglSurface = eglCreateWindowSurface(app.eglDisplay, config, app.eglWindow.handle, nil)
  if app.eglSurface == EGL_NO_SURFACE:
    raise newException(EGLInitError, "eglCreateWindowSurface() failed")

  app.eglContext = eglCreateContext(app.eglDisplay, config, EGL_NO_CONTEXT, contextAttribs[0].addr)
  if app.eglContext == EGL_NO_CONTEXT:
    raise newException(EGLInitError, "eglCreateContext() failed")

  if not eglMakeCurrent(app.eglDisplay, app.eglSurface, app.eglSurface, app.eglContext):
    raise newException(EGLInitError, "eglMakeCurrent() failed")

proc initializeWaylandVulkan*(app: App, surface: Surface) =
  var
    appInfo = newVkApplicationInfo(pApplicationName = app.appId, applicationVersion = vkMakeVersion(0, 0, 0, 0), pEngineName = app.appId, engineVersion = vkMakeVersion(0, 0, 0, 0), apiVersion = (
      when defined(surferVulkan10):
        vkApiVersion1_0
      elif defined(surferVulkan11): vkApiVersion1_1
      elif defined(surferVulkan12): vkApiVersion1_2
      elif defined(surferVulkan13): vkApiVersion1_3
      elif defined(surferVulkan14): vkApiVersion1_4
      else: vkApiVersion1_4
    ))
    extensions = [cstring(VkKhrSurfaceExtensionName), cstring(VkKhrWaylandSurfaceExtensionName)]

    instanceCreateInfo = newVkInstanceCreateInfo(
      pApplicationInfo = appInfo.addr,
      pEnabledLayerNames = [], # TODO: Maybe expose this to the programmer somehow?
      pEnabledExtensionNames = extensions
    )

  if vkCreateInstance(
    instanceCreateInfo.addr, nil, app.vkInstance.addr
  ) != VkSuccess:
    raise newException(VulkanInitError, "Failed to create Vulkan instance!")

  var extCount: uint32
  discard vkEnumerateInstanceExtensionProperties(nil, extCount.addr, nil)
  app.vkExtensions = newSeq[VkExtensionProperties](extCount)
  discard vkEnumerateInstanceExtensionProperties(nil, extCount.addr, app.vkExtensions[0].addr)

  var createInfo = VkWaylandSurfaceCreateInfoKHR(
    sType: VkStructureType.WaylandSurfaceCreateInfoKhr,
    pNext: nil,
    flags: cast[VkWaylandSurfaceCreateFlagsKHR](0),
    display: app.display.handle,
    surface: surface.handle
  )

  if vkCreateWaylandSurfaceKHR(app.vkInstance, createInfo.addr, nil, app.vkSurface.addr) != VkSuccess:
    raise newException(VulkanInitError, "Failed to create Vulkan Wayland surface!")

proc initializeSurfaceRenderer*(app: App, surface: Surface, dimensions: IVec2) =
  ## Initialize the renderer context for the given surface.
  ##
  ## **Note**: This function is idempotent.
  
  if app.renderer == Renderer.Software and app.pools.surfacePool != nil:
    return

  if app.renderer == Renderer.GLES and app.eglWindow != nil:
    return
  
  # debugecho "App::initializeSurfaceRenderer"
  app.windowSize = dimensions

  case app.renderer
  of Renderer.Software:
    if app.pools.surfacePool == nil:
      allocateShmemPool(app, dimensions)

    allocateSurfaceBuffer(app, dimensions)
    surface.attach(app.pools.surface, 0, 0)
    surface.damage(0, 0, dimensions.x, dimensions.y)
    surface.commit()
  of Renderer.GLES:
    app.eglWindow = createEGLWindow(surface, dimensions.x, dimensions.y)
    initializeWaylandEGL(app)

    surface.damage(0, 0, dimensions.x, dimensions.y)
    discard eglSwapBuffers(app.eglDisplay, app.eglSurface)
  of Renderer.Vulkan:
    initializeWaylandVulkan(app, surface)

proc setWaylandCSD*(app: App, flag: bool) =
  if app.xdgDecorationManager == nil or app.xdgToplevelDecoration == nil:
    return

  app.xdgToplevelDecoration.setMode(
    (if flag:
      XDGToplevelDecorationMode.ClientSide
    else:
      XDGToplevelDecorationMode.ServerSide
    )
  )

proc setWaylandPresentationHint*(app: App, hint: PresentationHint) =
  if app.tearingControlManager == nil or app.tearingControl == nil:
    return

  app.tearingControl.setPresentationHint(hint)

proc createWaylandWindow*(app: App, dimensions: IVec2, renderer: Renderer) =
  # Firstly, we'll create a `wl_surface`.
  # This is basically what we'll be blitting to.
  let surface = app.compositor.createSurface()
  app.surfaces &= surface

  # Then, we can create an XDG surface to help "associate"
  # the surface in the context of a DE/compositor.
  let xdgSurface = &app.xdgWmBase.getXDGSurface(surface)
  xdgSurface.onConfigure = proc(surface: XDGSurface, data: pointer, serial: uint32) =
    # debugecho "XDGSurface::configure"
    surface.ackConfigure(serial)

    initializeSurfaceRenderer(app, app.surfaces[0], app.windowSize)

    if *app.nextWindowSize:
      # The XDGToplevel probably received a configure event
      # of its own, and now we need to resize the window.
      resizeWaylandWindow(app, &app.nextWindowSize)
      app.nextWindowSize = none(IVec2)

  attachCallbacks(xdgSurface)
  app.xdgSurfaces &= xdgSurface

  # Then, we can create a toplevel. This is _ACTUALLY_
  # what constitutes a "window" in the traditional Windows sense
  let xdgToplevel = &xdgSurface.getToplevel()
  xdgToplevel.title = app.title
  xdgToplevel.appId = app.appId

  xdgToplevel.onClose = proc(_: XDGToplevel) =
    app.closureRequested = true
    app.queue &= Event(kind: EventKind.ClosureRequested)

  xdgToplevel.onConfigure = proc(_: XDGToplevel, width, height: int32) =
    # debugecho "XDGToplevel::configure"

    let size = ivec2(width, height)
    if app.windowSize == size:
      return

    app.nextWindowSize = some(size)

  xdgToplevel.attachCallbacks()

  app.xdgToplevels &= xdgToplevel

  app.xdgWmBase.attachCallbacks()
  app.display.roundtrip()

  surface.frame.listen(cast[ptr AppObj](app), frameCallback)

  if app.xdgDecorationManager != nil:
    app.xdgToplevelDecoration = app.xdgDecorationManager.getToplevelDecoration(xdgToplevel)
    app.xdgToplevelDecoration.onConfigure = proc(_: XDGToplevelDecoration, mode: XDGToplevelDecorationMode) =
      discard
  
  if app.tearingControlManager != nil:
    app.tearingControl = app.tearingControlManager.getTearingControl(surface)

  # Renderer-specific initialization
  app.renderer = renderer
  initializeWaylandAux(app)

  app.surfaces[0].damage(0, 0, dimensions.x, dimensions.y)
  app.surfaces[0].commit()

  # if app.renderer != Renderer.Software:
  #  initializeSurfaceRenderer(app, app.surfaces[0], dimensions)
