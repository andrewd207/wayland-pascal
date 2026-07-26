// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.gl.context — a surfaceless OpenGL 3.3 core context, and the EGL
  extension entry points needed to hand GPU memory to a compositor.

  There is deliberately no Wayland EGL platform here. We never ask EGL for a
  window surface; we create an EGL_PLATFORM_SURFACELESS_MESA display and render
  entirely into framebuffer objects. Frames reach the compositor as dmabuf file
  descriptors exported from those FBOs' textures (see wlg.gl.target), which
  means this stack needs neither libwayland-egl nor the EGL Wayland platform,
  matching the rest of the project's no-libwayland stance.

  The context is GL 3.3 CORE — no fixed-function pipeline. Everything is drawn
  with shaders and vertex buffers by TwgGLCanvas. gl_fpc supplies the
  GL 1.3 calls that survived into core; gl_core_fpc supplies the rest, loaded
  through eglGetProcAddress by LoadGLCore.

  One context can back several targets and canvases. Whoever draws must have
  called MakeCurrent first; the class does not do so implicitly on every call. }
unit wlg.gl.context;

{$mode ObjFPC}{$H+}
{$PACKRECORDS C}

interface

uses
  SysUtils, ctypes, gl_fpc, gl_core_fpc, egl_fpc;

type
  EwgGLContext = class(Exception);

  EGLuint64 = QWord;
  PEGLuint64 = ^EGLuint64;

  // Extension entry points, all resolved via eglGetProcAddress.
  TeglGetPlatformDisplayEXT = function(platform: EGLenum; native_display: Pointer;
    attrib_list: Pcint): EGLDisplay; cdecl;
  TeglCreateImageKHR = function(dpy: EGLDisplay; ctx: EGLContext; target: EGLenum;
    buffer: EGLClientBuffer; attrib_list: Pcint): EGLImage; cdecl;
  TeglDestroyImageKHR = function(dpy: EGLDisplay; image: EGLImage): EGLBoolean; cdecl;
  TeglExportDMABUFImageQueryMESA = function(dpy: EGLDisplay; image: EGLImage;
    fourcc: Pcint; num_planes: Pcint; modifiers: PEGLuint64): EGLBoolean; cdecl;
  TeglExportDMABUFImageMESA = function(dpy: EGLDisplay; image: EGLImage;
    fds: Pcint; strides: Pcint; offsets: Pcint): EGLBoolean; cdecl;

const
  EGL_PLATFORM_SURFACELESS_MESA = $31DD;
  EGL_GL_TEXTURE_2D             = $30B1;

type

  { TwgGLContext }

  TwgGLContext = class
  private
    FDisplay: EGLDisplay;
    FContext: EGLContext;
    FConfig: EGLConfig;
    FMajor: Integer;
    FMinor: Integer;

    FCreateImage:  TeglCreateImageKHR;
    FDestroyImage: TeglDestroyImageKHR;
    FExportQuery:  TeglExportDMABUFImageQueryMESA;
    FExportImage:  TeglExportDMABUFImageMESA;
    FCanExportDmabuf: Boolean;

    procedure InitDisplay;
    procedure CreateContext;
    procedure LoadExtensions;
    function  HasEGLExtension(const AName: String): Boolean;
  public
    // Bring up a surfaceless EGL display and a GL AMajor.AMinor core context.
    // Raises EwgGLContext with the failing step named if anything refuses.
    constructor Create(AMajor: Integer = 3; AMinor: Integer = 3);
    destructor Destroy; override;

    // Bind this context to the calling thread. Required before any GL call.
    procedure MakeCurrent;
    procedure ReleaseCurrent;

    // Resolve a GL/EGL entry point. Matches TGLGetProcAddress so it can be
    // handed straight to LoadGLCore.
    function GetProcAddress(const AName: String): Pointer;

    { --- dmabuf export (EGL_MESA_image_dma_buf_export) --- }

    // False when the driver lacks the export extensions; a target then cannot
    // hand its textures to a compositor and the caller must fall back to shm.
    property CanExportDmabuf: Boolean read FCanExportDmabuf;

    function CreateImageFromTexture(ATexture: GLuint): EGLImage;
    procedure DestroyImage(AImage: EGLImage);
    // Query the DRM format and modifier EGL chose for AImage.
    procedure QueryExport(AImage: EGLImage; out AFourcc: Integer;
      out APlanes: Integer; out AModifier: QWord);
    // Export plane 0. The returned fd is owned by the CALLER and must be closed.
    procedure ExportImage(AImage: EGLImage; out AFd: Integer;
      out AStride: Integer; out AOffset: Integer);

    property Display: EGLDisplay read FDisplay;
    property Context: EGLContext read FContext;
    property VersionMajor: Integer read FMajor;
    property VersionMinor: Integer read FMinor;
  end;

implementation

{ TwgGLContext }

constructor TwgGLContext.Create(AMajor: Integer; AMinor: Integer);
begin
  inherited Create;
  FMajor := AMajor;
  FMinor := AMinor;
  InitDisplay;
  CreateContext;
  MakeCurrent;
  // Requires a current context: the loader calls eglGetProcAddress and, on some
  // drivers, entry points only resolve once a context exists.
  LoadGLCore(@GetProcAddress);
  LoadExtensions;
end;

destructor TwgGLContext.Destroy;
begin
  if FDisplay <> nil then
  begin
    eglMakeCurrent(FDisplay, nil, nil, nil);
    if FContext <> nil then
      eglDestroyContext(FDisplay, FContext);
    eglTerminate(FDisplay);
  end;
  FContext := nil;
  FDisplay := nil;
  inherited Destroy;
end;

procedure TwgGLContext.InitDisplay;
var
  lGetPlatformDisplay: TeglGetPlatformDisplayEXT;
  lMajor, lMinor: cint;
begin
  lGetPlatformDisplay := TeglGetPlatformDisplayEXT(
    eglGetProcAddress('eglGetPlatformDisplayEXT'));
  if lGetPlatformDisplay = nil then
    raise EwgGLContext.Create(
      'EGL_EXT_platform_base is missing; cannot create a surfaceless display');

  FDisplay := lGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, nil, nil);
  if FDisplay = nil then
    raise EwgGLContext.Create('eglGetPlatformDisplay(SURFACELESS_MESA) failed');
  if eglInitialize(FDisplay, @lMajor, @lMinor) <> EGL_TRUE then
    raise EwgGLContext.CreateFmt('eglInitialize failed (EGL error 0x%.4x)',
      [eglGetError]);
end;

function TwgGLContext.HasEGLExtension(const AName: String): Boolean;
var
  lExts: PAnsiChar;
begin
  lExts := eglQueryString(FDisplay, EGL_EXTENSIONS);
  if lExts = nil then
    Exit(False);
  // Space-delimited list; pad both sides so a name cannot match a prefix of
  // a longer extension name.
  Result := Pos(' ' + AName + ' ', ' ' + String(lExts) + ' ') > 0;
end;

procedure TwgGLContext.CreateContext;
var
  lCfgAttr: array[0..12] of cint;
  lCtxAttr: array[0..6] of cint;
  lNum: cint;
begin
  lCfgAttr[0]  := EGL_SURFACE_TYPE;    lCfgAttr[1]  := EGL_PBUFFER_BIT;
  lCfgAttr[2]  := EGL_RENDERABLE_TYPE; lCfgAttr[3]  := EGL_OPENGL_BIT;
  lCfgAttr[4]  := EGL_RED_SIZE;        lCfgAttr[5]  := 8;
  lCfgAttr[6]  := EGL_GREEN_SIZE;      lCfgAttr[7]  := 8;
  lCfgAttr[8]  := EGL_BLUE_SIZE;       lCfgAttr[9]  := 8;
  lCfgAttr[10] := EGL_ALPHA_SIZE;      lCfgAttr[11] := 8;
  lCfgAttr[12] := EGL_NONE;
  if (eglChooseConfig(FDisplay, @lCfgAttr[0], @FConfig, 1, @lNum) <> EGL_TRUE)
     or (lNum < 1) then
    raise EwgGLContext.Create('eglChooseConfig found no RGBA8 config');

  if eglBindAPI(EGL_OPENGL_API) <> EGL_TRUE then
    raise EwgGLContext.Create('eglBindAPI(EGL_OPENGL_API) failed');

  lCtxAttr[0] := EGL_CONTEXT_MAJOR_VERSION;       lCtxAttr[1] := FMajor;
  lCtxAttr[2] := EGL_CONTEXT_MINOR_VERSION;       lCtxAttr[3] := FMinor;
  lCtxAttr[4] := EGL_CONTEXT_OPENGL_PROFILE_MASK;
  lCtxAttr[5] := EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT;
  lCtxAttr[6] := EGL_NONE;

  FContext := eglCreateContext(FDisplay, FConfig, nil, @lCtxAttr[0]);
  if FContext = nil then
    raise EwgGLContext.CreateFmt(
      'eglCreateContext for GL %d.%d core failed (EGL error 0x%.4x)',
      [FMajor, FMinor, eglGetError]);
end;

procedure TwgGLContext.LoadExtensions;
begin
  // These four come as a set. Treat a partial set as unavailable rather than
  // discovering the gap at export time.
  FCreateImage  := TeglCreateImageKHR(eglGetProcAddress('eglCreateImageKHR'));
  FDestroyImage := TeglDestroyImageKHR(eglGetProcAddress('eglDestroyImageKHR'));
  FExportQuery  := TeglExportDMABUFImageQueryMESA(
    eglGetProcAddress('eglExportDMABUFImageQueryMESA'));
  FExportImage  := TeglExportDMABUFImageMESA(
    eglGetProcAddress('eglExportDMABUFImageMESA'));

  FCanExportDmabuf := (FCreateImage <> nil) and (FDestroyImage <> nil) and
                      (FExportQuery <> nil) and (FExportImage <> nil) and
                      HasEGLExtension('EGL_MESA_image_dma_buf_export');
end;

procedure TwgGLContext.MakeCurrent;
begin
  // Surfaceless: no draw or read surface, only the context.
  if eglMakeCurrent(FDisplay, nil, nil, FContext) <> EGL_TRUE then
    raise EwgGLContext.CreateFmt('eglMakeCurrent failed (EGL error 0x%.4x)',
      [eglGetError]);
end;

procedure TwgGLContext.ReleaseCurrent;
begin
  eglMakeCurrent(FDisplay, nil, nil, nil);
end;

function TwgGLContext.GetProcAddress(const AName: String): Pointer;
begin
  Result := Pointer(eglGetProcAddress(PAnsiChar(AName)));
end;

function TwgGLContext.CreateImageFromTexture(ATexture: GLuint): EGLImage;
begin
  if not FCanExportDmabuf then
    raise EwgGLContext.Create(
      'EGL_MESA_image_dma_buf_export is unavailable on this driver');
  Result := FCreateImage(FDisplay, FContext, EGL_GL_TEXTURE_2D,
    EGLClientBuffer(PtrUInt(ATexture)), nil);
  if Result = nil then
    raise EwgGLContext.CreateFmt(
      'eglCreateImageKHR(GL_TEXTURE_2D) failed (EGL error 0x%.4x)', [eglGetError]);
end;

procedure TwgGLContext.DestroyImage(AImage: EGLImage);
begin
  if (AImage <> nil) and (FDestroyImage <> nil) then
    FDestroyImage(FDisplay, AImage);
end;

procedure TwgGLContext.QueryExport(AImage: EGLImage; out AFourcc: Integer;
  out APlanes: Integer; out AModifier: QWord);
var
  lFourcc, lPlanes: cint;
  lMod: EGLuint64;
begin
  if FExportQuery(FDisplay, AImage, @lFourcc, @lPlanes, @lMod) <> EGL_TRUE then
    raise EwgGLContext.CreateFmt(
      'eglExportDMABUFImageQueryMESA failed (EGL error 0x%.4x)', [eglGetError]);
  AFourcc := lFourcc;
  APlanes := lPlanes;
  AModifier := lMod;
end;

procedure TwgGLContext.ExportImage(AImage: EGLImage; out AFd: Integer;
  out AStride: Integer; out AOffset: Integer);
var
  lFd, lStride, lOffset: cint;
begin
  if FExportImage(FDisplay, AImage, @lFd, @lStride, @lOffset) <> EGL_TRUE then
    raise EwgGLContext.CreateFmt(
      'eglExportDMABUFImageMESA failed (EGL error 0x%.4x)', [eglGetError]);
  AFd := lFd;
  AStride := lStride;
  AOffset := lOffset;
end;

end.
