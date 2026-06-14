#!/bin/sh
# Build the OpenGL dmabuf triangle example. Run from this directory.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
RT=$HERE/../../../wayland-rt/src/main/pascal
STABLE=$HERE/../../../wayland-stable/src/main/pascal
LIBDIR=/usr/lib/x86_64-linux-gnu

echo "compiling program..."
# The GL/EGL bindings say external 'libGL'/'libEGL'; link the SONAMEs directly.
# -FU keeps compiled units out of the (shared) wayland source trees.
mkdir -p "$HERE/units"
fpc -Mobjfpc -O1 \
    -FU"$HERE/units" \
    -Fu"$RT" -Fu"$STABLE" -Fu"$HERE" \
    -k"-rpath=$LIBDIR" -k"$LIBDIR/libGL.so.1" -k"$LIBDIR/libEGL.so.1" \
    "$HERE/opengl_triangle.pas"

echo "built: $HERE/opengl_triangle"
