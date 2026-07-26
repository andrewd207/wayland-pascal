// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.gl.texture — a GL texture that presents itself as an IwgSurface.

  TwgGLTexture is the single texture type the GL backend uses for everything: the
  render targets a canvas draws into, the uploaded copies of CPU images in the
  canvas's texture cache, and the glyph atlas pages. Because it implements
  IwgTextureSurface, any of those can be handed straight back to the canvas as a
  blit source with no upload and no copy.

  Two colour layouts, chosen at construction:

    RGBA8 — ordinary colour. Uploads take TwgColor pixels (host DWord
            0xAARRGGBB) and go up as GL_BGRA + GL_UNSIGNED_INT_8_8_8_8_REV,
            which on little-endian desktop GL is the native memory order, so
            the driver does a straight copy rather than a swizzle.
    R8    — single-channel coverage, for glyph atlases. The shader reads the
            red channel as alpha.

  ORIENTATION: every texture here is top-down — texel row 0 is the image's top
  row. Uploads get that for free, and render targets get it because the canvas
  projects canvas-Y directly onto NDC-Y rather than flipping (see the vertex
  shader in wlg.canvas.gl), so nothing needs inverting. FlipV exists for the
  case IwgTextureSurface explicitly allows — a bottom-up texture from somewhere
  else, e.g. a decoder — and makes GetTextureUV report V inverted so the canvas
  samples it correctly without anyone copying pixels. Leave it False for
  textures this unit produces. }
unit wlg.gl.texture;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, ctypes, gl_fpc, gl_core_fpc, wlg.surface;

type
  EwgGLTexture = class(Exception);

  TwgGLTextureFormat = (
    tfRGBA8,      // colour
    tfR8          // single-channel coverage (glyph atlas)
  );

  TwgGLTextureFilter = (tflNearest, tflLinear);

  { TwgGLTexture }

  TwgGLTexture = class(TwgSurfaceObject, IwgTextureSurface)
  private
    FHandle: GLuint;
    FWidth: Integer;
    FHeight: Integer;
    FFormat: TwgGLTextureFormat;
    FFilter: TwgGLTextureFilter;
    FFlipV: Boolean;
    FOwnsHandle: Boolean;
    FHasAlpha: Boolean;
    procedure ApplyFilter;
  protected
    function GetSurfaceWidth: Integer; override;
    function GetSurfaceHeight: Integer; override;
    function GetSurfaceHasAlpha: Boolean; override;
    // Reported through IwgSurface now, so a CPU consumer sees it too.
    function GetSurfaceFormat: TwgSurfaceFormat; override;
  public
    { IwgTextureSurface — public rather than protected, because the GL backend
      calls these on a concrete TwgGLTexture as well as through the interface. }
    function GetTextureHandle: PtrUInt;
    procedure GetTextureUV(out AU0, AV0, AU1, AV1: Single);

    // Allocate an uninitialised texture of the given size and format.
    constructor Create(AWidth, AHeight: Integer;
      AFormat: TwgGLTextureFormat = tfRGBA8; AFilter: TwgGLTextureFilter = tflLinear);
    // Adopt an existing GL texture name. AOwnsHandle decides whether Destroy
    // deletes it — pass False for a texture someone else allocated.
    constructor CreateFromHandle(AHandle: GLuint; AWidth, AHeight: Integer;
      AFormat: TwgGLTextureFormat; AOwnsHandle: Boolean);
    destructor Destroy; override;

    procedure Bind(AUnit: Integer = 0);

    // Replace the whole image. AData must hold AHeight rows of AStride bytes
    // (TwgColor pixels for tfRGBA8, single bytes for tfR8). AStride <= 0
    // means tightly packed.
    procedure Upload(AData: Pointer; AStride: Integer = 0);
    // Replace a sub-rectangle. Same pixel layout rules as Upload.
    procedure UploadRect(AX, AY, AWidth, AHeight: Integer; AData: Pointer;
      AStride: Integer = 0);
    // Copy an IwgSurface's CPU pixels in. Sizes must match. Returns False if the
    // surface will not hand out pixels.
    function UploadFromSurface(ASurface: IwgSurface): Boolean;
    // Fill the whole texture with zeroes.
    procedure Clear;

    property Handle: GLuint read FHandle;
    property Format: TwgGLTextureFormat read FFormat;
    property Filter: TwgGLTextureFilter read FFilter write FFilter;
    // Set for textures GL renders into, whose rows run bottom-up.
    property FlipV: Boolean read FFlipV write FFlipV;
    property HasAlpha: Boolean read FHasAlpha write FHasAlpha;
  end;

implementation

{ TwgGLTexture }

constructor TwgGLTexture.Create(AWidth, AHeight: Integer;
  AFormat: TwgGLTextureFormat; AFilter: TwgGLTextureFilter);
var
  lInternal: GLint;
  lFormat, lType: GLenum;
begin
  inherited Create;
  if (AWidth <= 0) or (AHeight <= 0) then
    raise EwgGLTexture.CreateFmt('TwgGLTexture: invalid size %dx%d', [AWidth, AHeight]);
  FWidth := AWidth;
  FHeight := AHeight;
  FFormat := AFormat;
  FFilter := AFilter;
  FOwnsHandle := True;
  FHasAlpha := True;

  glGenTextures(1, @FHandle);
  if FHandle = 0 then
    raise EwgGLTexture.Create('glGenTextures returned 0 (is a context current?)');
  glBindTexture(GL_TEXTURE_2D, FHandle);
  ApplyFilter;

  if AFormat = tfR8 then
  begin
    lInternal := GLint(GL_R8);
    lFormat := GL_RED;
    lType := GL_UNSIGNED_BYTE;
  end
  else
  begin
    lInternal := GLint(GL_RGBA8);
    lFormat := GL_BGRA;
    lType := GL_UNSIGNED_INT_8_8_8_8_REV;
  end;
  glTexImage2D(GL_TEXTURE_2D, 0, lInternal, FWidth, FHeight, 0, lFormat, lType, nil);
end;

constructor TwgGLTexture.CreateFromHandle(AHandle: GLuint; AWidth, AHeight: Integer;
  AFormat: TwgGLTextureFormat; AOwnsHandle: Boolean);
begin
  inherited Create;
  FHandle := AHandle;
  FWidth := AWidth;
  FHeight := AHeight;
  FFormat := AFormat;
  FFilter := tflLinear;
  FOwnsHandle := AOwnsHandle;
  FHasAlpha := True;
end;

destructor TwgGLTexture.Destroy;
begin
  if FOwnsHandle and (FHandle <> 0) then
    glDeleteTextures(1, @FHandle);
  FHandle := 0;
  inherited Destroy;
end;

procedure TwgGLTexture.ApplyFilter;
var
  lFilter: GLint;
begin
  if FFilter = tflNearest then
    lFilter := GLint(GL_NEAREST)
  else
    lFilter := GLint(GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, lFilter);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, lFilter);
  // Clamping matters for atlases: without it, linear filtering at a glyph's
  // edge would bleed in the opposite edge of the page.
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GLint(GL_CLAMP_TO_EDGE));
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GLint(GL_CLAMP_TO_EDGE));
end;

function TwgGLTexture.GetSurfaceWidth: Integer;
begin
  Result := FWidth;
end;

function TwgGLTexture.GetSurfaceHeight: Integer;
begin
  Result := FHeight;
end;

function TwgGLTexture.GetSurfaceHasAlpha: Boolean;
begin
  Result := FHasAlpha;
end;

function TwgGLTexture.GetTextureHandle: PtrUInt;
begin
  Result := FHandle;
end;

function TwgGLTexture.GetSurfaceFormat: TwgSurfaceFormat;
begin
  if FFormat = tfR8 then
    Result := sfA8
  else
    Result := sfARGB32;
end;

procedure TwgGLTexture.GetTextureUV(out AU0, AV0, AU1, AV1: Single);
begin
  AU0 := 0;
  AU1 := 1;
  if FFlipV then
  begin
    // GL rendered into this bottom-up; hand back an inverted V so a top-left
    // origin sample lands on the right row.
    AV0 := 1;
    AV1 := 0;
  end
  else
  begin
    AV0 := 0;
    AV1 := 1;
  end;
end;

procedure TwgGLTexture.Bind(AUnit: Integer);
begin
  glActiveTexture(GL_TEXTURE0 + GLenum(AUnit));
  glBindTexture(GL_TEXTURE_2D, FHandle);
end;

procedure TwgGLTexture.Upload(AData: Pointer; AStride: Integer);
begin
  UploadRect(0, 0, FWidth, FHeight, AData, AStride);
end;

procedure TwgGLTexture.UploadRect(AX, AY, AWidth, AHeight: Integer; AData: Pointer;
  AStride: Integer);
var
  lFormat, lType: GLenum;
  lPixelBytes, lRowPixels: Integer;
begin
  if (AData = nil) or (AWidth <= 0) or (AHeight <= 0) then
    Exit;
  if FFormat = tfR8 then
  begin
    lFormat := GL_RED;
    lType := GL_UNSIGNED_BYTE;
    lPixelBytes := 1;
  end
  else
  begin
    lFormat := GL_BGRA;
    lType := GL_UNSIGNED_INT_8_8_8_8_REV;
    lPixelBytes := 4;
  end;
  if AStride <= 0 then
    AStride := AWidth * lPixelBytes;

  glBindTexture(GL_TEXTURE_2D, FHandle);
  // GL wants the row length in PIXELS, not bytes. A stride that is not a whole
  // number of pixels cannot be expressed this way.
  if (AStride mod lPixelBytes) <> 0 then
    raise EwgGLTexture.CreateFmt(
      'TwgGLTexture: stride %d is not a multiple of the %d-byte pixel size',
      [AStride, lPixelBytes]);
  lRowPixels := AStride div lPixelBytes;
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, lRowPixels);
  glTexSubImage2D(GL_TEXTURE_2D, 0, AX, AY, AWidth, AHeight, lFormat, lType, AData);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  Changed;
end;

function TwgGLTexture.UploadFromSurface(ASurface: IwgSurface): Boolean;
var
  lPixels: IwgPixelSurface;
  lData: PByte;
  lStride: Integer;
begin
  Result := False;
  if ASurface = nil then
    Exit;
  if not Supports(ASurface, IwgPixelSurface, lPixels) then
    Exit;
  if (ASurface.Width <> FWidth) or (ASurface.Height <> FHeight) then
    raise EwgGLTexture.CreateFmt(
      'TwgGLTexture: surface is %dx%d but the texture is %dx%d',
      [ASurface.Width, ASurface.Height, FWidth, FHeight]);
  if not lPixels.LockPixels(lData, lStride) then
    Exit;
  try
    UploadRect(0, 0, FWidth, FHeight, lData, lStride);
    FHasAlpha := ASurface.HasAlpha;
    Result := True;
  finally
    lPixels.UnlockPixels;
  end;
end;

procedure TwgGLTexture.Clear;
var
  lZero: PByte;
  lBytes: PtrUInt;
begin
  if FFormat = tfR8 then
    lBytes := PtrUInt(FWidth) * PtrUInt(FHeight)
  else
    lBytes := PtrUInt(FWidth) * PtrUInt(FHeight) * 4;
  lZero := GetMem(lBytes);
  try
    FillChar(lZero^, lBytes, 0);
    Upload(lZero);
  finally
    FreeMem(lZero);
  end;
end;

end.
