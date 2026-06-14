{
  SKETCH — Vulkan offscreen render -> dmabuf -> Wayland present.

  This is illustrative, not a compiling unit. It shows how the pure-Pascal
  Wayland binding (wayland-rt) presents GPU frames WITHOUT libwayland / EGL /
  Vulkan WSI. Vulkan renders offscreen, the image's memory is exported as a
  dmabuf fd, and that fd is handed to the compositor over the wire via
  zwp_linux_dmabuf_v1 -- using the binding's existing fd-passing (SCM_RIGHTS).

  The Vulkan calls are sketched (extern decls / error checks omitted). Fill in
  a real loader (e.g. via dynlibs + vkGetInstanceProcAddr) for production.

  Pipeline:
    [VkImage offscreen] --vkGetMemoryFdKHR--> dmabuf fd
       --zwp_linux_buffer_params_v1.Add(fd,...)--> .CreateImmed --> wl_buffer
       --wl_surface.Attach + Damage + Commit--> compositor scans out the GPU
       buffer directly (zero-copy). wl_buffer.release tells us when we may
       reuse/free that image; wl_surface.frame paces the next frame.
}
unit vulkan_dmabuf_present;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ctypes, BaseUnix,
  Wayland_Core, wayland, linux_dmabuf_v1_protocol;

type
  // One slot of our hand-rolled swapchain: a GPU image + its exported fd + the
  // wl_buffer wrapping it. We own buffer lifetime via wl_buffer.release.
  TFrameImage = record
    Image:      Pointer;   // VkImage
    Memory:     Pointer;   // VkDeviceMemory (exportable)
    DmabufFd:   cint;       // from vkGetMemoryFdKHR
    Stride:     DWord;      // VkSubresourceLayout.rowPitch
    Offset:     DWord;      // VkSubresourceLayout.offset
    Buffer:     TWlBuffer;  // created via dmabuf params; nil until built
    Busy:       Boolean;    // true between Attach/Commit and wl_buffer.release
  end;

  TVulkanWaylandPresenter = class
  private
    // --- Wayland side (all via the binding, no libwayland) ---
    FDmabuf:  TWpLinuxDmabufV1;   // bound from registry global
    FSurface: TWlSurface;
    // negotiated DRM format + modifier (from dmabuf format/modifier events or
    // the v4 feedback tranches). foXrgb8888 == DRM_FORMAT_XRGB8888.
    FDrmFormat:   DWord;
    FModifierHi:  DWord;
    FModifierLo:  DWord;
    // --- GPU side ---
    FImages: array of TFrameImage;
    FWidth, FHeight: Integer;
    procedure HandleBufferRelease(Sender: TWlBuffer);
    procedure HandleFrameDone(Sender: TWlCallback; aData: DWord);
    function  AcquireFreeImage: Integer; // index, or -1 if all busy
    procedure BuildWlBuffer(var AImg: TFrameImage);
  public
    constructor Create(ADmabuf: TWpLinuxDmabufV1; ASurface: TWlSurface;
      AWidth, AHeight: Integer);
    procedure RenderAndPresent;
  end;

implementation

{ ===========================================================================
  GPU side (Vulkan) -- sketched. Device must be created with:
    VK_KHR_external_memory_fd, VK_EXT_external_memory_dma_buf,
    VK_EXT_image_drm_format_modifier
  and the physical device chosen via VK_EXT_physical_device_drm so it matches
  the compositor's main_device (from the dmabuf feedback main_device event).
  =========================================================================== }

// Allocate an offscreen VkImage whose memory can be exported as a dmabuf, with
// the DRM format modifier the compositor advertised. Returns the slot filled in.
procedure CreateExportableImage(var AImg: TFrameImage; AWidth, AHeight: Integer;
  ADrmFormat, AModifierHi, AModifierLo: DWord);
begin
  // VkImageCreateInfo with:
  //   tiling = VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT
  //   pNext  = VkImageDrmFormatModifierExplicitCreateInfoEXT{ modifier = (hi<<32)|lo }
  //          + VkExternalMemoryImageCreateInfo{ handleTypes =
  //              VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT }
  //   usage  = COLOR_ATTACHMENT | TRANSFER_DST
  // vkCreateImage(...) -> AImg.Image

  // Allocate memory with VkExportMemoryAllocateInfo{ handleTypes = DMA_BUF_BIT }
  // (+ VkMemoryDedicatedAllocateInfo for the image). vkBindImageMemory(...).

  // Query layout for plane 0:
  //   vkGetImageSubresourceLayout2EXT / DrmFormatModifierProperties ->
  //   AImg.Stride := rowPitch;  AImg.Offset := offset;

  // Export the dmabuf fd:
  //   VkMemoryGetFdInfoKHR{ memory = AImg.Memory,
  //     handleType = DMA_BUF_BIT_EXT }; vkGetMemoryFdKHR(...) -> AImg.DmabufFd
  AImg.Busy := False;
  AImg.Buffer := nil;
end;

procedure RecordAndSubmitRender(var AImg: TFrameImage);
begin
  // Record a command buffer that renders this frame into AImg.Image and
  // transitions it to a layout the compositor can scan out
  // (VK_IMAGE_LAYOUT_GENERAL, or use VK_QUEUE_FAMILY_FOREIGN_EXT ownership
  // transfer). vkQueueSubmit. With IMPLICIT sync, the dmabuf carries a fence
  // the compositor waits on, so attaching right after submit is safe enough to
  // start. For EXPLICIT sync, signal a VkSemaphore -> export sync_file ->
  // wp_linux_drm_syncobj_v1 timeline (later refinement).
end;

{ ===========================================================================
  Wayland side -- entirely via the binding.
  =========================================================================== }

constructor TVulkanWaylandPresenter.Create(ADmabuf: TWpLinuxDmabufV1;
  ASurface: TWlSurface; AWidth, AHeight: Integer);
var
  i: Integer;
begin
  FDmabuf  := ADmabuf;
  FSurface := ASurface;
  FWidth   := AWidth;
  FHeight  := AHeight;

  // In a real client these come from negotiation:
  //   - dmabuf 'format'/'modifier' events (v3), or
  //   - get_default_feedback / get_surface_feedback tranches (v4):
  //     read the format table (mmap the fd from format_table event), match a
  //     modifier whose tranche_target_device == your GPU.
  FDrmFormat  := DWord(TWlShm.TFormat.foXrgb8888); // DRM_FORMAT_XRGB8888
  FModifierHi := 0;
  FModifierLo := 0; // DRM_FORMAT_MOD_LINEAR to start; prefer a real tiled mod.

  // Triple buffer.
  SetLength(FImages, 3);
  for i := 0 to High(FImages) do
  begin
    CreateExportableImage(FImages[i], FWidth, FHeight,
      FDrmFormat, FModifierHi, FModifierLo);
    BuildWlBuffer(FImages[i]);
  end;
end;

// Wrap an exported dmabuf fd as a wl_buffer. The fd travels via the binding's
// SendFD (SCM_RIGHTS) -- Add() is generated with the 'fd' arg marked for fd
// passing, so the connection sends it out-of-band automatically.
procedure TVulkanWaylandPresenter.BuildWlBuffer(var AImg: TFrameImage);
var
  lParams: TWpLinuxBufferParamsV1;
  lFlags: TWpLinuxBufferParamsV1.TFlags;
begin
  lParams := FDmabuf.CreateParams;
  // plane 0 only for a single-plane format like XRGB8888
  lParams.Add(AImg.DmabufFd, 0, AImg.Offset, AImg.Stride,
              FModifierHi, FModifierLo);
  lFlags.Value := 0;
  // 'create' was renamed Create_ by the generator to avoid clashing with the
  // constructor; CreateImmed returns the wl_buffer synchronously.
  AImg.Buffer := lParams.CreateImmed(FWidth, FHeight, FDrmFormat, lFlags);
  AImg.Buffer.OnRelease := @HandleBufferRelease;
  lParams.Free; // params object is single-use; the wl_buffer outlives it
end;

procedure TVulkanWaylandPresenter.HandleBufferRelease(Sender: TWlBuffer);
var
  i: Integer;
begin
  // Compositor is done with this buffer -> the GPU image is free to reuse.
  for i := 0 to High(FImages) do
    if FImages[i].Buffer = Sender then
    begin
      FImages[i].Busy := False;
      Break;
    end;
end;

function TVulkanWaylandPresenter.AcquireFreeImage: Integer;
var
  i: Integer;
begin
  for i := 0 to High(FImages) do
    if not FImages[i].Busy then
      Exit(i);
  Result := -1; // all in flight; wait for a release / skip this frame
end;

procedure TVulkanWaylandPresenter.HandleFrameDone(Sender: TWlCallback; aData: DWord);
begin
  Sender.Free;
  RenderAndPresent; // drive the next frame when the compositor is ready
end;

procedure TVulkanWaylandPresenter.RenderAndPresent;
var
  idx: Integer;
  lFrame: TWlCallback;
begin
  idx := AcquireFreeImage;
  if idx < 0 then
    Exit; // back-pressure: nothing free yet

  RecordAndSubmitRender(FImages[idx]);

  // Pace to the compositor: request a frame callback BEFORE commit.
  lFrame := FSurface.Frame;
  lFrame.OnDone := @HandleFrameDone;

  FImages[idx].Busy := True;
  FSurface.Attach(FImages[idx].Buffer, 0, 0);
  FSurface.DamageBuffer(0, 0, FWidth, FHeight);
  FSurface.Commit;
  // The connection flushes; compositor scans out the dmabuf with no copy.
end;

end.
