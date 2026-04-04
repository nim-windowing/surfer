type Platform* {.size: sizeof(uint8).} = enum
  Wayland = 0

func getPlatform*(): Platform {.compileTime.} =
  when defined(linux) or defined(wayland):
    return Platform.Wayland

func usingPlatform*(platform: Platform): bool {.compileTime.} =
  getPlatform() == platform
