with import <nixpkgs> { };

mkShell {
  nativeBuildInputs = [
    pkg-config
    c2nim
    wayland
    libxkbcommon
    wayland-scanner
    vulkan-headers
    vulkan-loader
    libGL
  ];

  LD_LIBRARY_PATH = lib.makeLibraryPath [
    wayland.dev
    libxkbcommon.dev
    libGL.dev
    vulkan-loader.dev
  ];
}
