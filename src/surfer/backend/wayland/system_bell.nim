## Routines to handle system bell
##
## Copyright (C) 2026 Trayambak Rai (xtrayambak@disroot.org)
import std/importutils
import pkg/nayland/types/protocols/xdg_system_bell, pkg/surfer/types

privateAccess(types.App)

proc ringWaylandSystemBell*(app: App) =
  if app.xdgSystemBell == nil:
    return # NOTE: I think raising an exception for such a trivial op would be overkill.

  app.xdgSystemBell.ring(
    if app.surfaces.len > 0:
      app.surfaces[0]
    else:
      nil
  )

  # fun fact: before losing your mind for 3 hours over why this doesn't work in your desktop, try checking if you set the bell sound to None. I _DEFINITELY_ didn't just waste a few hours pulling my hair out and looking at libwayland logs. Trust me.
