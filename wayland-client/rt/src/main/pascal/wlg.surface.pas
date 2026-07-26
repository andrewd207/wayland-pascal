// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.surface — what it means to be a rectangle of pixels something else can
  draw FROM.

  A canvas needs to blit images; a canvas is itself an image once you have drawn
  into it; and a GPU canvas wants to blit from a texture without ever touching
  the CPU. IwgSurface is the common denominator: width, height, whether it has
  meaningful alpha, and a generation counter. Everything a canvas can use as a
  source implements it — TwgImage here, the software TwgRasterCanvas, and
  the GL canvas's render target.

  Two refinements say HOW the pixels can be reached:

    IwgPixelSurface   — the pixels are CPU-addressable; hand back a pointer and a
                      stride. Any backend can consume this (a GPU backend
                      uploads it to a texture).
    IwgTextureSurface — the pixels already live in GPU memory; hand back the
                      native texture handle and the UV sub-rect occupied. A GPU
                      backend uses this directly and skips the upload entirely.

  A surface may implement both, one, or (for a pure GPU render target) only
  IwgTextureSurface. Consumers should prefer IwgTextureSurface and fall back.

  GENERATION is the cache key. Texture caches in a GPU backend hold an uploaded
  copy of an IwgPixelSurface; they re-upload only when Generation changes. Any
  mutation must call Changed. Generation is never reused within a process, so
  "same pointer, same generation" genuinely means "same pixels".

  LIFETIME: these interfaces do NOT own their implementor. Following the
  convention wayland_core established for protocol objects, implementors derive
  from TInterfacedObject but make _AddRef/_Release no-ops, so holding an
  IwgSurface does not keep the object alive and letting one go out of scope does
  not free it. Surfaces are freed explicitly by whoever created them.

  PIXEL FORMAT: one format, TwgColor — a host DWord 0xAARRGGBB, stored
  little-endian as bytes B,G,R,A. That is wl_shm ARGB8888/XRGB8888, and it is
  also GL_BGRA + GL_UNSIGNED_INT_8_8_8_8_REV, so an upload is a straight memcpy
  on desktop GL.

  ALPHA: surfaces carry PREMULTIPLIED alpha, because that is what both wl_shm
  and sane texture filtering want. Images decoded from PNG and friends arrive
  straight (non-premultiplied); TwgImage.Premultiply converts in place, and
  the FPImage constructors do it for you. }
unit wlg.surface;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, FPImage;

type
  EwgSurface = class(Exception);

  // 0xAARRGGBB as a host DWord (little-endian bytes B,G,R,A = wl_shm ARGB8888).
  TwgColor = type DWord;
  PwgColor = ^TwgColor;

  { TwgSurfaceFormat — how to read a surface's pixels.

    sfARGB32 is the normal case: 4 bytes per pixel, a TwgColor.
    sfA8 is ONE byte per pixel of coverage, with no colour at all — what a glyph
    atlas produces. A backend samples it as alpha and takes the colour from the
    vertex, so the same atlas page serves any text colour. Keeping this on
    IwgSurface (rather than only on the GPU-side interface) is what lets one
    FreeType atlas feed both the GL and the software canvas. }
  TwgSurfaceFormat = (sfARGB32, sfA8);

  { IwgSurface }

  IwgSurface = interface
    ['{6C8F2A41-0D3B-4F52-9E7A-2B1C5D0E8A31}']
    function GetSurfaceWidth: Integer;
    function GetSurfaceHeight: Integer;
    function GetSurfaceHasAlpha: Boolean;
    function GetSurfaceFormat: TwgSurfaceFormat;
    function GetSurfaceGeneration: QWord;

    property Width: Integer read GetSurfaceWidth;
    property Height: Integer read GetSurfaceHeight;
    // False promises every pixel is opaque, letting a backend skip blending.
    property HasAlpha: Boolean read GetSurfaceHasAlpha;
    property Format: TwgSurfaceFormat read GetSurfaceFormat;
    // Bumped on every content change; texture caches key on it.
    property Generation: QWord read GetSurfaceGeneration;
  end;

// Bytes per pixel for a surface format.
function wgSurfaceFormatBytes(AFormat: TwgSurfaceFormat): Integer; inline;

type

  { IwgPixelSurface — CPU-addressable pixels. }

  IwgPixelSurface = interface(IwgSurface)
    ['{A17E4D92-5C60-4B18-8F3D-7E9A0C2B6415}']
    // Hand back the top-left pixel and the byte stride between rows. Returns
    // False if the pixels cannot be reached right now. Every successful Lock
    // must be matched by an Unlock. Nesting is not allowed.
    function LockPixels(out AData: PByte; out AStride: Integer): Boolean;
    procedure UnlockPixels;
  end;

  { IwgTextureSurface — pixels already resident in GPU memory.

    The surface may occupy only part of its backing texture (an atlas page, or
    a power-of-two-padded upload), so the UV sub-rect is explicit. V0 > V1 is
    legal and means the texture is stored bottom-up, as GL render targets are. }

  IwgTextureSurface = interface(IwgSurface)
    ['{3F0B8E77-91A4-4D26-B5C8-1A6E42D9F083}']
    // Backend-native handle; a GL texture name for the GL backend.
    // Whether it holds colour or coverage comes from IwgSurface.Format.
    function GetTextureHandle: PtrUInt;
    procedure GetTextureUV(out AU0, AV0, AU1, AV1: Single);
  end;

  { TwgSurfaceObject — base for anything implementing IwgSurface.

    Supplies the generation counter and the no-op reference counting described
    in the unit header. }

  TwgSurfaceObject = class(TInterfacedObject, IwgSurface)
  private
    FGeneration: QWord;
  protected
    function _AddRef: LongInt; cdecl;
    function _Release: LongInt; cdecl;

    function GetSurfaceWidth: Integer; virtual; abstract;
    function GetSurfaceHeight: Integer; virtual; abstract;
    function GetSurfaceHasAlpha: Boolean; virtual;
    function GetSurfaceFormat: TwgSurfaceFormat; virtual;
    function GetSurfaceGeneration: QWord;
  public
    constructor Create;
    // Mark the content as modified so cached copies are invalidated. Call this
    // after any direct write through a locked pixel pointer.
    procedure Changed;

    property Width: Integer read GetSurfaceWidth;
    property Height: Integer read GetSurfaceHeight;
    property Generation: QWord read GetSurfaceGeneration;
  end;

  { TwgImage — a CPU-side ARGB32 image.

    Owns its pixel memory unless constructed with CreateFromMemory(..., False),
    in which case it wraps a caller-owned block that must outlive it. }

  TwgImage = class(TwgSurfaceObject, IwgPixelSurface)
  private
    FData: PByte;
    FWidth: Integer;
    FHeight: Integer;
    FStride: Integer;
    FOwnsData: Boolean;
    FHasAlpha: Boolean;
    FLocked: Boolean;
    function RowPtr(Y: Integer): PwgColor; inline;
  protected
    function GetSurfaceWidth: Integer; override;
    function GetSurfaceHeight: Integer; override;
    function GetSurfaceHasAlpha: Boolean; override;

    function LockPixels(out AData: PByte; out AStride: Integer): Boolean;
    procedure UnlockPixels;
  public
    // A new, zero-filled (fully transparent) image.
    constructor Create(AWidth, AHeight: Integer);
    // Wrap or copy existing ARGB32 memory. AStride <= 0 means tightly packed.
    constructor CreateFromMemory(AData: Pointer; AWidth, AHeight: Integer;
      AStride: Integer; ACopy: Boolean);
    // Convert from an FPImage. The 16-bit channels are reduced to 8-bit and the
    // result is premultiplied, since FPImage carries straight alpha.
    constructor CreateFromFPImage(AImage: TFPCustomImage);
    destructor Destroy; override;

    procedure Assign(AImage: TFPCustomImage);

    procedure Clear(AColor: TwgColor);
    procedure PutPixel(X, Y: Integer; AColor: TwgColor); inline;
    function  GetPixel(X, Y: Integer): TwgColor;

    // Convert straight alpha to premultiplied in place (and back). Loading from
    // FPImage already premultiplies; use these when you supplied raw memory.
    procedure Premultiply;
    procedure Unpremultiply;
    // Declare that every pixel is opaque, so backends can skip blending.
    procedure SetOpaque(AValue: Boolean);

    property Data: PByte read FData;
    property Stride: Integer read FStride;
    property HasAlpha: Boolean read FHasAlpha;
  end;

  { TwgAlphaImage — a CPU coverage bitmap, one byte per pixel (sfA8).

    What a glyph atlas page is. Deliberately a separate, small class rather than
    a mode of TwgImage: the colour accessors would be meaningless here, and
    keeping it distinct means a backend that receives one knows to take its
    colour from the vertex. The GL canvas uploads these as R8 textures through
    the ordinary IwgPixelSurface path; the software canvas samples them directly.
    That is what lets one FreeType atlas serve both backends. }

  TwgAlphaImage = class(TwgSurfaceObject, IwgPixelSurface)
  private
    FData: PByte;
    FWidth: Integer;
    FHeight: Integer;
    FStride: Integer;
    FLocked: Boolean;
  protected
    function GetSurfaceWidth: Integer; override;
    function GetSurfaceHeight: Integer; override;
    function GetSurfaceFormat: TwgSurfaceFormat; override;

    function LockPixels(out AData: PByte; out AStride: Integer): Boolean;
    procedure UnlockPixels;
  public
    // Zero-filled (fully transparent).
    constructor Create(AWidth, AHeight: Integer);
    destructor Destroy; override;

    procedure Clear;
    procedure PutCoverage(X, Y: Integer; AValue: Byte); inline;
    function  GetCoverage(X, Y: Integer): Byte;
    // Copy an 8-bit coverage bitmap into the sub-rectangle at (AX, AY).
    // ASrcStride may be negative for a bottom-up source, as FreeType allows.
    procedure CopyCoverage(AX, AY, AWidth, AHeight: Integer; ASrc: PByte;
      ASrcStride: Integer);

    property Data: PByte read FData;
    property Stride: Integer read FStride;
  end;

{ --- colour helpers --- }

function wgARGB(A, R, G, B: Byte): TwgColor; inline;   // explicit alpha

function wgRGB(R, G, B: Byte): TwgColor; inline;       // opaque (A = 255)
function wgFPColorToColor(const AColor: TFPColor): TwgColor; inline;

function wgAlphaOf(AColor: TwgColor): Byte; inline;
function wgRedOf(AColor: TwgColor): Byte; inline;
function wgGreenOf(AColor: TwgColor): Byte; inline;
function wgBlueOf(AColor: TwgColor): Byte; inline;

// Scale wgRGB by the colour's own alpha (straight -> premultiplied) and back.
function wgPremultiply(AColor: TwgColor): TwgColor;
function wgUnpremultiply(AColor: TwgColor): TwgColor;
// Replace the alpha channel, scaling wgRGB to keep the result premultiplied.
function wgColorWithAlpha(AColor: TwgColor; AAlpha: Byte): TwgColor;

implementation

function wgSurfaceFormatBytes(AFormat: TwgSurfaceFormat): Integer;
begin
  if AFormat = sfA8 then
    Result := 1
  else
    Result := 4;
end;

{ --- colour helpers --- }

function wgARGB(A, R, G, B: Byte): TwgColor;
begin
  Result := (TwgColor(A) shl 24) or (TwgColor(R) shl 16) or
            (TwgColor(G) shl 8) or TwgColor(B);
end;

function wgRGB(R, G, B: Byte): TwgColor;
begin
  Result := $FF000000 or (TwgColor(R) shl 16) or
            (TwgColor(G) shl 8) or TwgColor(B);
end;

function wgFPColorToColor(const AColor: TFPColor): TwgColor;
begin
  // FPColor channels are 16-bit; take the high byte of each.
  Result := wgARGB(AColor.alpha shr 8, AColor.red shr 8,
                 AColor.green shr 8, AColor.blue shr 8);
end;

function wgAlphaOf(AColor: TwgColor): Byte;
begin
  Result := (AColor shr 24) and $FF;
end;

function wgRedOf(AColor: TwgColor): Byte;
begin
  Result := (AColor shr 16) and $FF;
end;

function wgGreenOf(AColor: TwgColor): Byte;
begin
  Result := (AColor shr 8) and $FF;
end;

function wgBlueOf(AColor: TwgColor): Byte;
begin
  Result := AColor and $FF;
end;

function wgPremultiply(AColor: TwgColor): TwgColor;
var
  a: Cardinal;
begin
  a := (AColor shr 24) and $FF;
  if a = $FF then
    Exit(AColor);
  if a = 0 then
    Exit(0);
  // +127 biases toward round-to-nearest rather than truncation.
  Result := (AColor and $FF000000)
    or ((((AColor shr 16) and $FF) * a + 127) div 255) shl 16
    or ((((AColor shr 8) and $FF) * a + 127) div 255) shl 8
    or (((AColor and $FF) * a + 127) div 255);
end;

function wgUnpremultiply(AColor: TwgColor): TwgColor;
var
  a: Cardinal;

  function Up(AChannel: Cardinal): Cardinal; inline;
  begin
    Result := (AChannel * 255 + (a div 2)) div a;
    if Result > 255 then
      Result := 255;
  end;

begin
  a := (AColor shr 24) and $FF;
  if (a = $FF) or (a = 0) then
    Exit(AColor);
  Result := (AColor and $FF000000)
    or Up((AColor shr 16) and $FF) shl 16
    or Up((AColor shr 8) and $FF) shl 8
    or Up(AColor and $FF);
end;

function wgColorWithAlpha(AColor: TwgColor; AAlpha: Byte): TwgColor;
begin
  // Take the colour back to straight alpha, swap in the new one, re-premultiply.
  Result := wgPremultiply((wgUnpremultiply(AColor) and $00FFFFFF)
    or (TwgColor(AAlpha) shl 24));
end;

{ TwgSurfaceObject }

var
  GNextGeneration: QWord = 1;

constructor TwgSurfaceObject.Create;
begin
  inherited Create;
  Changed;
end;

function TwgSurfaceObject._AddRef: LongInt; cdecl;
begin
  // No-op refcounting: surfaces are owned and freed by their creator, matching
  // the convention wayland_core uses for protocol objects. Holding an IwgSurface
  // must not keep the object alive, nor free it at scope exit.
  Result := 1;
end;

function TwgSurfaceObject._Release: LongInt; cdecl;
begin
  Result := 1;
end;

function TwgSurfaceObject.GetSurfaceHasAlpha: Boolean;
begin
  Result := True;
end;

function TwgSurfaceObject.GetSurfaceFormat: TwgSurfaceFormat;
begin
  Result := sfARGB32;
end;

function TwgSurfaceObject.GetSurfaceGeneration: QWord;
begin
  Result := FGeneration;
end;

procedure TwgSurfaceObject.Changed;
begin
  // Process-wide and monotonic, so a generation is never reused even across
  // different surfaces — a stale cache entry can never look current.
  Inc(GNextGeneration);
  FGeneration := GNextGeneration;
end;

{ TwgImage }

constructor TwgImage.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  if (AWidth <= 0) or (AHeight <= 0) then
    raise EwgSurface.CreateFmt('TwgImage: invalid size %dx%d', [AWidth, AHeight]);
  FWidth := AWidth;
  FHeight := AHeight;
  FStride := AWidth * 4;
  FData := GetMem(PtrUInt(FStride) * PtrUInt(FHeight));
  FillChar(FData^, PtrUInt(FStride) * PtrUInt(FHeight), 0);
  FOwnsData := True;
  FHasAlpha := True;
end;

constructor TwgImage.CreateFromMemory(AData: Pointer; AWidth, AHeight: Integer;
  AStride: Integer; ACopy: Boolean);
var
  lSize: PtrUInt;
begin
  inherited Create;
  if (AWidth <= 0) or (AHeight <= 0) then
    raise EwgSurface.CreateFmt('TwgImage: invalid size %dx%d', [AWidth, AHeight]);
  if AData = nil then
    raise EwgSurface.Create('TwgImage: nil source data');
  FWidth := AWidth;
  FHeight := AHeight;
  if AStride > 0 then
    FStride := AStride
  else
    FStride := AWidth * 4;
  FHasAlpha := True;
  if ACopy then
  begin
    lSize := PtrUInt(FStride) * PtrUInt(FHeight);
    FData := GetMem(lSize);
    Move(AData^, FData^, lSize);
    FOwnsData := True;
  end
  else
  begin
    FData := AData;
    FOwnsData := False;
  end;
end;

constructor TwgImage.CreateFromFPImage(AImage: TFPCustomImage);
begin
  if AImage = nil then
    raise EwgSurface.Create('TwgImage: nil source image');
  Create(AImage.Width, AImage.Height);
  Assign(AImage);
end;

destructor TwgImage.Destroy;
begin
  if FOwnsData and (FData <> nil) then
    FreeMem(FData);
  FData := nil;
  inherited Destroy;
end;

function TwgImage.RowPtr(Y: Integer): PwgColor;
begin
  Result := PwgColor(FData + Y * FStride);
end;

function TwgImage.GetSurfaceWidth: Integer;
begin
  Result := FWidth;
end;

function TwgImage.GetSurfaceHeight: Integer;
begin
  Result := FHeight;
end;

function TwgImage.GetSurfaceHasAlpha: Boolean;
begin
  Result := FHasAlpha;
end;

function TwgImage.LockPixels(out AData: PByte; out AStride: Integer): Boolean;
begin
  if FLocked then
    raise EInvalidOperation.Create('TwgImage: pixels are already locked');
  FLocked := True;
  AData := FData;
  AStride := FStride;
  Result := FData <> nil;
end;

procedure TwgImage.UnlockPixels;
begin
  FLocked := False;
end;

procedure TwgImage.Assign(AImage: TFPCustomImage);
var
  x, y, w, h: Integer;
  p: PwgColor;
begin
  if AImage = nil then
    Exit;
  w := AImage.Width;
  if w > FWidth then w := FWidth;
  h := AImage.Height;
  if h > FHeight then h := FHeight;
  for y := 0 to h - 1 do
  begin
    p := RowPtr(y);
    for x := 0 to w - 1 do
      // FPImage carries straight alpha; surfaces are premultiplied.
      p[x] := wgPremultiply(wgFPColorToColor(AImage.Colors[x, y]));
  end;
  Changed;
end;

procedure TwgImage.Clear(AColor: TwgColor);
var
  x, y: Integer;
  p: PwgColor;
begin
  for y := 0 to FHeight - 1 do
  begin
    p := RowPtr(y);
    for x := 0 to FWidth - 1 do
      p[x] := AColor;
  end;
  Changed;
end;

procedure TwgImage.PutPixel(X, Y: Integer; AColor: TwgColor);
begin
  if (X < 0) or (Y < 0) or (X >= FWidth) or (Y >= FHeight) then
    Exit;
  RowPtr(Y)[X] := AColor;
end;

function TwgImage.GetPixel(X, Y: Integer): TwgColor;
begin
  if (X < 0) or (Y < 0) or (X >= FWidth) or (Y >= FHeight) then
    Exit(0);
  Result := RowPtr(Y)[X];
end;

procedure TwgImage.Premultiply;
var
  x, y: Integer;
  p: PwgColor;
begin
  for y := 0 to FHeight - 1 do
  begin
    p := RowPtr(y);
    for x := 0 to FWidth - 1 do
      p[x] := wgPremultiply(p[x]);
  end;
  Changed;
end;

procedure TwgImage.Unpremultiply;
var
  x, y: Integer;
  p: PwgColor;
begin
  for y := 0 to FHeight - 1 do
  begin
    p := RowPtr(y);
    for x := 0 to FWidth - 1 do
      p[x] := wgUnpremultiply(p[x]);
  end;
  Changed;
end;

procedure TwgImage.SetOpaque(AValue: Boolean);
begin
  if FHasAlpha = not AValue then
    Exit;
  FHasAlpha := not AValue;
  Changed;
end;

{ TwgAlphaImage }

constructor TwgAlphaImage.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  if (AWidth <= 0) or (AHeight <= 0) then
    raise EwgSurface.CreateFmt('TwgAlphaImage: invalid size %dx%d',
      [AWidth, AHeight]);
  FWidth := AWidth;
  FHeight := AHeight;
  FStride := AWidth;
  FData := GetMem(PtrUInt(FStride) * PtrUInt(FHeight));
  FillChar(FData^, PtrUInt(FStride) * PtrUInt(FHeight), 0);
end;

destructor TwgAlphaImage.Destroy;
begin
  if FData <> nil then
    FreeMem(FData);
  FData := nil;
  inherited Destroy;
end;

function TwgAlphaImage.GetSurfaceWidth: Integer;
begin
  Result := FWidth;
end;

function TwgAlphaImage.GetSurfaceHeight: Integer;
begin
  Result := FHeight;
end;

function TwgAlphaImage.GetSurfaceFormat: TwgSurfaceFormat;
begin
  Result := sfA8;
end;

function TwgAlphaImage.LockPixels(out AData: PByte; out AStride: Integer): Boolean;
begin
  if FLocked then
    raise EwgSurface.Create('TwgAlphaImage: pixels are already locked');
  FLocked := True;
  AData := FData;
  AStride := FStride;
  Result := FData <> nil;
end;

procedure TwgAlphaImage.UnlockPixels;
begin
  FLocked := False;
end;

procedure TwgAlphaImage.Clear;
begin
  FillChar(FData^, PtrUInt(FStride) * PtrUInt(FHeight), 0);
  Changed;
end;

procedure TwgAlphaImage.PutCoverage(X, Y: Integer; AValue: Byte);
begin
  if (X < 0) or (Y < 0) or (X >= FWidth) or (Y >= FHeight) then
    Exit;
  (FData + PtrUInt(Y) * PtrUInt(FStride) + PtrUInt(X))^ := AValue;
end;

function TwgAlphaImage.GetCoverage(X, Y: Integer): Byte;
begin
  if (X < 0) or (Y < 0) or (X >= FWidth) or (Y >= FHeight) then
    Exit(0);
  Result := (FData + PtrUInt(Y) * PtrUInt(FStride) + PtrUInt(X))^;
end;

procedure TwgAlphaImage.CopyCoverage(AX, AY, AWidth, AHeight: Integer;
  ASrc: PByte; ASrcStride: Integer);
var
  y: Integer;
begin
  if (ASrc = nil) or (AWidth <= 0) or (AHeight <= 0) then
    Exit;
  // Callers are the atlas, which has already reserved a fitting rectangle;
  // clamp anyway so a bad glyph cannot scribble outside the page.
  if (AX < 0) or (AY < 0) or (AX + AWidth > FWidth) or (AY + AHeight > FHeight) then
    raise EwgSurface.CreateFmt(
      'TwgAlphaImage: %dx%d at (%d,%d) does not fit a %dx%d page',
      [AWidth, AHeight, AX, AY, FWidth, FHeight]);
  for y := 0 to AHeight - 1 do
    Move((ASrc + PtrInt(y) * ASrcStride)^,
         (FData + PtrUInt(AY + y) * PtrUInt(FStride) + PtrUInt(AX))^, AWidth);
  Changed;
end;

end.
