# OpenGL dmabuf triangle

A spinning triangle rendered with **fixed-function OpenGL** and presented over
**Wayland** with no libwayland and no Wayland EGL platform — the GPU buffer is
handed to the compositor zero-copy as a **dmabuf**.

This is the OpenGL counterpart to `../vulkan_triangle`.

## How it works

1. A **surfaceless** EGL context (`EGL_PLATFORM_SURFACELESS_MESA`) is created —
   no window system involved. Default (compatibility) context, so legacy
   fixed-function GL works.
2. Each frame is rendered into an FBO-backed `GL_RGBA8` texture with plain
   `glRotatef` + `glBegin/glEnd`.
3. The texture is exported as a **dmabuf** via `EGL_MESA_image_dma_buf_export`
   (`eglCreateImageKHR` of `EGL_GL_TEXTURE_2D` → `eglExportDMABUFImageMESA`),
   which yields the fd, stride, offset, DRM fourcc and modifier.
4. The fd is sent to the compositor through the pure-Pascal binding's
   `zwp_linux_dmabuf_v1` implementation (out-of-band via `SCM_RIGHTS`), wrapped
   as a `wl_buffer` with the **queried** format/modifier (so tiled formats work),
   and attached to an `xdg_toplevel` surface.

Triple-buffered with `wl_buffer.release` tracking and `wl_surface.frame` pacing.
Anti-aliasing is free **supersampling**: the texture is rendered at `SS`× the
window size and the surface uses `wl_surface.set_buffer_scale(SS)`, so the
compositor downsamples — clean edges with no MSAA renderbuffers or shaders. The
surface is marked opaque, and rotation is time-based.

The GL FBO entry points and the EGL dmabuf-export functions are extensions, so
they're loaded at runtime via `eglGetProcAddress` (the core `gl_fpc` / `egl_fpc`
bindings are GL 1.x / EGL 1.x).

## Building

```sh
./build.sh
./opengl_triangle   # connect to the running compositor; close the window to quit
```

`gl_fpc.pas` and `egl_fpc.pas` are vendored from the `pascal_bindgen` generator.
`build.sh` points the unit path at `wayland-rt` / `wayland-stable` and links
`libGL.so.1` + `libEGL.so.1` directly.
