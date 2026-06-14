{ OpenGL spinning triangle, presented over Wayland with NO libwayland / Wayland
  EGL platform.

  Fixed-function OpenGL renders a triangle into an offscreen FBO-backed texture
  using a SURFACELESS EGL context (EGL_PLATFORM_SURFACELESS_MESA -- no window
  system). The texture is exported as a dmabuf via EGL_MESA_image_dma_buf_export,
  and that fd is handed to the compositor through the pure-Pascal binding's
  zwp_linux_dmabuf_v1 implementation (out-of-band via SCM_RIGHTS), wrapped as a
  wl_buffer and attached to an xdg_toplevel surface -- zero copy.

  Anti-aliasing is free supersampling: we render at SS x the window size and set
  wl_surface.set_buffer_scale(SS) so the compositor downsamples -- clean edges
  with plain fixed-function GL (no MSAA renderbuffers, no shaders).

  Triple-buffered with wl_buffer.release tracking and wl_surface.frame pacing.
  The DRM format + modifier are whatever EGL exported (queried, not hardcoded),
  so tiled formats work too.

  Build with ./build.sh. }
program opengl_triangle;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  ctypes, SysUtils, BaseUnix,
  gl_fpc, egl_fpc,
  Wayland_Core, wayland, linux_dmabuf_v1_protocol, xdg_shell_protocol;

const
  WIN_W = 800;
  WIN_H = 600;
  SS    = 2;            // supersample factor (render at SS x, buffer_scale = SS)
  TEX_W = WIN_W * SS;
  TEX_H = WIN_H * SS;
  // Double-buffered: the minimum that still animates (a single buffer deadlocks
  // -- the compositor won't release the only buffer it's displaying). Combined
  // with the "draw only when ready AND free" pacing below, this keeps just one
  // frame in flight, minimising the trailing that stacks up at high speed.
  FRAME_SLOTS = 2;
  ROT_SPEED = 2.5;      // radians/second

  // EGL / GL enums not in the core bindings
  EGL_PLATFORM_SURFACELESS_MESA = $31DD;
  EGL_GL_TEXTURE_2D             = $30B1;
  GL_FRAMEBUFFER          = $8D40;
  GL_COLOR_ATTACHMENT0    = $8CE0;
  GL_FRAMEBUFFER_COMPLETE = $8CD5;

  BTN_LEFT  = $110; // 272 — interactive move
  BTN_RIGHT = $111; // 273 — close

type
  EGLuint64 = QWord;
  PEGLuint64 = ^EGLuint64;

  // extension entry points (loaded via eglGetProcAddress)
  TeglGetPlatformDisplayEXT = function(platform: EGLenum; native_display: Pointer; attrib_list: Pcint): EGLDisplay; cdecl;
  TeglCreateImageKHR  = function(dpy: EGLDisplay; ctx: EGLContext; target: EGLenum; buffer: EGLClientBuffer; attrib_list: Pcint): EGLImage; cdecl;
  TeglDestroyImageKHR = function(dpy: EGLDisplay; image: EGLImage): EGLBoolean; cdecl;
  TeglExportDMABUFImageQueryMESA = function(dpy: EGLDisplay; image: EGLImage; fourcc: Pcint; num_planes: Pcint; modifiers: PEGLuint64): EGLBoolean; cdecl;
  TeglExportDMABUFImageMESA = function(dpy: EGLDisplay; image: EGLImage; fds: Pcint; strides: Pcint; offsets: Pcint): EGLBoolean; cdecl;

  // GL FBO entry points (not in the GL 1.1 bindings)
  TglGenFramebuffers       = procedure(n: GLsizei; framebuffers: PGLuint); cdecl;
  TglBindFramebuffer       = procedure(target: GLenum; framebuffer: GLuint); cdecl;
  TglFramebufferTexture2D  = procedure(target, attachment, textarget: GLenum; texture: GLuint; level: GLint); cdecl;
  TglCheckFramebufferStatus= function(target: GLenum): GLenum; cdecl;

  TFrameSlot = record
    Tex:      GLuint;
    Fbo:      GLuint;
    Image:    EGLImage;
    DmabufFd: cint;
    Stride:   DWord;
    Offset:   DWord;
    Buffer:   TWlBuffer;
    Busy:     Boolean;
  end;

  { TGlTriangle }

  TGlTriangle = class
  private
    // EGL
    FDpy: EGLDisplay;
    FCtx: EGLContext;
    FFourcc:   cint;
    FModifier: EGLuint64;
    // extension fn pointers
    FGetPlatformDisplay: TeglGetPlatformDisplayEXT;
    FCreateImage:  TeglCreateImageKHR;
    FDestroyImage: TeglDestroyImageKHR;
    FExportQuery:  TeglExportDMABUFImageQueryMESA;
    FExport:       TeglExportDMABUFImageMESA;
    FGenFramebuffers: TglGenFramebuffers;
    FBindFramebuffer: TglBindFramebuffer;
    FFramebufferTexture2D: TglFramebufferTexture2D;
    FCheckFramebufferStatus: TglCheckFramebufferStatus;
    FSlots: array[0..FRAME_SLOTS-1] of TFrameSlot;
    // Wayland
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
    FFrames:     Integer;
    FStartTick:  QWord;

    function  GetEglProc(const AName: String): Pointer;
    procedure InitEgl;
    procedure CreateSlot(var ASlot: TFrameSlot);
    procedure RenderSlot(var ASlot: TFrameSlot; AAngleRad: Single);

    procedure InitWayland;
    procedure BuildWlBuffers;
    function  AcquireSlot: Integer;
    procedure TryDraw;
    procedure DrawFrame;

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
    procedure Run;
  end;

{ TGlTriangle }

function TGlTriangle.GetEglProc(const AName: String): Pointer;
begin
  Result := Pointer(eglGetProcAddress(PAnsiChar(AName)));
  if Result = nil then
    raise Exception.CreateFmt('eglGetProcAddress(%s) returned nil', [AName]);
end;

procedure TGlTriangle.InitEgl;
var
  lConfig: EGLConfig;
  lNum: cint;
  lCfgAttr: array[0..12] of cint;
  lMajor, lMinor: cint;
begin
  FGetPlatformDisplay := TeglGetPlatformDisplayEXT(GetEglProc('eglGetPlatformDisplayEXT'));
  FDpy := FGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, nil, nil);
  if FDpy = nil then raise Exception.Create('eglGetPlatformDisplay(surfaceless) failed');
  if eglInitialize(FDpy, @lMajor, @lMinor) <> EGL_TRUE then
    raise Exception.Create('eglInitialize failed');

  lCfgAttr[0]  := EGL_SURFACE_TYPE;    lCfgAttr[1]  := EGL_PBUFFER_BIT;
  lCfgAttr[2]  := EGL_RENDERABLE_TYPE; lCfgAttr[3]  := EGL_OPENGL_BIT;
  lCfgAttr[4]  := EGL_RED_SIZE;        lCfgAttr[5]  := 8;
  lCfgAttr[6]  := EGL_GREEN_SIZE;      lCfgAttr[7]  := 8;
  lCfgAttr[8]  := EGL_BLUE_SIZE;       lCfgAttr[9]  := 8;
  lCfgAttr[10] := EGL_ALPHA_SIZE;      lCfgAttr[11] := 8;
  lCfgAttr[12] := EGL_NONE;
  if (eglChooseConfig(FDpy, @lCfgAttr[0], @lConfig, 1, @lNum) <> EGL_TRUE) or (lNum < 1) then
    raise Exception.Create('eglChooseConfig found no config');

  if eglBindAPI(EGL_OPENGL_API) <> EGL_TRUE then
    raise Exception.Create('eglBindAPI(OpenGL) failed');
  // nil attribs -> a default (compatibility) context, so fixed-function works
  FCtx := eglCreateContext(FDpy, lConfig, nil, nil);
  if FCtx = nil then raise Exception.Create('eglCreateContext failed');
  if eglMakeCurrent(FDpy, nil, nil, FCtx) <> EGL_TRUE then
    raise Exception.Create('eglMakeCurrent (surfaceless) failed');

  // dmabuf-export + FBO entry points
  FCreateImage  := TeglCreateImageKHR(GetEglProc('eglCreateImageKHR'));
  FDestroyImage := TeglDestroyImageKHR(GetEglProc('eglDestroyImageKHR'));
  FExportQuery  := TeglExportDMABUFImageQueryMESA(GetEglProc('eglExportDMABUFImageQueryMESA'));
  FExport       := TeglExportDMABUFImageMESA(GetEglProc('eglExportDMABUFImageMESA'));
  FGenFramebuffers        := TglGenFramebuffers(GetEglProc('glGenFramebuffers'));
  FBindFramebuffer        := TglBindFramebuffer(GetEglProc('glBindFramebuffer'));
  FFramebufferTexture2D   := TglFramebufferTexture2D(GetEglProc('glFramebufferTexture2D'));
  FCheckFramebufferStatus := TglCheckFramebufferStatus(GetEglProc('glCheckFramebufferStatus'));
end;

procedure TGlTriangle.CreateSlot(var ASlot: TFrameSlot);
var
  lFourcc, lPlanes, lFd, lStride, lOffset: cint;
  lMod: EGLuint64;
begin
  glGenTextures(1, @ASlot.Tex);
  glBindTexture(GL_TEXTURE_2D, ASlot.Tex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_RGBA8), TEX_W, TEX_H, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil);

  FGenFramebuffers(1, @ASlot.Fbo);
  FBindFramebuffer(GL_FRAMEBUFFER, ASlot.Fbo);
  FFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, ASlot.Tex, 0);
  if FCheckFramebufferStatus(GL_FRAMEBUFFER) <> GL_FRAMEBUFFER_COMPLETE then
    raise Exception.Create('FBO incomplete');

  // export the texture as a dmabuf
  ASlot.Image := FCreateImage(FDpy, FCtx, EGL_GL_TEXTURE_2D,
    EGLClientBuffer(PtrUInt(ASlot.Tex)), nil);
  if ASlot.Image = nil then raise Exception.Create('eglCreateImage failed');

  if FExportQuery(FDpy, ASlot.Image, @lFourcc, @lPlanes, @lMod) <> EGL_TRUE then
    raise Exception.Create('eglExportDMABUFImageQueryMESA failed');
  if FExport(FDpy, ASlot.Image, @lFd, @lStride, @lOffset) <> EGL_TRUE then
    raise Exception.Create('eglExportDMABUFImageMESA failed');

  ASlot.DmabufFd := lFd;
  ASlot.Stride := DWord(lStride);
  ASlot.Offset := DWord(lOffset);
  FFourcc := lFourcc;        // same for every slot
  FModifier := lMod;
  ASlot.Busy := False;
  ASlot.Buffer := nil;
end;

procedure TGlTriangle.RenderSlot(var ASlot: TFrameSlot; AAngleRad: Single);
begin
  FBindFramebuffer(GL_FRAMEBUFFER, ASlot.Fbo);
  glViewport(0, 0, TEX_W, TEX_H);
  glClearColor(0.0, 0.0, 0.0, 0.0); // transparent: only the triangle is opaque
  glClear(GL_COLOR_BUFFER_BIT);

  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;
  glRotatef(AAngleRad * 180.0 / Pi, 0, 0, 1);

  glBegin(GL_TRIANGLES);
    glColor3f(1, 0, 0); glVertex2f( 0.0,  0.6);
    glColor3f(0, 1, 0); glVertex2f(-0.6, -0.5);
    glColor3f(0, 0, 1); glVertex2f( 0.6, -0.5);
  glEnd;

  glFinish; // ensure rendering is complete before the compositor reads the dmabuf
end;

procedure TGlTriangle.InitWayland;
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
  FSurface.SetBufferScale(SS); // buffer is SS x denser -> compositor downsamples
  // No opaque region: the buffer has alpha and we want the compositor to blend,
  // so the area around the triangle shows through to whatever is behind.

  FXdgSurface := FWM.GetXdgSurface(FSurface);
  FXdgSurface.OnConfigure := @OnXdgConfigure;
  FToplevel := FXdgSurface.GetToplevel;
  FToplevel.SetTitle('wayl — OpenGL dmabuf triangle');
  FToplevel.OnConfigure := @OnToplevelConfigure;
  FToplevel.OnClose := @OnToplevelClose;
end;

procedure TGlTriangle.BuildWlBuffers;
var
  i: Integer;
  lParams: TWpLinuxBufferParamsV1;
  lFlags: TWpLinuxBufferParamsV1.TFlags;
begin
  for i := 0 to FRAME_SLOTS-1 do
  begin
    lParams := FDmabuf.CreateParams;
    lParams.Add(FSlots[i].DmabufFd, 0, FSlots[i].Offset, FSlots[i].Stride,
                DWord(FModifier shr 32), DWord(FModifier and $FFFFFFFF));
    lFlags.Value := 0;
    FSlots[i].Buffer := lParams.CreateImmed(TEX_W, TEX_H, DWord(FFourcc), lFlags);
    FSlots[i].Buffer.OnRelease := @OnBufferRelease;
    lParams.Free;
  end;
end;

function TGlTriangle.AcquireSlot: Integer;
var
  i: Integer;
begin
  for i := 0 to FRAME_SLOTS-1 do
    if not FSlots[i].Busy then Exit(i);
  Result := -1;
end;

// Draw only when the compositor has asked for a new frame AND a buffer is free.
// (With FRAME_SLOTS=1 this serialises strictly: one frame on screen at a time.)
procedure TGlTriangle.TryDraw;
begin
  if FQuit or not FFrameReady then Exit;
  if AcquireSlot < 0 then Exit;
  FFrameReady := False;
  DrawFrame;
end;

procedure TGlTriangle.DrawFrame;
var
  idx: Integer;
  lCb: TWlCallback;
  lAngle: Single;
begin
  idx := AcquireSlot;
  if idx < 0 then Exit;

  lAngle := ((GetTickCount64 - FStartTick) / 1000.0) * ROT_SPEED;
  RenderSlot(FSlots[idx], lAngle);

  lCb := FSurface.Frame;
  lCb.OnDone := @OnFrameDone;

  FSlots[idx].Busy := True;
  FSurface.Attach(FSlots[idx].Buffer, 0, 0);
  FSurface.DamageBuffer(0, 0, TEX_W, TEX_H);
  FSurface.Commit;

  Inc(FFrames);
  if (FFrames mod 30) = 0 then
  begin
    WriteLn(Format('  presented %d frames', [FFrames]));
    Flush(Output);
  end;
end;

procedure TGlTriangle.OnRegistryGlobal(Sender: TWlRegistry; aName: DWord;
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

procedure TGlTriangle.OnError(Sender: TWlDisplay; aObjectId: Cardinal;
  aCode: DWord; aMessage: String);
begin
  WriteLn(Format('wayland error: obj[%d] code %d: %s', [aObjectId, aCode, aMessage]));
  FQuit := True;
end;

procedure TGlTriangle.OnPing(Sender: TXdgWmBase; aSerial: DWord);
begin
  Sender.Pong(aSerial);
end;

procedure TGlTriangle.OnXdgConfigure(Sender: TXdgSurface; aSerial: DWord);
begin
  Sender.AckConfigure(aSerial);
  if not FConfigured then
  begin
    FConfigured := True;
    FFrameReady := True;
    TryDraw; // first frame
  end;
end;

procedure TGlTriangle.OnToplevelConfigure(Sender: TXdgToplevel; aWidth,
  aHeight: Integer; aStates: TBytes);
begin
end;

procedure TGlTriangle.OnToplevelClose(Sender: TXdgToplevel);
begin
  FQuit := True;
end;

procedure TGlTriangle.OnSeatCapabilities(Sender: TWlSeat;
  aCapabilities: TWlSeat.TCapability);
begin
  if aCapabilities.Pointer and not Assigned(FPointer) then
  begin
    FPointer := Sender.GetPointer;
    FPointer.OnButton := @OnPointerButton;
  end;
end;

procedure TGlTriangle.OnPointerButton(Sender: TWlPointer; aSerial, aTime,
  aButton: DWord; aState: TWlPointer.TButtonState);
begin
  if aState <> TWlPointer.TButtonState.buPressed then Exit;
  case aButton of
    BTN_LEFT:  FToplevel.Move(FSeat, aSerial); // interactive drag-move
    BTN_RIGHT: FQuit := True;                  // close
  end;
end;

procedure TGlTriangle.OnBufferRelease(Sender: TWlBuffer);
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

procedure TGlTriangle.OnFrameDone(Sender: TWlCallback; aData: DWord);
begin
  Sender.Free;
  FFrameReady := True;
  TryDraw; // compositor is ready — draw if a buffer is also free
end;

constructor TGlTriangle.Create;
var
  i: Integer;
begin
  InitEgl;
  for i := 0 to FRAME_SLOTS-1 do
    CreateSlot(FSlots[i]);
  InitWayland;
  BuildWlBuffers;
  FStartTick := GetTickCount64;
end;

procedure TGlTriangle.Run;
begin
  WriteLn(Format('OpenGL dmabuf triangle: rendering (fourcc %x, modifier %x). Close the window to quit.',
    [FFourcc, FModifier]));
  Flush(Output);
  FSurface.Commit; // buffer-less commit -> first configure -> first frame
  while not FQuit do
    FDisplay.WaitMessage(100);
end;

var
  lApp: TGlTriangle;
begin
  lApp := TGlTriangle.Create;
  lApp.Run;
end.
