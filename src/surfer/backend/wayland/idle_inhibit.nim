## Idle inhibition routines on Wayland
##
## Copyright (C) 2026 Trayambak Rai (xtrayambak@disroot.org)
import std/[importutils]
import
  pkg/nayland/types/protocols/idle_inhibit/prelude,
  pkg/nayland/types/protocols/core/[callback, compositor, surface]
import pkg/surfer/types, pkg/surfer/backend/wayland/windows

type
  IdleInhibitError* = AppError
  IdleInhibitNotSupported* = object of IdleInhibitError

func inhibitingIdle*(app: App): bool {.inline, raises: [].} =
  app.idleInhibitor != nil

proc setWaylandIdleInhibit*(app: App, value: bool) {.raises: [IdleInhibitError].} =
  if app.idleInhibitManager == nil:
    raise newException(
      IdleInhibitNotSupported,
      "The compositor under which this program is running does not support zwp-idle-inhibitor-v1",
    )

  if value:
    if app.idleInhibitor != nil:
      # If an inhibitor is already to attached to our surface,
      # we don't need to actually recreate it.
      return

    if app.surfaces.len < 1:
      raise newException(
        IdleInhibitError,
        "Cannot inhibit system idle if we have no surfaces to present!",
      )

    app.idleInhibitor = app.idleInhibitManager.createInhibitor(app.surfaces[0])
  else:
    if app.idleInhibitor == nil:
      raise newException(
        IdleInhibitError,
        "Cannot destroy IdleInhibitor object to end inhibition if it doesn't exist in the first place!",
      )

    app.idleInhibitor.destroy()
