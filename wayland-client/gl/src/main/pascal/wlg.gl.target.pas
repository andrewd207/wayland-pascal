// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.gl.target — FBO-backed render targets, optionally exported as dmabufs.

  TwgGLRenderTarget is one texture plus the framebuffer object that renders into
  it. It is an IwgTextureSurface (via its texture), so a target that has been
  drawn into can immediately be blitted from — that is how the canvas's
  supersample buffer is resolved into the presentation target.

  TwgGLTargetRing is a small ring of those, for presentation. A compositor holds
  on to a buffer while it is on screen, so a client that draws into the buffer
  it just committed will tear; the ring hands out a target that is not currently
  held. Each slot's texture is exported once at construction as a dmabuf file
  descriptor, which the caller wraps in a wl_buffer through
  zwp_linux_dmabuf_v1 — zero copy, the GPU writes exactly the memory the
  compositor scans out.

  This unit deliberately knows nothing about Wayland. It produces file
  descriptors, strides, offsets, a DRM fourcc and a modifier; turning those into
  a wl_buffer is the caller's job, which keeps the GL module independent of the
  protocol tiers.

  FD OWNERSHIP: each slot owns its exported fd and closes it on Free. A caller
  that passes the fd to zwp_linux_dmabuf_v1 is only lending it — the protocol
  dups what it needs — so the caller must NOT close it. }
unit wlg.gl.target;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, BaseUnix, ctypes, gl_fpc, gl_core_fpc, egl_fpc,
  wlg.surface, wlg.gl.context, wlg.gl.texture;

type
  EwgGLTarget = class(Exception);

  { TwgGLRenderTarget — a texture with an FBO attached. }

  TwgGLRenderTarget = class
  private
    FContext: TwgGLContext;
    FTexture: TwgGLTexture;
    FFbo: GLuint;
    FWidth: Integer;
    FHeight: Integer;
    // dmabuf export, only when Create was asked for it
    FImage: EGLImage;
    FDmabufFd: Integer;
    FStride: Integer;
    FOffset: Integer;
    FFourcc: Integer;
    FModifier: QWord;
    FExported: Boolean;
    procedure BuildFbo;
    procedure ExportDmabuf;
  public
    // AExport asks for the texture to be exported as a dmabuf as well; it
    // raises if the driver cannot, so pass False for purely internal targets
    // (the supersample buffer) that never reach a compositor.
    constructor Create(AContext: TwgGLContext; AWidth, AHeight: Integer;
      AExport: Boolean);
    destructor Destroy; override;

    // Direct all subsequent drawing here, with the viewport set to its size.
    procedure Bind;

    property Texture: TwgGLTexture read FTexture;
    property Fbo: GLuint read FFbo;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;

    { --- dmabuf, valid only when Exported --- }
    property Exported: Boolean read FExported;
    // Owned by this target; do not close it.
    property DmabufFd: Integer read FDmabufFd;
    property Stride: Integer read FStride;
    property Offset: Integer read FOffset;
    property Fourcc: Integer read FFourcc;
    property Modifier: QWord read FModifier;
  end;

  { TwgGLTargetRing — several exported targets, cycled for presentation. }

  TwgGLTargetRing = class
  private
    FTargets: array of TwgGLRenderTarget;
    FBusy: array of Boolean;
    FWidth: Integer;
    FHeight: Integer;
    function GetTarget(AIndex: Integer): TwgGLRenderTarget;
    function GetCount: Integer;
  public
    // ACount below 2 will deadlock against a compositor that holds the buffer
    // it is displaying, so it is clamped to at least 2.
    constructor Create(AContext: TwgGLContext; AWidth, AHeight: Integer;
      ACount: Integer = 2);
    destructor Destroy; override;

    // Index of a target the compositor is not holding, or -1 if all are busy.
    function Acquire: Integer;
    // Mark as handed to the compositor; it will not be reused until released.
    procedure MarkBusy(AIndex: Integer);
    // Call from the wl_buffer.release handler.
    procedure MarkFree(AIndex: Integer);
    function IsBusy(AIndex: Integer): Boolean;

    property Targets[AIndex: Integer]: TwgGLRenderTarget read GetTarget; default;
    property Count: Integer read GetCount;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
  end;

implementation

{ TwgGLRenderTarget }

constructor TwgGLRenderTarget.Create(AContext: TwgGLContext;
  AWidth, AHeight: Integer; AExport: Boolean);
begin
  inherited Create;
  if AContext = nil then
    raise EwgGLTarget.Create('TwgGLRenderTarget: nil context');
  FContext := AContext;
  FWidth := AWidth;
  FHeight := AHeight;
  FDmabufFd := -1;

  FTexture := TwgGLTexture.Create(AWidth, AHeight, tfRGBA8, tflLinear);
  // NOT flipped. The canvas projects canvas-Y straight onto NDC-Y (see the
  // vertex shader in wlg.canvas.gl), so canvas row 0 rasterises into
  // framebuffer memory row 0. That makes this texture top-down like any
  // uploaded image, and makes the exported dmabuf's first row the top row —
  // which is what a wl_buffer means. Setting FlipV here would present
  // vertically mirrored frames.
  BuildFbo;

  if AExport then
    ExportDmabuf;
end;

destructor TwgGLRenderTarget.Destroy;
begin
  if FImage <> nil then
    FContext.DestroyImage(FImage);
  if FDmabufFd >= 0 then
    FpClose(FDmabufFd);
  if FFbo <> 0 then
    glDeleteFramebuffers(1, @FFbo);
  FTexture.Free;
  inherited Destroy;
end;

procedure TwgGLRenderTarget.BuildFbo;
var
  lStatus: GLenum;
  lPrev: GLint;
begin
  // Preserve whatever was bound; constructing a target must not disturb a
  // frame that is already in progress on another one.
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, @lPrev);
  glGenFramebuffers(1, @FFbo);
  glBindFramebuffer(GL_FRAMEBUFFER, FFbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
    FTexture.Handle, 0);
  lStatus := glCheckFramebufferStatus(GL_FRAMEBUFFER);
  glBindFramebuffer(GL_FRAMEBUFFER, GLuint(lPrev));
  if lStatus <> GL_FRAMEBUFFER_COMPLETE then
    raise EwgGLTarget.CreateFmt(
      'framebuffer incomplete for a %dx%d RGBA8 target (status 0x%.4x)',
      [FWidth, FHeight, lStatus]);
end;

procedure TwgGLRenderTarget.ExportDmabuf;
var
  lPlanes: Integer;
begin
  if not FContext.CanExportDmabuf then
    raise EwgGLTarget.Create(
      'this driver cannot export GL textures as dmabufs ' +
      '(EGL_MESA_image_dma_buf_export missing)');

  FImage := FContext.CreateImageFromTexture(FTexture.Handle);
  FContext.QueryExport(FImage, FFourcc, lPlanes, FModifier);
  if lPlanes <> 1 then
    raise EwgGLTarget.CreateFmt(
      'exported dmabuf has %d planes; only single-plane targets are supported',
      [lPlanes]);
  FContext.ExportImage(FImage, FDmabufFd, FStride, FOffset);
  FExported := True;
end;

procedure TwgGLRenderTarget.Bind;
begin
  glBindFramebuffer(GL_FRAMEBUFFER, FFbo);
  glViewport(0, 0, FWidth, FHeight);
end;

{ TwgGLTargetRing }

constructor TwgGLTargetRing.Create(AContext: TwgGLContext;
  AWidth, AHeight: Integer; ACount: Integer);
var
  i: Integer;
begin
  inherited Create;
  if ACount < 2 then
    ACount := 2;
  FWidth := AWidth;
  FHeight := AHeight;
  SetLength(FTargets, ACount);
  SetLength(FBusy, ACount);
  for i := 0 to ACount - 1 do
    FTargets[i] := TwgGLRenderTarget.Create(AContext, AWidth, AHeight, True);
end;

destructor TwgGLTargetRing.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FTargets) do
    FTargets[i].Free;
  SetLength(FTargets, 0);
  SetLength(FBusy, 0);
  inherited Destroy;
end;

function TwgGLTargetRing.GetTarget(AIndex: Integer): TwgGLRenderTarget;
begin
  Result := FTargets[AIndex];
end;

function TwgGLTargetRing.GetCount: Integer;
begin
  Result := Length(FTargets);
end;

function TwgGLTargetRing.Acquire: Integer;
var
  i: Integer;
begin
  for i := 0 to High(FTargets) do
    if not FBusy[i] then
      Exit(i);
  Result := -1;
end;

procedure TwgGLTargetRing.MarkBusy(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex <= High(FBusy)) then
    FBusy[AIndex] := True;
end;

procedure TwgGLTargetRing.MarkFree(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex <= High(FBusy)) then
    FBusy[AIndex] := False;
end;

function TwgGLTargetRing.IsBusy(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FBusy)) and FBusy[AIndex];
end;

end.
