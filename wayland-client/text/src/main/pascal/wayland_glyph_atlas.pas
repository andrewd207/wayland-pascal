// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wayland_glyph_atlas — FreeType text rendering for the accelerated canvas.

  TGlyphAtlas is an IGlyphSource: give it a font file and a pixel size and it
  rasterises glyphs on demand into a coverage atlas, handing the canvas back UV
  rectangles. The canvas then draws text as ordinary textured quads — text costs
  no more than any other blit, and a whole run of glyphs in one page becomes one
  draw call.

  BACKEND-AGNOSTIC ON PURPOSE. Pages are plain CPU TWaylandAlphaImage surfaces
  (sfA8), not GPU textures, which is why this module sits beside the GL one
  rather than inside it. The GL canvas picks them up through its ordinary
  IPixelSurface texture cache — seeing sfA8, it allocates an R8 texture — while
  the software canvas samples the same bytes directly. One atlas, both backends,
  and no atlas-specific code in either. It does link libfreetype, so it is its
  own module and stays out of the RTL-only stack's way.

  PACKING is a shelf allocator: glyphs are laid down left to right on a row
  whose height is that of the tallest glyph placed on it; when a glyph will not
  fit, a new shelf starts below. That is a poor fit for wildly varying sizes but
  close to optimal for a single font at a single size, which is the case that
  matters, and it needs no per-glyph bookkeeping to free.

  GROWTH: when a page fills, the atlas allocates a new, larger one and starts
  over on it — existing glyphs keep pointing at the old page, which stays alive.
  Nothing is ever evicted, so a TGlyphInfo handed out earlier never dangles. For
  a UI that is the right trade; a text editor cycling through thousands of CJK
  glyphs would want an LRU instead.

  ONE FACE PER ATLAS, at one size. Bold, italic and other sizes are separate
  TGlyphAtlas instances — which is also how they end up as separate batches.

  A shared FreeType library handle is refcounted across atlases, so opening ten
  fonts does not initialise FreeType ten times. }
unit wayland_glyph_atlas;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, ctypes, freetype_fpc,
  wayland_surface, wayland_accel_canvas;

type
  EGlyphAtlas = class(Exception);

  { TGlyphAtlas }

  TGlyphAtlas = class(TInterfacedObject, IGlyphSource)
  private
    type
      TGlyphEntry = record
        GlyphIndex: LongWord;
        Valid: Boolean;
        Page: Integer;         // index into FPages
        U0, V0, U1, V1: Single;
        Width, Height: Single;
        BearingX, BearingY: Single;
        Advance: Single;
      end;
  private
    FFace: FT_Face;
    FOwnsFace: Boolean;
    FPixelSize: Integer;
    FHasKerning: Boolean;

    FAscent: Single;
    FDescent: Single;
    FLineHeight: Single;

    FPages: array of TWaylandAlphaImage;
    FPageSize: Integer;
    // shelf allocator state for the current (last) page
    FPenX: Integer;
    FShelfY: Integer;
    FShelfHeight: Integer;

    // Glyph index -> entry. A plain open-addressed map keyed on the glyph
    // index; fonts have far fewer glyphs than the code point space, so this
    // stays small and avoids a generic container dependency.
    FEntries: array of TGlyphEntry;
    FEntryCount: Integer;

    function  FindEntry(AGlyphIndex: LongWord; out AIndex: Integer): Boolean;
    procedure StoreEntry(const AEntry: TGlyphEntry);
    function  NewPage: Integer;
    // Reserve AWidth x AHeight in the current page, growing if needed.
    procedure Allocate(AWidth, AHeight: Integer; out APage, AX, AY: Integer);
    function  Rasterise(AGlyphIndex: LongWord; out AEntry: TGlyphEntry): Boolean;
    procedure ReadFaceMetrics;

    function _AddRef: LongInt; cdecl;
    function _Release: LongInt; cdecl;
  protected
    { IGlyphSource }
    function GetAscent: Single;
    function GetDescent: Single;
    function GetLineHeight: Single;
    function GetGlyphIndex(ACodePoint: LongWord): LongWord;
    function GetGlyph(AGlyphIndex: LongWord; out AGlyph: TGlyphInfo): Boolean;
    function GetKerning(ALeftIndex, ARightIndex: LongWord): Single;
  public
    // Open a font file at APixelSize pixels per em. AFaceIndex selects a face
    // within a collection (.ttc); 0 for an ordinary .ttf/.otf.
    constructor Create(const AFileName: String; APixelSize: Integer;
      AFaceIndex: Integer = 0);
    // Same, from an in-memory font. The buffer must outlive the atlas —
    // FreeType reads from it lazily rather than copying.
    constructor CreateFromMemory(AData: Pointer; ASize: Integer;
      APixelSize: Integer; AFaceIndex: Integer = 0);
    destructor Destroy; override;

    // Rasterise a run up front, so the first frame that draws it does not
    // stall uploading glyphs. Purely an optimisation.
    procedure Prewarm(const AText: String);

    property PixelSize: Integer read FPixelSize;
    property Ascent: Single read FAscent;
    property Descent: Single read FDescent;
    property LineHeight: Single read FLineHeight;
    // Number of texture pages currently allocated; > 1 means the atlas grew.
    function PageCount: Integer;
    function Page(AIndex: Integer): TWaylandAlphaImage;
  end;

// The shared FreeType library handle, initialised on first use.
function SharedFTLibrary: FT_Library;

implementation

const
  // Starting page edge. Doubles each time the atlas grows.
  InitialPageSize = 512;
  MaxPageSize = 4096;
  // Transparent gutter between glyphs, so linear filtering at a glyph's edge
  // cannot pick up its neighbour.
  GlyphPadding = 1;

var
  GLibrary: FT_Library = nil;
  GLibraryRefs: Integer = 0;

function SharedFTLibrary: FT_Library;
begin
  if GLibrary = nil then
    FTCheck(FT_Init_FreeType(@GLibrary), 'FT_Init_FreeType');
  Result := GLibrary;
end;

procedure RetainFTLibrary;
begin
  SharedFTLibrary;
  Inc(GLibraryRefs);
end;

procedure ReleaseFTLibrary;
begin
  Dec(GLibraryRefs);
  if (GLibraryRefs <= 0) and (GLibrary <> nil) then
  begin
    FT_Done_FreeType(GLibrary);
    GLibrary := nil;
    GLibraryRefs := 0;
  end;
end;

{ TGlyphAtlas }

constructor TGlyphAtlas.Create(const AFileName: String; APixelSize: Integer;
  AFaceIndex: Integer);
begin
  inherited Create;
  if APixelSize <= 0 then
    raise EGlyphAtlas.CreateFmt('TGlyphAtlas: invalid pixel size %d', [APixelSize]);
  if not FileExists(AFileName) then
    raise EGlyphAtlas.CreateFmt('TGlyphAtlas: font file not found: %s', [AFileName]);

  RetainFTLibrary;
  FPixelSize := APixelSize;
  FPageSize := InitialPageSize;
  FOwnsFace := True;
  try
    FTCheck(FT_New_Face(GLibrary, PAnsiChar(AFileName), AFaceIndex, @FFace),
      'FT_New_Face(' + AFileName + ')');
    ReadFaceMetrics;
  except
    ReleaseFTLibrary;
    raise;
  end;
end;

constructor TGlyphAtlas.CreateFromMemory(AData: Pointer; ASize: Integer;
  APixelSize: Integer; AFaceIndex: Integer);
begin
  inherited Create;
  if APixelSize <= 0 then
    raise EGlyphAtlas.CreateFmt('TGlyphAtlas: invalid pixel size %d', [APixelSize]);
  if (AData = nil) or (ASize <= 0) then
    raise EGlyphAtlas.Create('TGlyphAtlas: empty font buffer');

  RetainFTLibrary;
  FPixelSize := APixelSize;
  FPageSize := InitialPageSize;
  FOwnsFace := True;
  try
    FTCheck(FT_New_Memory_Face(GLibrary, PFT_Byte(AData), ASize, AFaceIndex, @FFace),
      'FT_New_Memory_Face');
    ReadFaceMetrics;
  except
    ReleaseFTLibrary;
    raise;
  end;
end;

destructor TGlyphAtlas.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FPages) do
    FPages[i].Free;
  SetLength(FPages, 0);
  if FOwnsFace and (FFace <> nil) then
    FT_Done_Face(FFace);
  FFace := nil;
  ReleaseFTLibrary;
  inherited Destroy;
end;

procedure TGlyphAtlas.ReadFaceMetrics;
begin
  FTCheck(FT_Set_Pixel_Sizes(FFace, 0, FPixelSize), 'FT_Set_Pixel_Sizes');
  FHasKerning := (FFace^.face_flags and FT_FACE_FLAG_KERNING) <> 0;
  // Size metrics are 26.6 and already scaled to the pixel size. Descent is
  // negative in FreeType; IGlyphSource reports it as a positive distance.
  FAscent := From26Dot6(FFace^.size^.metrics.ascender);
  FDescent := -From26Dot6(FFace^.size^.metrics.descender);
  FLineHeight := From26Dot6(FFace^.size^.metrics.height);
  if FLineHeight <= 0 then
    FLineHeight := FAscent + FDescent;
end;

function TGlyphAtlas._AddRef: LongInt; cdecl;
begin
  // As elsewhere in the stack: the atlas is owned and freed by its creator,
  // so handing an IGlyphSource to a canvas must not affect its lifetime.
  Result := 1;
end;

function TGlyphAtlas._Release: LongInt; cdecl;
begin
  Result := 1;
end;

function TGlyphAtlas.PageCount: Integer;
begin
  Result := Length(FPages);
end;

function TGlyphAtlas.Page(AIndex: Integer): TWaylandAlphaImage;
begin
  Result := FPages[AIndex];
end;

function TGlyphAtlas.NewPage: Integer;
var
  lTex: TWaylandAlphaImage;
begin
  // A plain CPU coverage page. The GL backend uploads it as an R8 texture
  // through the ordinary IPixelSurface cache; the software backend samples it
  // directly. Neither needs atlas-specific code.
  lTex := TWaylandAlphaImage.Create(FPageSize, FPageSize);
  Result := Length(FPages);
  SetLength(FPages, Result + 1);
  FPages[Result] := lTex;
  FPenX := 0;
  FShelfY := 0;
  FShelfHeight := 0;
end;

procedure TGlyphAtlas.Allocate(AWidth, AHeight: Integer; out APage, AX, AY: Integer);
var
  lPad: Integer;
begin
  lPad := GlyphPadding;
  if Length(FPages) = 0 then
    NewPage;

  if (AWidth + 2 * lPad > FPageSize) or (AHeight + 2 * lPad > FPageSize) then
  begin
    // A single glyph larger than a page: grow until it fits, or give up.
    while (FPageSize < MaxPageSize) and
          ((AWidth + 2 * lPad > FPageSize) or (AHeight + 2 * lPad > FPageSize)) do
      FPageSize := FPageSize * 2;
    if (AWidth + 2 * lPad > FPageSize) or (AHeight + 2 * lPad > FPageSize) then
      raise EGlyphAtlas.CreateFmt(
        'glyph is %dx%d, larger than the maximum %dx%d atlas page',
        [AWidth, AHeight, MaxPageSize, MaxPageSize]);
    NewPage;
  end;

  // Start a new shelf if the glyph will not fit on this one.
  if FPenX + AWidth + 2 * lPad > FPageSize then
  begin
    FPenX := 0;
    FShelfY := FShelfY + FShelfHeight + lPad;
    FShelfHeight := 0;
  end;

  // Out of shelves: grow the page size and start a fresh page. Glyphs already
  // handed out keep referring to the old page, which stays alive.
  if FShelfY + AHeight + 2 * lPad > FPageSize then
  begin
    if FPageSize < MaxPageSize then
      FPageSize := FPageSize * 2;
    NewPage;
  end;

  APage := High(FPages);
  AX := FPenX + lPad;
  AY := FShelfY + lPad;
  FPenX := FPenX + AWidth + 2 * lPad;
  if AHeight > FShelfHeight then
    FShelfHeight := AHeight;
end;

function TGlyphAtlas.Rasterise(AGlyphIndex: LongWord; out AEntry: TGlyphEntry): Boolean;
var
  lSlot: FT_GlyphSlot;
  lBmp: FT_Bitmap;
  lPage, lX, lY, lW, lH: Integer;
  lSrc: PByte;
  lTex: TWaylandAlphaImage;
begin
  Result := False;
  FillChar(AEntry, SizeOf(AEntry), 0);
  AEntry.GlyphIndex := AGlyphIndex;

  if FT_Load_Glyph(FFace, AGlyphIndex, FT_LOAD_DEFAULT) <> FT_Err_Ok then
    Exit;
  lSlot := FFace^.glyph;
  if FT_Render_Glyph(lSlot, FT_RENDER_MODE_NORMAL) <> FT_Err_Ok then
    Exit;

  lBmp := lSlot^.bitmap;
  AEntry.Advance := From26Dot6(lSlot^.advance.x);
  AEntry.BearingX := lSlot^.bitmap_left;
  AEntry.BearingY := lSlot^.bitmap_top;
  AEntry.Valid := True;

  lW := Integer(lBmp.width);
  lH := Integer(lBmp.rows);
  if (lW <= 0) or (lH <= 0) or (lBmp.buffer = nil) then
  begin
    // A blank glyph (space): metrics only, no texture.
    AEntry.Page := -1;
    Exit(True);
  end;
  if lBmp.pixel_mode <> FT_PIXEL_MODE_GRAY then
    // Only 8-bit coverage is handled; a monochrome or colour glyph would need
    // expanding first. Report metrics and skip the image rather than
    // uploading garbage.
    Exit(True);

  Allocate(lW, lH, lPage, lX, lY);
  lTex := FPages[lPage];

  // CopyCoverage copies row by row, so FreeType's negative pitch (rows stored
  // bottom-up) needs no repacking: the source pointer is simply walked backwards.
  lSrc := lBmp.buffer;
  if lBmp.pitch < 0 then
    lSrc := lSrc + PtrInt(lH - 1) * lBmp.pitch;
  lTex.CopyCoverage(lX, lY, lW, lH, lSrc, lBmp.pitch);

  AEntry.Page := lPage;
  AEntry.Width := lW;
  AEntry.Height := lH;
  AEntry.U0 := lX / lTex.Width;
  AEntry.V0 := lY / lTex.Height;
  AEntry.U1 := (lX + lW) / lTex.Width;
  AEntry.V1 := (lY + lH) / lTex.Height;
  Result := True;
end;

function TGlyphAtlas.FindEntry(AGlyphIndex: LongWord; out AIndex: Integer): Boolean;
var
  i: Integer;
begin
  // Linear scan over a compact array. Glyph counts in use are small (a UI
  // typically touches a couple of hundred), and this keeps the cache dense.
  for i := 0 to FEntryCount - 1 do
    if FEntries[i].GlyphIndex = AGlyphIndex then
    begin
      AIndex := i;
      Exit(True);
    end;
  AIndex := -1;
  Result := False;
end;

procedure TGlyphAtlas.StoreEntry(const AEntry: TGlyphEntry);
begin
  if FEntryCount = Length(FEntries) then
    SetLength(FEntries, Length(FEntries) * 2 + 64);
  FEntries[FEntryCount] := AEntry;
  Inc(FEntryCount);
end;

{ IGlyphSource }

function TGlyphAtlas.GetAscent: Single;
begin
  Result := FAscent;
end;

function TGlyphAtlas.GetDescent: Single;
begin
  Result := FDescent;
end;

function TGlyphAtlas.GetLineHeight: Single;
begin
  Result := FLineHeight;
end;

function TGlyphAtlas.GetGlyphIndex(ACodePoint: LongWord): LongWord;
begin
  Result := FT_Get_Char_Index(FFace, ACodePoint);
end;

function TGlyphAtlas.GetGlyph(AGlyphIndex: LongWord; out AGlyph: TGlyphInfo): Boolean;
var
  lIdx: Integer;
  lEntry: TGlyphEntry;
begin
  FillChar(AGlyph, SizeOf(AGlyph), 0);
  AGlyph.Texture := nil;

  if not FindEntry(AGlyphIndex, lIdx) then
  begin
    if not Rasterise(AGlyphIndex, lEntry) then
    begin
      // Remember the failure too, so a missing glyph is not re-attempted on
      // every frame that draws it.
      FillChar(lEntry, SizeOf(lEntry), 0);
      lEntry.GlyphIndex := AGlyphIndex;
      lEntry.Page := -1;
      StoreEntry(lEntry);
      Exit(False);
    end;
    StoreEntry(lEntry);
    lIdx := FEntryCount - 1;
  end;

  lEntry := FEntries[lIdx];
  if not lEntry.Valid then
    Exit(False);

  AGlyph.Advance := lEntry.Advance;
  AGlyph.BearingX := lEntry.BearingX;
  AGlyph.BearingY := lEntry.BearingY;
  AGlyph.Width := lEntry.Width;
  AGlyph.Height := lEntry.Height;
  if lEntry.Page >= 0 then
  begin
    AGlyph.Texture := FPages[lEntry.Page];
    AGlyph.U0 := lEntry.U0;
    AGlyph.V0 := lEntry.V0;
    AGlyph.U1 := lEntry.U1;
    AGlyph.V1 := lEntry.V1;
  end;
  Result := True;
end;

function TGlyphAtlas.GetKerning(ALeftIndex, ARightIndex: LongWord): Single;
var
  lVec: FT_Vector;
begin
  Result := 0;
  if not FHasKerning then
    Exit;
  if (ALeftIndex = 0) or (ARightIndex = 0) then
    Exit;
  if FT_Get_Kerning(FFace, ALeftIndex, ARightIndex, FT_KERNING_DEFAULT,
       @lVec) <> FT_Err_Ok then
    Exit;
  Result := From26Dot6(lVec.x);
end;

procedure TGlyphAtlas.Prewarm(const AText: String);
var
  i: Integer;
  lInfo: TGlyphInfo;
begin
  // Byte-wise is enough: any lead byte of a multi-byte sequence maps to no
  // glyph and is simply skipped, while ASCII — the common prewarm case — is
  // covered exactly.
  for i := 1 to Length(AText) do
    GetGlyph(GetGlyphIndex(Byte(AText[i])), lInfo);
end;

end.
