// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wayland_surface — what it means to be a rectangle of pixels something else can
  draw FROM.

  A canvas needs to blit images; a canvas is itself an image once you have drawn
  into it; and a GPU canvas wants to blit from a texture without ever touching
  the CPU. ISurface is the common denominator: width, height, whether it has
  meaningful alpha, and a generation counter. Everything a canvas can use as a
  source implements it — TWaylandImage here, the software TWaylandCanvas, and
  the GL canvas's render target.

  Two refinements say HOW the pixels can be reached:

    IPixelSurface   — the pixels are CPU-addressable; hand back a pointer and a
                      stride. Any backend can consume this (a GPU backend
                      uploads it to a texture).
    ITextureSurface — the pixels already live in GPU memory; hand back the
                      native texture handle and the UV sub-rect occupied. A GPU
                      backend uses this directly and skips the upload entirely.

  A surface may implement both, one, or (for a pure GPU render target) only
  ITextureSurface. Consumers should prefer ITextureSurface and fall back.

  GENERATION is the cache key. Texture caches in a GPU backend hold an uploaded
  copy of an IPixelSurface; they re-upload only when Generation changes. Any
  mutation must call Changed. Generation is never reused within a process, so
  "same pointer, same generation" genuinely means "same pixels".

  LIFETIME: these interfaces do NOT own their implementor. Following the
  convention wayland_core established for protocol objects, implementors derive
  from TInterfacedObject but make _AddRef/_Release no-ops, so holding an
  ISurface does not keep the object alive and letting one go out of scope does
  not free it. Surfaces are freed explicitly by whoever created them.

  PIXEL FORMAT: one format, TCanvasColor — a host DWord 0xAARRGGBB, stored
  little-endian as bytes B,G,R,A. That is wl_shm ARGB8888/XRGB8888, and it is
  also GL_BGRA + GL_UNSIGNED_INT_8_8_8_8_REV, so an upload is a straight memcpy
  on desktop GL.

  ALPHA: surfaces carry PREMULTIPLIED alpha, because that is what both wl_shm
  and sane texture filtering want. Images decoded from PNG and friends arrive
  straight (non-premultiplied); TWaylandImage.Premultiply converts in place, and
  the FPImage constructors do it for you. }
unit wayland_surface;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, FPImage;

type
  ESurface = class(Exception);

  // 0xAARRGGBB as a host DWord (little-endian bytes B,G,R,A = wl_shm ARGB8888).
  TCanvasColor = type DWord;
  PCanvasColor = ^TCanvasColor;

  { ISurface }

  ISurface = interface
    ['{6C8F2A41-0D3B-4F52-9E7A-2B1C5D0E8A31}']
    function GetSurfaceWidth: Integer;
    function GetSurfaceHeight: Integer;
    function GetSurfaceHasAlpha: Boolean;
    function GetSurfaceGeneration: QWord;

    property Width: Integer read GetSurfaceWidth;
    property Height: Integer read GetSurfaceHeight;
    // False promises every pixel is opaque, letting a backend skip blending.
    property HasAlpha: Boolean read GetSurfaceHasAlpha;
    // Bumped on every content change; texture caches key on it.
    property Generation: QWord read GetSurfaceGeneration;
  end;

  { IPixelSurface — CPU-addressable pixels. }

  IPixelSurface = interface(ISurface)
    ['{A17E4D92-5C60-4B18-8F3D-7E9A0C2B6415}']
    // Hand back the top-left pixel and the byte stride between rows. Returns
    // False if the pixels cannot be reached right now. Every successful Lock
    // must be matched by an Unlock. Nesting is not allowed.
    function LockPixels(out AData: PByte; out AStride: Integer): Boolean;
    procedure UnlockPixels;
  end;

  { ITextureSurface — pixels already resident in GPU memory.

    The surface may occupy only part of its backing texture (an atlas page, or
    a power-of-two-padded upload), so the UV sub-rect is explicit. V0 > V1 is
    legal and means the texture is stored bottom-up, as GL render targets are. }

  ITextureSurface = interface(ISurface)
    ['{3F0B8E77-91A4-4D26-B5C8-1A6E42D9F083}']
    // Backend-native handle; a GL texture name for the GL backend.
    function GetTextureHandle: PtrUInt;
    // True when the texture holds single-channel coverage (a glyph atlas)
    // rather than colour — the backend then samples red as alpha.
    function GetTextureIsAlphaOnly: Boolean;
    procedure GetTextureUV(out AU0, AV0, AU1, AV1: Single);
  end;

  { TWaylandSurfaceObject — base for anything implementing ISurface.

    Supplies the generation counter and the no-op reference counting described
    in the unit header. }

  TWaylandSurfaceObject = class(TInterfacedObject, ISurface)
  private
    FGeneration: QWord;
  protected
    function _AddRef: LongInt; cdecl;
    function _Release: LongInt; cdecl;

    function GetSurfaceWidth: Integer; virtual; abstract;
    function GetSurfaceHeight: Integer; virtual; abstract;
    function GetSurfaceHasAlpha: Boolean; virtual;
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

  { TWaylandImage — a CPU-side ARGB32 image.

    Owns its pixel memory unless constructed with CreateFromMemory(..., False),
    in which case it wraps a caller-owned block that must outlive it. }

  TWaylandImage = class(TWaylandSurfaceObject, IPixelSurface)
  private
    FData: PByte;
    FWidth: Integer;
    FHeight: Integer;
    FStride: Integer;
    FOwnsData: Boolean;
    FHasAlpha: Boolean;
    FLocked: Boolean;
    function RowPtr(Y: Integer): PCanvasColor; inline;
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

    procedure Clear(AColor: TCanvasColor);
    procedure PutPixel(X, Y: Integer; AColor: TCanvasColor); inline;
    function  GetPixel(X, Y: Integer): TCanvasColor;

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

{ --- colour helpers --- }

function ARGB(A, R, G, B: Byte): TCanvasColor; inline;   // explicit alpha
function RGB(R, G, B: Byte): TCanvasColor; inline;       // opaque (A = 255)
function FPColorToCanvas(const AColor: TFPColor): TCanvasColor; inline;

function AlphaOf(AColor: TCanvasColor): Byte; inline;
function RedOf(AColor: TCanvasColor): Byte; inline;
function GreenOf(AColor: TCanvasColor): Byte; inline;
function BlueOf(AColor: TCanvasColor): Byte; inline;

// Scale RGB by the colour's own alpha (straight -> premultiplied) and back.
function PremultiplyColor(AColor: TCanvasColor): TCanvasColor;
function UnpremultiplyColor(AColor: TCanvasColor): TCanvasColor;
// Replace the alpha channel, scaling RGB to keep the result premultiplied.
function ColorWithAlpha(AColor: TCanvasColor; AAlpha: Byte): TCanvasColor;

implementation

{ --- colour helpers --- }

function ARGB(A, R, G, B: Byte): TCanvasColor;
begin
  Result := (TCanvasColor(A) shl 24) or (TCanvasColor(R) shl 16) or
            (TCanvasColor(G) shl 8) or TCanvasColor(B);
end;

function RGB(R, G, B: Byte): TCanvasColor;
begin
  Result := $FF000000 or (TCanvasColor(R) shl 16) or
            (TCanvasColor(G) shl 8) or TCanvasColor(B);
end;

function FPColorToCanvas(const AColor: TFPColor): TCanvasColor;
begin
  // FPColor channels are 16-bit; take the high byte of each.
  Result := ARGB(AColor.alpha shr 8, AColor.red shr 8,
                 AColor.green shr 8, AColor.blue shr 8);
end;

function AlphaOf(AColor: TCanvasColor): Byte;
begin
  Result := (AColor shr 24) and $FF;
end;

function RedOf(AColor: TCanvasColor): Byte;
begin
  Result := (AColor shr 16) and $FF;
end;

function GreenOf(AColor: TCanvasColor): Byte;
begin
  Result := (AColor shr 8) and $FF;
end;

function BlueOf(AColor: TCanvasColor): Byte;
begin
  Result := AColor and $FF;
end;

function PremultiplyColor(AColor: TCanvasColor): TCanvasColor;
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

function UnpremultiplyColor(AColor: TCanvasColor): TCanvasColor;
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

function ColorWithAlpha(AColor: TCanvasColor; AAlpha: Byte): TCanvasColor;
begin
  // Take the colour back to straight alpha, swap in the new one, re-premultiply.
  Result := PremultiplyColor((UnpremultiplyColor(AColor) and $00FFFFFF)
    or (TCanvasColor(AAlpha) shl 24));
end;

{ TWaylandSurfaceObject }

var
  GNextGeneration: QWord = 1;

constructor TWaylandSurfaceObject.Create;
begin
  inherited Create;
  Changed;
end;

function TWaylandSurfaceObject._AddRef: LongInt; cdecl;
begin
  // No-op refcounting: surfaces are owned and freed by their creator, matching
  // the convention wayland_core uses for protocol objects. Holding an ISurface
  // must not keep the object alive, nor free it at scope exit.
  Result := 1;
end;

function TWaylandSurfaceObject._Release: LongInt; cdecl;
begin
  Result := 1;
end;

function TWaylandSurfaceObject.GetSurfaceHasAlpha: Boolean;
begin
  Result := True;
end;

function TWaylandSurfaceObject.GetSurfaceGeneration: QWord;
begin
  Result := FGeneration;
end;

procedure TWaylandSurfaceObject.Changed;
begin
  // Process-wide and monotonic, so a generation is never reused even across
  // different surfaces — a stale cache entry can never look current.
  Inc(GNextGeneration);
  FGeneration := GNextGeneration;
end;

{ TWaylandImage }

constructor TWaylandImage.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  if (AWidth <= 0) or (AHeight <= 0) then
    raise ESurface.CreateFmt('TWaylandImage: invalid size %dx%d', [AWidth, AHeight]);
  FWidth := AWidth;
  FHeight := AHeight;
  FStride := AWidth * 4;
  FData := GetMem(PtrUInt(FStride) * PtrUInt(FHeight));
  FillChar(FData^, PtrUInt(FStride) * PtrUInt(FHeight), 0);
  FOwnsData := True;
  FHasAlpha := True;
end;

constructor TWaylandImage.CreateFromMemory(AData: Pointer; AWidth, AHeight: Integer;
  AStride: Integer; ACopy: Boolean);
var
  lSize: PtrUInt;
begin
  inherited Create;
  if (AWidth <= 0) or (AHeight <= 0) then
    raise ESurface.CreateFmt('TWaylandImage: invalid size %dx%d', [AWidth, AHeight]);
  if AData = nil then
    raise ESurface.Create('TWaylandImage: nil source data');
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

constructor TWaylandImage.CreateFromFPImage(AImage: TFPCustomImage);
begin
  if AImage = nil then
    raise ESurface.Create('TWaylandImage: nil source image');
  Create(AImage.Width, AImage.Height);
  Assign(AImage);
end;

destructor TWaylandImage.Destroy;
begin
  if FOwnsData and (FData <> nil) then
    FreeMem(FData);
  FData := nil;
  inherited Destroy;
end;

function TWaylandImage.RowPtr(Y: Integer): PCanvasColor;
begin
  Result := PCanvasColor(FData + Y * FStride);
end;

function TWaylandImage.GetSurfaceWidth: Integer;
begin
  Result := FWidth;
end;

function TWaylandImage.GetSurfaceHeight: Integer;
begin
  Result := FHeight;
end;

function TWaylandImage.GetSurfaceHasAlpha: Boolean;
begin
  Result := FHasAlpha;
end;

function TWaylandImage.LockPixels(out AData: PByte; out AStride: Integer): Boolean;
begin
  if FLocked then
    raise EInvalidOperation.Create('TWaylandImage: pixels are already locked');
  FLocked := True;
  AData := FData;
  AStride := FStride;
  Result := FData <> nil;
end;

procedure TWaylandImage.UnlockPixels;
begin
  FLocked := False;
end;

procedure TWaylandImage.Assign(AImage: TFPCustomImage);
var
  x, y, w, h: Integer;
  p: PCanvasColor;
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
      p[x] := PremultiplyColor(FPColorToCanvas(AImage.Colors[x, y]));
  end;
  Changed;
end;

procedure TWaylandImage.Clear(AColor: TCanvasColor);
var
  x, y: Integer;
  p: PCanvasColor;
begin
  for y := 0 to FHeight - 1 do
  begin
    p := RowPtr(y);
    for x := 0 to FWidth - 1 do
      p[x] := AColor;
  end;
  Changed;
end;

procedure TWaylandImage.PutPixel(X, Y: Integer; AColor: TCanvasColor);
begin
  if (X < 0) or (Y < 0) or (X >= FWidth) or (Y >= FHeight) then
    Exit;
  RowPtr(Y)[X] := AColor;
end;

function TWaylandImage.GetPixel(X, Y: Integer): TCanvasColor;
begin
  if (X < 0) or (Y < 0) or (X >= FWidth) or (Y >= FHeight) then
    Exit(0);
  Result := RowPtr(Y)[X];
end;

procedure TWaylandImage.Premultiply;
var
  x, y: Integer;
  p: PCanvasColor;
begin
  for y := 0 to FHeight - 1 do
  begin
    p := RowPtr(y);
    for x := 0 to FWidth - 1 do
      p[x] := PremultiplyColor(p[x]);
  end;
  Changed;
end;

procedure TWaylandImage.Unpremultiply;
var
  x, y: Integer;
  p: PCanvasColor;
begin
  for y := 0 to FHeight - 1 do
  begin
    p := RowPtr(y);
    for x := 0 to FWidth - 1 do
      p[x] := UnpremultiplyColor(p[x]);
  end;
  Changed;
end;

procedure TWaylandImage.SetOpaque(AValue: Boolean);
begin
  if FHasAlpha = not AValue then
    Exit;
  FHasAlpha := not AValue;
  Changed;
end;

end.
