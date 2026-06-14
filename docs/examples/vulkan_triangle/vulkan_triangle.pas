{ Vulkan spinning triangle, presented over Wayland with NO libwayland / EGL /
  Vulkan WSI.

  Vulkan renders a spinning triangle into an offscreen image whose memory is
  exported as a dmabuf fd (VK_KHR_external_memory_fd, DMA_BUF handle type). That
  fd is handed to the compositor through the pure-Pascal binding's
  zwp_linux_dmabuf_v1 implementation (the fd travels out-of-band via SCM_RIGHTS),
  wrapped as a wl_buffer, and attached to an xdg_toplevel surface. The compositor
  scans out the GPU buffer directly -- zero copy.

  Triple-buffered: each slot owns its own VkImage + dmabuf + wl_buffer; we render
  into a slot the compositor isn't using (tracked via wl_buffer.release) and pace
  frames with wl_surface.frame callbacks.

  The image uses LINEAR tiling and is advertised to the compositor as
  DRM_FORMAT_ARGB8888 / DRM_FORMAT_MOD_LINEAR, which Mesa drivers (and the
  llvmpipe software ICD) export cleanly -- no DRM-format-modifier negotiation.
  ARGB (not XRGB) so the compositor blends the alpha: everything but the triangle
  is transparent.

  Build with ./build.sh (needs the shaders compiled to .spv next to the binary). }
program vulkan_triangle;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  ctypes, SysUtils, Classes, BaseUnix,
  vulkan_fpc,
  Wayland_Core, wayland, linux_dmabuf_v1_protocol, xdg_shell_protocol;

const
  WIN_W = 800;
  WIN_H = 600;
  // Double-buffered: the minimum that still animates (a single buffer deadlocks
  // -- the compositor won't release the only buffer it's displaying). With the
  // "draw only when ready AND free" pacing this keeps just one frame in flight,
  // minimising the trailing that stacks up at high rotation speed.
  FRAME_SLOTS = 2;
  MSAA = VK_SAMPLE_COUNT_4_BIT; // 4x anti-aliasing for clean triangle edges
  ROT_SPEED = 2.5;              // radians/second (time-based, frame-rate independent)

  // not present in the generated bindings; from vulkan_core.h
  VK_QUEUE_FAMILY_IGNORED     = cuint($FFFFFFFF);
  VK_QUEUE_FAMILY_FOREIGN_EXT = cuint($FFFFFFFE);

  BTN_LEFT  = $110; // 272 — interactive move
  BTN_RIGHT = $111; // 273 — close

  // DRM fourcc + modifier we present to the compositor. ARGB (not XRGB) so the
  // compositor honours the alpha channel -> transparent around the triangle.
  DRM_FORMAT_ARGB8888 = $34325241; // 'AR24'
  DRM_MOD_LINEAR_HI   = 0;
  DRM_MOD_LINEAR_LO   = 0;

type
  TFrameSlot = record
    Image:   VkImage;
    Memory:  VkDeviceMemory;
    View:    VkImageView;
    Fbo:     VkFramebuffer;
    Fence:   VkFence;
    Cmd:     VkCommandBuffer;
    DmabufFd: cint;
    Stride:  DWord;
    Offset:  DWord;
    Buffer:  TWlBuffer; // nil until built
    Busy:    Boolean;   // attached and not yet released by the compositor
  end;

  { TVkTriangle }

  TVkTriangle = class
  private
    // --- Vulkan ---
    FInstance: VkInstance;
    FPhys:     VkPhysicalDevice;
    FDevice:   VkDevice;
    FQueue:    VkQueue;
    FQueueFamily: cuint;
    FRenderPass: VkRenderPass;
    FPipeLayout: VkPipelineLayout;
    FPipeline:   VkPipeline;
    FCmdPool:    VkCommandPool;
    // shared 4x-multisample colour target; resolved into each slot's export image
    FMsaaImage:  VkImage;
    FMsaaMem:    VkDeviceMemory;
    FMsaaView:   VkImageView;
    // vkGetMemoryFdKHR is an extension entry point; it is not a static export of
    // libvulkan, so it must be fetched at runtime via vkGetDeviceProcAddr.
    FGetMemoryFdKHR: PFN_vkGetMemoryFdKHR;
    FSlots: array[0..FRAME_SLOTS-1] of TFrameSlot;
    // --- Wayland ---
    FDisplay:    TWlDisplay;
    FRegistry:   TWlRegistry;
    FCompositor: TWlCompositor;
    FWM:         TXdgWmBase;
    FSurface:    TWlSurface;
    FXdgSurface: TXdgSurface;
    FToplevel:   TXdgToplevel;
    FDmabuf:     TWpLinuxDmabufV1;
    FSeat:       TWlSeat;
    FPointer:    TWlPointer;
    FConfigured: Boolean;
    FQuit:       Boolean;
    FFrameReady: Boolean; // compositor signalled it wants a new frame
    FAngle:      Single;
    FFrames:     Integer;
    FStartTick:  QWord;

    procedure VkCheck(ARc: VkResult; const AWhere: String);
    function  LoadShader(const AFile: String): VkShaderModule;
    function  PickMemoryType(ATypeBits: cuint; AProps: VkMemoryPropertyFlags): cuint;

    procedure InitVulkan;
    procedure CreateMsaaTarget;
    procedure CreatePipeline;
    procedure CreateSlotImage(var ASlot: TFrameSlot);
    procedure RecordSlot(var ASlot: TFrameSlot; AAngle: Single);

    procedure InitWayland;
    procedure BuildWlBuffers;
    function  AcquireSlot: Integer;
    procedure TryDraw;
    procedure DrawFrame;

    // wayland callbacks
    procedure OnRegistryGlobal(Sender: TWlRegistry; aName: DWord; aInterface: String; aVersion: DWord);
    procedure OnError(Sender: TWlDisplay; aObjectId: Cardinal; aCode: DWord; aMessage: String);
    procedure OnPing(Sender: TXdgWmBase; aSerial: DWord);
    procedure OnXdgConfigure(Sender: TXdgSurface; aSerial: DWord);
    procedure OnToplevelConfigure(Sender: TXdgToplevel; aWidth, aHeight: Integer; aStates: TBytes);
    procedure OnToplevelClose(Sender: TXdgToplevel);
    procedure OnSeatCapabilities(Sender: TWlSeat; aCapabilities: TWlSeat.TCapability);
    procedure OnPointerButton(Sender: TWlPointer; aSerial, aTime, aButton: DWord; aState: TWlPointer.TButtonState);
    procedure OnBufferRelease(Sender: TWlBuffer);
    procedure OnFrameDone(Sender: TWlCallback; aData: DWord);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run;
  end;

{ helpers }

function MakeVersion(major, minor, patch: cuint): cuint; inline;
begin
  Result := (major shl 22) or (minor shl 12) or patch;
end;

{ TVkTriangle }

procedure TVkTriangle.VkCheck(ARc: VkResult; const AWhere: String);
begin
  if ARc <> VK_SUCCESS then
    raise Exception.CreateFmt('%s failed: VkResult=%d', [AWhere, Integer(ARc)]);
end;

function TVkTriangle.LoadShader(const AFile: String): VkShaderModule;
var
  lStream: TMemoryStream;
  lInfo: VkShaderModuleCreateInfo;
  lPath: String;
begin
  lPath := ExtractFilePath(ParamStr(0)) + AFile;
  if not FileExists(lPath) then lPath := AFile;
  lStream := TMemoryStream.Create;
  try
    lStream.LoadFromFile(lPath);
    FillChar(lInfo, SizeOf(lInfo), 0);
    lInfo.sType := VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    lInfo.codeSize := lStream.Size;
    lInfo.pCode := Pcuint(lStream.Memory);
    VkCheck(vkCreateShaderModule(FDevice, @lInfo, nil, @Result), 'vkCreateShaderModule '+AFile);
  finally
    lStream.Free;
  end;
end;

function TVkTriangle.PickMemoryType(ATypeBits: cuint; AProps: VkMemoryPropertyFlags): cuint;
var
  lMem: VkPhysicalDeviceMemoryProperties;
  i: Integer;
begin
  vkGetPhysicalDeviceMemoryProperties(FPhys, @lMem);
  // first try a type satisfying the requested property flags...
  for i := 0 to Integer(lMem.memoryTypeCount)-1 do
    if ((ATypeBits and (cuint(1) shl i)) <> 0)
       and ((lMem.memoryTypes[i].propertyFlags and AProps) = AProps) then
      Exit(i);
  // ...otherwise any allowed type (dmabuf export is what matters here).
  for i := 0 to Integer(lMem.memoryTypeCount)-1 do
    if (ATypeBits and (cuint(1) shl i)) <> 0 then
      Exit(i);
  raise Exception.Create('no suitable Vulkan memory type');
end;

procedure TVkTriangle.InitVulkan;
var
  lApp: VkApplicationInfo;
  lIci: VkInstanceCreateInfo;
  lCount: cuint;
  lPhysList: array of VkPhysicalDevice;
  lQfProps: array of VkQueueFamilyProperties;
  lPrio: cfloat;
  lQci: VkDeviceQueueCreateInfo;
  lDci: VkDeviceCreateInfo;
  lExt: PAnsiChar;
  i: Integer;
  lFound: Boolean;
begin
  FillChar(lApp, SizeOf(lApp), 0);
  lApp.sType := VK_STRUCTURE_TYPE_APPLICATION_INFO;
  lApp.pApplicationName := 'wayl vulkan triangle';
  lApp.apiVersion := MakeVersion(1, 1, 0);

  FillChar(lIci, SizeOf(lIci), 0);
  lIci.sType := VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  lIci.pApplicationInfo := @lApp;
  VkCheck(vkCreateInstance(@lIci, nil, @FInstance), 'vkCreateInstance');

  lCount := 0;
  VkCheck(vkEnumeratePhysicalDevices(FInstance, @lCount, nil), 'vkEnumeratePhysicalDevices');
  if lCount = 0 then raise Exception.Create('no Vulkan physical devices');
  SetLength(lPhysList, lCount);
  VkCheck(vkEnumeratePhysicalDevices(FInstance, @lCount, @lPhysList[0]), 'vkEnumeratePhysicalDevices');
  FPhys := lPhysList[0];

  // find a graphics-capable queue family
  lCount := 0;
  vkGetPhysicalDeviceQueueFamilyProperties(FPhys, @lCount, nil);
  SetLength(lQfProps, lCount);
  vkGetPhysicalDeviceQueueFamilyProperties(FPhys, @lCount, @lQfProps[0]);
  lFound := False;
  for i := 0 to Integer(lCount)-1 do
    if (lQfProps[i].queueFlags and VK_QUEUE_GRAPHICS_BIT) <> 0 then
    begin
      FQueueFamily := i;
      lFound := True;
      Break;
    end;
  if not lFound then raise Exception.Create('no graphics queue family');

  lPrio := 1.0;
  FillChar(lQci, SizeOf(lQci), 0);
  lQci.sType := VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
  lQci.queueFamilyIndex := FQueueFamily;
  lQci.queueCount := 1;
  lQci.pQueuePriorities := @lPrio;

  lExt := 'VK_KHR_external_memory_fd';
  FillChar(lDci, SizeOf(lDci), 0);
  lDci.sType := VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
  lDci.queueCreateInfoCount := 1;
  lDci.pQueueCreateInfos := @lQci;
  lDci.enabledExtensionCount := 1;
  lDci.ppEnabledExtensionNames := @lExt;
  VkCheck(vkCreateDevice(FPhys, @lDci, nil, @FDevice), 'vkCreateDevice');

  vkGetDeviceQueue(FDevice, FQueueFamily, 0, @FQueue);

  FGetMemoryFdKHR := PFN_vkGetMemoryFdKHR(vkGetDeviceProcAddr(FDevice, 'vkGetMemoryFdKHR'));
  if FGetMemoryFdKHR = nil then
    raise Exception.Create('vkGetMemoryFdKHR unavailable (no VK_KHR_external_memory_fd)');
end;

procedure TVkTriangle.CreateMsaaTarget;
var
  lIci: VkImageCreateInfo;
  lReq: VkMemoryRequirements;
  lMai: VkMemoryAllocateInfo;
  lView: VkImageViewCreateInfo;
begin
  FillChar(lIci, SizeOf(lIci), 0);
  lIci.sType := VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
  lIci.imageType := VK_IMAGE_TYPE_2D;
  lIci.format := VK_FORMAT_B8G8R8A8_UNORM;
  lIci.extent.width := WIN_W;
  lIci.extent.height := WIN_H;
  lIci.extent.depth := 1;
  lIci.mipLevels := 1;
  lIci.arrayLayers := 1;
  lIci.samples := MSAA;
  lIci.tiling := VK_IMAGE_TILING_OPTIMAL;
  lIci.usage := VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT or VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT;
  lIci.sharingMode := VK_SHARING_MODE_EXCLUSIVE;
  lIci.initialLayout := VK_IMAGE_LAYOUT_UNDEFINED;
  VkCheck(vkCreateImage(FDevice, @lIci, nil, @FMsaaImage), 'vkCreateImage(msaa)');

  vkGetImageMemoryRequirements(FDevice, FMsaaImage, @lReq);
  FillChar(lMai, SizeOf(lMai), 0);
  lMai.sType := VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
  lMai.allocationSize := lReq.size;
  lMai.memoryTypeIndex := PickMemoryType(lReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
  VkCheck(vkAllocateMemory(FDevice, @lMai, nil, @FMsaaMem), 'vkAllocateMemory(msaa)');
  VkCheck(vkBindImageMemory(FDevice, FMsaaImage, FMsaaMem, 0), 'vkBindImageMemory(msaa)');

  FillChar(lView, SizeOf(lView), 0);
  lView.sType := VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
  lView.image := FMsaaImage;
  lView.viewType := VK_IMAGE_VIEW_TYPE_2D;
  lView.format := VK_FORMAT_B8G8R8A8_UNORM;
  lView.subresourceRange.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
  lView.subresourceRange.levelCount := 1;
  lView.subresourceRange.layerCount := 1;
  VkCheck(vkCreateImageView(FDevice, @lView, nil, @FMsaaView), 'vkCreateImageView(msaa)');
end;

procedure TVkTriangle.CreatePipeline;
var
  lAttach: array[0..1] of VkAttachmentDescription;
  lRef, lResolveRef: VkAttachmentReference;
  lSub: VkSubpassDescription;
  lRp: VkRenderPassCreateInfo;
  lVert, lFrag: VkShaderModule;
  lStages: array[0..1] of VkPipelineShaderStageCreateInfo;
  lVin: VkPipelineVertexInputStateCreateInfo;
  lIa: VkPipelineInputAssemblyStateCreateInfo;
  lVp: VkViewport;
  lScissor: VkRect2D;
  lVps: VkPipelineViewportStateCreateInfo;
  lRs: VkPipelineRasterizationStateCreateInfo;
  lMs: VkPipelineMultisampleStateCreateInfo;
  lCba: VkPipelineColorBlendAttachmentState;
  lCb: VkPipelineColorBlendStateCreateInfo;
  lPush: VkPushConstantRange;
  lPl: VkPipelineLayoutCreateInfo;
  lGp: VkGraphicsPipelineCreateInfo;
  lPoolInfo: VkCommandPoolCreateInfo;
begin
  // render pass: attachment 0 = multisample colour (cleared, transient);
  // attachment 1 = single-sample resolve target (the exported dmabuf image).
  FillChar(lAttach, SizeOf(lAttach), 0);
  lAttach[0].format := VK_FORMAT_B8G8R8A8_UNORM;
  lAttach[0].samples := MSAA;
  lAttach[0].loadOp := VK_ATTACHMENT_LOAD_OP_CLEAR;
  lAttach[0].storeOp := VK_ATTACHMENT_STORE_OP_DONT_CARE;
  lAttach[0].stencilLoadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
  lAttach[0].stencilStoreOp := VK_ATTACHMENT_STORE_OP_DONT_CARE;
  lAttach[0].initialLayout := VK_IMAGE_LAYOUT_UNDEFINED;
  lAttach[0].finalLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

  lAttach[1].format := VK_FORMAT_B8G8R8A8_UNORM;
  lAttach[1].samples := VK_SAMPLE_COUNT_1_BIT;
  lAttach[1].loadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
  lAttach[1].storeOp := VK_ATTACHMENT_STORE_OP_STORE;
  lAttach[1].stencilLoadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
  lAttach[1].stencilStoreOp := VK_ATTACHMENT_STORE_OP_DONT_CARE;
  lAttach[1].initialLayout := VK_IMAGE_LAYOUT_UNDEFINED;
  lAttach[1].finalLayout := VK_IMAGE_LAYOUT_GENERAL; // readable by the dmabuf importer

  FillChar(lRef, SizeOf(lRef), 0);
  lRef.attachment := 0;
  lRef.layout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
  FillChar(lResolveRef, SizeOf(lResolveRef), 0);
  lResolveRef.attachment := 1;
  lResolveRef.layout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

  FillChar(lSub, SizeOf(lSub), 0);
  lSub.pipelineBindPoint := VK_PIPELINE_BIND_POINT_GRAPHICS;
  lSub.colorAttachmentCount := 1;
  lSub.pColorAttachments := @lRef;
  lSub.pResolveAttachments := @lResolveRef;

  FillChar(lRp, SizeOf(lRp), 0);
  lRp.sType := VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
  lRp.attachmentCount := 2;
  lRp.pAttachments := @lAttach[0];
  lRp.subpassCount := 1;
  lRp.pSubpasses := @lSub;
  VkCheck(vkCreateRenderPass(FDevice, @lRp, nil, @FRenderPass), 'vkCreateRenderPass');

  lVert := LoadShader('triangle.vert.spv');
  lFrag := LoadShader('triangle.frag.spv');

  FillChar(lStages, SizeOf(lStages), 0);
  lStages[0].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
  lStages[0].stage := VK_SHADER_STAGE_VERTEX_BIT;
  lStages[0].module := lVert;
  lStages[0].pName := 'main';
  lStages[1].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
  lStages[1].stage := VK_SHADER_STAGE_FRAGMENT_BIT;
  lStages[1].module := lFrag;
  lStages[1].pName := 'main';

  FillChar(lVin, SizeOf(lVin), 0);
  lVin.sType := VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;

  FillChar(lIa, SizeOf(lIa), 0);
  lIa.sType := VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
  lIa.topology := VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

  FillChar(lVp, SizeOf(lVp), 0);
  lVp.width := WIN_W; lVp.height := WIN_H; lVp.maxDepth := 1.0;
  FillChar(lScissor, SizeOf(lScissor), 0);
  lScissor.extent.width := WIN_W; lScissor.extent.height := WIN_H;
  FillChar(lVps, SizeOf(lVps), 0);
  lVps.sType := VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
  lVps.viewportCount := 1; lVps.pViewports := @lVp;
  lVps.scissorCount := 1; lVps.pScissors := @lScissor;

  FillChar(lRs, SizeOf(lRs), 0);
  lRs.sType := VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
  lRs.polygonMode := VK_POLYGON_MODE_FILL;
  lRs.cullMode := VK_CULL_MODE_NONE;
  lRs.frontFace := VK_FRONT_FACE_COUNTER_CLOCKWISE;
  lRs.lineWidth := 1.0;

  FillChar(lMs, SizeOf(lMs), 0);
  lMs.sType := VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
  lMs.rasterizationSamples := MSAA;

  FillChar(lCba, SizeOf(lCba), 0);
  lCba.colorWriteMask := VK_COLOR_COMPONENT_R_BIT or VK_COLOR_COMPONENT_G_BIT
                      or VK_COLOR_COMPONENT_B_BIT or VK_COLOR_COMPONENT_A_BIT;
  FillChar(lCb, SizeOf(lCb), 0);
  lCb.sType := VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
  lCb.attachmentCount := 1;
  lCb.pAttachments := @lCba;

  FillChar(lPush, SizeOf(lPush), 0);
  lPush.stageFlags := VK_SHADER_STAGE_VERTEX_BIT;
  lPush.offset := 0;
  lPush.size := SizeOf(Single);
  FillChar(lPl, SizeOf(lPl), 0);
  lPl.sType := VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
  lPl.pushConstantRangeCount := 1;
  lPl.pPushConstantRanges := @lPush;
  VkCheck(vkCreatePipelineLayout(FDevice, @lPl, nil, @FPipeLayout), 'vkCreatePipelineLayout');

  FillChar(lGp, SizeOf(lGp), 0);
  lGp.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  lGp.stageCount := 2;
  lGp.pStages := @lStages[0];
  lGp.pVertexInputState := @lVin;
  lGp.pInputAssemblyState := @lIa;
  lGp.pViewportState := @lVps;
  lGp.pRasterizationState := @lRs;
  lGp.pMultisampleState := @lMs;
  lGp.pColorBlendState := @lCb;
  lGp.layout := FPipeLayout;
  lGp.renderPass := FRenderPass;
  lGp.subpass := 0;
  VkCheck(vkCreateGraphicsPipelines(FDevice, nil, 1, @lGp, nil, @FPipeline), 'vkCreateGraphicsPipelines');

  FillChar(lPoolInfo, SizeOf(lPoolInfo), 0);
  lPoolInfo.sType := VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
  lPoolInfo.flags := VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
  lPoolInfo.queueFamilyIndex := FQueueFamily;
  VkCheck(vkCreateCommandPool(FDevice, @lPoolInfo, nil, @FCmdPool), 'vkCreateCommandPool');
end;

procedure TVkTriangle.CreateSlotImage(var ASlot: TFrameSlot);
var
  lExtImg: VkExternalMemoryImageCreateInfo;
  lIci: VkImageCreateInfo;
  lReq: VkMemoryRequirements;
  lExportInfo: VkExportMemoryAllocateInfo;
  lDedicated: VkMemoryDedicatedAllocateInfo;
  lMai: VkMemoryAllocateInfo;
  lSubres: VkImageSubresource;
  lLayout: VkSubresourceLayout;
  lFdInfo: VkMemoryGetFdInfoKHR;
  lFd: cint;
  lView: VkImageViewCreateInfo;
  lFbo: VkFramebufferCreateInfo;
  lFbAttach: array[0..1] of VkImageView;
  lFenceInfo: VkFenceCreateInfo;
  lCbai: VkCommandBufferAllocateInfo;
begin
  // exportable, LINEAR colour image
  FillChar(lExtImg, SizeOf(lExtImg), 0);
  lExtImg.sType := VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO;
  lExtImg.handleTypes := VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT;

  FillChar(lIci, SizeOf(lIci), 0);
  lIci.sType := VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
  lIci.pNext := @lExtImg;
  lIci.imageType := VK_IMAGE_TYPE_2D;
  lIci.format := VK_FORMAT_B8G8R8A8_UNORM;
  lIci.extent.width := WIN_W;
  lIci.extent.height := WIN_H;
  lIci.extent.depth := 1;
  lIci.mipLevels := 1;
  lIci.arrayLayers := 1;
  lIci.samples := VK_SAMPLE_COUNT_1_BIT;
  lIci.tiling := VK_IMAGE_TILING_LINEAR;
  lIci.usage := VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
  lIci.sharingMode := VK_SHARING_MODE_EXCLUSIVE;
  lIci.initialLayout := VK_IMAGE_LAYOUT_UNDEFINED;
  VkCheck(vkCreateImage(FDevice, @lIci, nil, @ASlot.Image), 'vkCreateImage');

  vkGetImageMemoryRequirements(FDevice, ASlot.Image, @lReq);

  // export as dma_buf, dedicated to this image
  FillChar(lExportInfo, SizeOf(lExportInfo), 0);
  lExportInfo.sType := VK_STRUCTURE_TYPE_EXPORT_MEMORY_ALLOCATE_INFO;
  lExportInfo.handleTypes := VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT;
  FillChar(lDedicated, SizeOf(lDedicated), 0);
  lDedicated.sType := VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO;
  lDedicated.image := ASlot.Image;
  lDedicated.pNext := @lExportInfo;

  FillChar(lMai, SizeOf(lMai), 0);
  lMai.sType := VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
  lMai.pNext := @lDedicated;
  lMai.allocationSize := lReq.size;
  lMai.memoryTypeIndex := PickMemoryType(lReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
  VkCheck(vkAllocateMemory(FDevice, @lMai, nil, @ASlot.Memory), 'vkAllocateMemory');
  VkCheck(vkBindImageMemory(FDevice, ASlot.Image, ASlot.Memory, 0), 'vkBindImageMemory');

  // plane-0 layout: stride + offset for the dmabuf import
  FillChar(lSubres, SizeOf(lSubres), 0);
  lSubres.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
  vkGetImageSubresourceLayout(FDevice, ASlot.Image, @lSubres, @lLayout);
  ASlot.Stride := DWord(lLayout.rowPitch);
  ASlot.Offset := DWord(lLayout.offset);

  // export the dmabuf fd
  FillChar(lFdInfo, SizeOf(lFdInfo), 0);
  lFdInfo.sType := VK_STRUCTURE_TYPE_MEMORY_GET_FD_INFO_KHR;
  lFdInfo.memory := ASlot.Memory;
  lFdInfo.handleType := VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT;
  VkCheck(FGetMemoryFdKHR(FDevice, @lFdInfo, @lFd), 'vkGetMemoryFdKHR');
  ASlot.DmabufFd := lFd;

  // image view + framebuffer
  FillChar(lView, SizeOf(lView), 0);
  lView.sType := VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
  lView.image := ASlot.Image;
  lView.viewType := VK_IMAGE_VIEW_TYPE_2D;
  lView.format := VK_FORMAT_B8G8R8A8_UNORM;
  lView.subresourceRange.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
  lView.subresourceRange.levelCount := 1;
  lView.subresourceRange.layerCount := 1;
  VkCheck(vkCreateImageView(FDevice, @lView, nil, @ASlot.View), 'vkCreateImageView');

  lFbAttach[0] := FMsaaView;   // multisample colour (attachment 0)
  lFbAttach[1] := ASlot.View;  // resolve target = exported image (attachment 1)
  FillChar(lFbo, SizeOf(lFbo), 0);
  lFbo.sType := VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
  lFbo.renderPass := FRenderPass;
  lFbo.attachmentCount := 2;
  lFbo.pAttachments := PPVkImageView_T(@lFbAttach[0]);
  lFbo.width := WIN_W;
  lFbo.height := WIN_H;
  lFbo.layers := 1;
  VkCheck(vkCreateFramebuffer(FDevice, @lFbo, nil, @ASlot.Fbo), 'vkCreateFramebuffer');

  FillChar(lFenceInfo, SizeOf(lFenceInfo), 0);
  lFenceInfo.sType := VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
  VkCheck(vkCreateFence(FDevice, @lFenceInfo, nil, @ASlot.Fence), 'vkCreateFence');

  FillChar(lCbai, SizeOf(lCbai), 0);
  lCbai.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  lCbai.commandPool := FCmdPool;
  lCbai.level := VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  lCbai.commandBufferCount := 1;
  VkCheck(vkAllocateCommandBuffers(FDevice, @lCbai, @ASlot.Cmd), 'vkAllocateCommandBuffers');

  ASlot.Busy := False;
  ASlot.Buffer := nil;
end;

procedure TVkTriangle.RecordSlot(var ASlot: TFrameSlot; AAngle: Single);
var
  lBegin: VkCommandBufferBeginInfo;
  lClear: array[0..1] of VkClearValue;
  lRpb: VkRenderPassBeginInfo;
  lSubmit: VkSubmitInfo;
  lBarrier: VkImageMemoryBarrier;
begin
  VkCheck(vkResetCommandBuffer(ASlot.Cmd, 0), 'vkResetCommandBuffer');
  FillChar(lBegin, SizeOf(lBegin), 0);
  lBegin.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  VkCheck(vkBeginCommandBuffer(ASlot.Cmd, @lBegin), 'vkBeginCommandBuffer');

  FillChar(lClear, SizeOf(lClear), 0);
  lClear[0].color.float32[0] := 0.0; // transparent: only the triangle is opaque
  lClear[0].color.float32[1] := 0.0;
  lClear[0].color.float32[2] := 0.0;
  lClear[0].color.float32[3] := 0.0;

  FillChar(lRpb, SizeOf(lRpb), 0);
  lRpb.sType := VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
  lRpb.renderPass := FRenderPass;
  lRpb.framebuffer := ASlot.Fbo;
  lRpb.renderArea.extent.width := WIN_W;
  lRpb.renderArea.extent.height := WIN_H;
  lRpb.clearValueCount := 2;
  lRpb.pClearValues := @lClear[0];

  vkCmdBeginRenderPass(ASlot.Cmd, @lRpb, VK_SUBPASS_CONTENTS_INLINE);
  vkCmdBindPipeline(ASlot.Cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, FPipeline);
  vkCmdPushConstants(ASlot.Cmd, FPipeLayout, VK_SHADER_STAGE_VERTEX_BIT, 0, SizeOf(Single), @AAngle);
  vkCmdDraw(ASlot.Cmd, 3, 1, 0, 0);
  vkCmdEndRenderPass(ASlot.Cmd);

  // Hand the resolved image off to the compositor: release queue ownership to
  // the FOREIGN family so its dmabuf import sees fully-written, coherent pixels.
  // Without this the compositor can sample a slot's stale (previous-frame)
  // contents -> ghosting / fading trails. We loadOp-CLEAR on reuse, so we never
  // need to acquire it back.
  FillChar(lBarrier, SizeOf(lBarrier), 0);
  lBarrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  lBarrier.srcAccessMask := VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
  lBarrier.dstAccessMask := 0;
  lBarrier.oldLayout := VK_IMAGE_LAYOUT_GENERAL;
  lBarrier.newLayout := VK_IMAGE_LAYOUT_GENERAL;
  lBarrier.srcQueueFamilyIndex := FQueueFamily;
  lBarrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_FOREIGN_EXT;
  lBarrier.image := ASlot.Image;
  lBarrier.subresourceRange.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
  lBarrier.subresourceRange.levelCount := 1;
  lBarrier.subresourceRange.layerCount := 1;
  vkCmdPipelineBarrier(ASlot.Cmd,
    VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
    0, 0, nil, 0, nil, 1, @lBarrier);

  VkCheck(vkEndCommandBuffer(ASlot.Cmd), 'vkEndCommandBuffer');

  // submit and wait so the image is complete before the compositor reads it
  VkCheck(vkResetFences(FDevice, 1, PPVkFence_T(@ASlot.Fence)), 'vkResetFences');
  FillChar(lSubmit, SizeOf(lSubmit), 0);
  lSubmit.sType := VK_STRUCTURE_TYPE_SUBMIT_INFO;
  lSubmit.commandBufferCount := 1;
  lSubmit.pCommandBuffers := PPVkCommandBuffer_T(@ASlot.Cmd);
  VkCheck(vkQueueSubmit(FQueue, 1, @lSubmit, ASlot.Fence), 'vkQueueSubmit');
  VkCheck(vkWaitForFences(FDevice, 1, PPVkFence_T(@ASlot.Fence), VK_TRUE, High(culong)), 'vkWaitForFences');
end;

procedure TVkTriangle.InitWayland;
begin
  TWlDisplay.TryCreateConnection(FDisplay);
  FDisplay.OnError := @OnError;
  FRegistry := FDisplay.GetRegistry;
  FRegistry.OnGlobal := @OnRegistryGlobal;
  FDisplay.SyncAndWait;
  FDisplay.SyncAndWait;

  if not Assigned(FCompositor) then raise Exception.Create('no wl_compositor');
  if not Assigned(FWM) then raise Exception.Create('no xdg_wm_base');
  if not Assigned(FDmabuf) then raise Exception.Create('no zwp_linux_dmabuf_v1');

  FSurface := FCompositor.CreateSurface;
  // No opaque region: the buffer is ARGB8888 and we want the compositor to
  // blend, so the area around the triangle shows through to what's behind.

  FXdgSurface := FWM.GetXdgSurface(FSurface);
  FXdgSurface.OnConfigure := @OnXdgConfigure;
  FToplevel := FXdgSurface.GetToplevel;
  FToplevel.SetTitle('wayl — Vulkan dmabuf triangle');
  FToplevel.OnConfigure := @OnToplevelConfigure;
  FToplevel.OnClose := @OnToplevelClose;
  // NB: the initial (buffer-less) commit that elicits the first xdg configure
  // is deferred to Run, AFTER BuildWlBuffers -- otherwise the configure (which
  // draws) could fire before any wl_buffer exists.
end;

procedure TVkTriangle.BuildWlBuffers;
var
  i: Integer;
  lParams: TWpLinuxBufferParamsV1;
  lFlags: TWpLinuxBufferParamsV1.TFlags;
begin
  for i := 0 to FRAME_SLOTS-1 do
  begin
    lParams := FDmabuf.CreateParams;
    lParams.Add(FSlots[i].DmabufFd, 0, FSlots[i].Offset, FSlots[i].Stride,
                DRM_MOD_LINEAR_HI, DRM_MOD_LINEAR_LO);
    lFlags.Value := 0;
    FSlots[i].Buffer := lParams.CreateImmed(WIN_W, WIN_H, DRM_FORMAT_ARGB8888, lFlags);
    FSlots[i].Buffer.OnRelease := @OnBufferRelease;
    lParams.Free; // single-use; the wl_buffer outlives it
  end;
end;

function TVkTriangle.AcquireSlot: Integer;
var
  i: Integer;
begin
  for i := 0 to FRAME_SLOTS-1 do
    if not FSlots[i].Busy then Exit(i);
  Result := -1; // all in flight
end;

// Draw only when the compositor has asked for a new frame AND a buffer is free,
// so just one frame is ever in flight (minimum trailing at high speed).
procedure TVkTriangle.TryDraw;
begin
  if FQuit or not FFrameReady then Exit;
  if AcquireSlot < 0 then Exit;
  FFrameReady := False;
  DrawFrame;
end;

procedure TVkTriangle.DrawFrame;
var
  idx: Integer;
  lCb: TWlCallback;
begin
  idx := AcquireSlot;
  if idx < 0 then Exit; // back-pressure; wait for a release

  // time-based angle so rotation speed is independent of frame rate
  FAngle := ((GetTickCount64 - FStartTick) / 1000.0) * ROT_SPEED;
  RecordSlot(FSlots[idx], FAngle);

  lCb := FSurface.Frame;          // pace the next frame
  lCb.OnDone := @OnFrameDone;

  FSlots[idx].Busy := True;
  FSurface.Attach(FSlots[idx].Buffer, 0, 0);
  FSurface.DamageBuffer(0, 0, WIN_W, WIN_H);
  FSurface.Commit;

  Inc(FFrames);
  if (FFrames mod 30) = 0 then
  begin
    WriteLn(Format('  presented %d frames', [FFrames]));
    Flush(Output);
  end;
end;

{ wayland callbacks }

procedure TVkTriangle.OnRegistryGlobal(Sender: TWlRegistry; aName: DWord;
  aInterface: String; aVersion: DWord);
begin
  if aInterface = 'wl_compositor' then
    Sender.Bind(aName, aInterface, aVersion, TWlCompositor, FCompositor)
  else if aInterface = 'xdg_wm_base' then
  begin
    Sender.Bind(aName, aInterface, aVersion, TXdgWmBase, FWM);
    FWM.OnPing := @OnPing;
  end
  else if aInterface = 'zwp_linux_dmabuf_v1' then
    Sender.Bind(aName, aInterface, aVersion, TWpLinuxDmabufV1, FDmabuf)
  else if aInterface = 'wl_seat' then
  begin
    Sender.Bind(aName, aInterface, aVersion, TWlSeat, FSeat);
    FSeat.OnCapabilities := @OnSeatCapabilities;
  end;
end;

procedure TVkTriangle.OnError(Sender: TWlDisplay; aObjectId: Cardinal;
  aCode: DWord; aMessage: String);
begin
  WriteLn(Format('wayland error: obj[%d] code %d: %s', [aObjectId, aCode, aMessage]));
  FQuit := True;
end;

procedure TVkTriangle.OnPing(Sender: TXdgWmBase; aSerial: DWord);
begin
  Sender.Pong(aSerial);
end;

procedure TVkTriangle.OnXdgConfigure(Sender: TXdgSurface; aSerial: DWord);
begin
  Sender.AckConfigure(aSerial);
  if not FConfigured then
  begin
    FConfigured := True;
    FFrameReady := True;
    TryDraw; // kick off the first frame
  end;
end;

procedure TVkTriangle.OnToplevelConfigure(Sender: TXdgToplevel; aWidth,
  aHeight: Integer; aStates: TBytes);
begin
  // fixed-size example; ignore the suggested size
end;

procedure TVkTriangle.OnToplevelClose(Sender: TXdgToplevel);
begin
  FQuit := True;
end;

procedure TVkTriangle.OnSeatCapabilities(Sender: TWlSeat;
  aCapabilities: TWlSeat.TCapability);
begin
  if aCapabilities.Pointer and not Assigned(FPointer) then
  begin
    FPointer := Sender.GetPointer;
    FPointer.OnButton := @OnPointerButton;
  end;
end;

procedure TVkTriangle.OnPointerButton(Sender: TWlPointer; aSerial, aTime,
  aButton: DWord; aState: TWlPointer.TButtonState);
begin
  if aState <> TWlPointer.TButtonState.buPressed then Exit;
  case aButton of
    BTN_LEFT:  FToplevel.Move(FSeat, aSerial); // interactive drag-move
    BTN_RIGHT: FQuit := True;                  // close
  end;
end;

procedure TVkTriangle.OnBufferRelease(Sender: TWlBuffer);
var
  i: Integer;
begin
  for i := 0 to FRAME_SLOTS-1 do
    if FSlots[i].Buffer = Sender then
    begin
      FSlots[i].Busy := False;
      Break;
    end;
  TryDraw; // a buffer freed up — draw if the compositor is also ready
end;

procedure TVkTriangle.OnFrameDone(Sender: TWlCallback; aData: DWord);
begin
  Sender.Free;
  FFrameReady := True;
  TryDraw; // compositor is ready — draw if a buffer is also free
end;

{ lifecycle }

constructor TVkTriangle.Create;
var
  i: Integer;
begin
  InitVulkan;
  CreateMsaaTarget;
  CreatePipeline;
  for i := 0 to FRAME_SLOTS-1 do
    CreateSlotImage(FSlots[i]);
  InitWayland;
  BuildWlBuffers;
  FStartTick := GetTickCount64;
end;

destructor TVkTriangle.Destroy;
var
  i: Integer;
begin
  for i := 0 to FRAME_SLOTS-1 do
    if FSlots[i].DmabufFd > 0 then fpClose(FSlots[i].DmabufFd);
  inherited Destroy;
end;

procedure TVkTriangle.Run;
begin
  WriteLn('Vulkan dmabuf triangle: rendering. Close the window to quit.');
  Flush(Output);
  // initial buffer-less commit -> compositor replies with xdg configure, which
  // (now that the wl_buffers exist) draws and attaches the first frame.
  FSurface.Commit;
  while not FQuit do
    FDisplay.WaitMessage(100);
end;

var
  lApp: TVkTriangle;
begin
  lApp := TVkTriangle.Create;
  try
    lApp.Run;
  finally
    lApp.Free;
  end;
end.
