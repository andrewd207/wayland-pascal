# Vulkan dmabuf triangle

A spinning, anti-aliased triangle rendered with **Vulkan** and presented over
**Wayland** with no libwayland, no EGL, and no Vulkan WSI — the GPU buffer is
handed to the compositor zero-copy as a **dmabuf**.

## How it works

1. Vulkan renders the triangle into an offscreen `VK_FORMAT_B8G8R8A8_UNORM` image
   with **4× MSAA**, resolving into a second image whose memory is created with
   `VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT` (LINEAR tiling).
2. The image's memory is exported to a **dmabuf fd** via `vkGetMemoryFdKHR`
   (loaded at runtime through `vkGetDeviceProcAddr` — it is an extension entry
   point, not a static libvulkan export).
3. The fd is sent to the compositor through the pure-Pascal binding's
   `zwp_linux_dmabuf_v1` implementation (the fd travels out-of-band via
   `SCM_RIGHTS`), wrapped as a `wl_buffer` with
   `DRM_FORMAT_XRGB8888` / `DRM_FORMAT_MOD_LINEAR`.
4. The `wl_buffer` is attached to an `xdg_toplevel` surface; the compositor scans
   out the GPU buffer directly.

Triple-buffered: each slot owns its own image + dmabuf + `wl_buffer`. We render
into a slot the compositor isn't using (tracked via `wl_buffer.release`) and pace
frames with `wl_surface.frame` callbacks. After rendering, each image is released
to `VK_QUEUE_FAMILY_FOREIGN_EXT` so the compositor's import sees coherent pixels
(without this, a reused slot's stale contents bleed through as ghosting). The
surface is marked opaque (XRGB has no alpha) to skip compositor blending, and the
rotation is time-based so it spins at a constant rate regardless of frame rate.

## Building

```sh
./build.sh        # compiles the shaders (glslc) and the program
./vulkan_triangle # connect to the running compositor; close the window to quit
```

The Vulkan binding (`vulkan_fpc.pas`) and `bindgen_helpers.pas` are vendored
copies from the `pascal_bindgen` generator. `build.sh` points the unit path at
`wayland-rt` and `wayland-stable` for the Wayland units, links `libvulkan.so.1`
directly (the bindings say `external 'libvulkan'`), and compiles
`triangle.vert` / `triangle.frag` to SPIR-V with `glslc`.

If `glslc` isn't on your `PATH`, set `GLSLC` (and `GLSLC_LIBS` if it needs an
out-of-tree `libshaderc`) — see the top of `build.sh`.

## Notes

This is the zero-copy counterpart to the `../vulkan_dmabuf_present.pas` sketch.
Real apps would negotiate the format/modifier from the dmabuf feedback tranches
(`zwp_linux_dmabuf_v1` v4) and use explicit sync; here we keep it minimal with
LINEAR / `MOD_LINEAR`, which Mesa drivers and the llvmpipe software ICD export
cleanly.
