#!/bin/sh
# Build the Vulkan dmabuf triangle example. Run from this directory.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
RT=$HERE/../../../wayland-rt/src/main/pascal
STABLE=$HERE/../../../wayland-stable/src/main/pascal
LIBDIR=/usr/lib/x86_64-linux-gnu

# glslc lives in the kf6 snap here; adjust GLSLC if yours is elsewhere
# (or install shaderc and set GLSLC=glslc).
GLSLC=${GLSLC:-/snap/kf6-core24/36/usr/bin/glslc}
GLSLC_LIBS=${GLSLC_LIBS:-/snap/kf6-core24/36/usr/lib/x86_64-linux-gnu}

echo "compiling shaders..."
LD_LIBRARY_PATH=$GLSLC_LIBS "$GLSLC" "$HERE/triangle.vert" -o "$HERE/triangle.vert.spv"
LD_LIBRARY_PATH=$GLSLC_LIBS "$GLSLC" "$HERE/triangle.frag" -o "$HERE/triangle.frag.spv"

echo "compiling program..."
# The Vulkan bindings say external 'libvulkan'; link the SONAME directly.
# -FU keeps compiled units out of the (shared) wayland source trees.
mkdir -p "$HERE/units"
fpc -Mobjfpc -O1 \
    -FU"$HERE/units" \
    -Fu"$RT" -Fu"$STABLE" -Fu"$HERE" \
    -k"-rpath=$LIBDIR" -k"$LIBDIR/libvulkan.so.1" \
    "$HERE/vulkan_triangle.pas"

echo "built: $HERE/vulkan_triangle"
