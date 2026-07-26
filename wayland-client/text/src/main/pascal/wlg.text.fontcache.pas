// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.text.fontcache — ask for a font by description, get an IwgGlyphSource.

  TwgGlyphAtlas is deliberately low level: one face, one pixel size, opened from
  a FILE PATH. A widget toolkit wants to say "Sans, 11pt, bold" and not think
  about files, and it wants the same request from twenty widgets to produce ONE
  atlas rather than twenty. This unit is that bridge: fontconfig resolves the
  description to a file, and a cache keyed on the resolved request hands back a
  shared atlas.

  SCALE IS PART OF THE KEY, not an afterthought. Glyphs must be rasterised at
  the size they will actually occupy in device pixels, so on a 2x display an
  11pt font is a 2x-larger atlas — drawn through the scaled canvas transform it
  then lands at the right logical size, crisply. Caching on logical size alone
  would produce blurry text on HiDPI, so TwgFontDesc carries the scale and two
  requests differing only in scale are correctly different fonts.

  POINTS VS PIXELS: sizes are given in points and converted at 96 dpi, the
  convention Wayland desktops use, before the scale is applied. Pass a pixel
  size directly with SizePx if you would rather not go through points.

  LIFETIME: the cache owns every atlas it creates and frees them on Destroy.
  Callers hold IwgGlyphSource interfaces, which are the project's usual no-op
  refcounted kind, so holding one neither keeps the atlas alive nor frees it —
  the cache must outlive its users. A UI's cache normally lives as long as the
  application. }
unit wlg.text.fontcache;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math,
  wlg.canvas.base, wlg.text.atlas, fontconfig_fpc;

type
  EwgFontCache = class(Exception);

  TwgFontWeight = (fwLight, fwRegular, fwMedium, fwBold);
  TwgFontSlant  = (fsRoman, fsItalic, fsOblique);

  { TwgFontDesc — what a caller asks for. }
  TwgFontDesc = record
    Family: String;        // 'Sans', 'Monospace', 'DejaVu Serif', ...
    SizePt: Single;        // points; ignored when SizePx > 0
    SizePx: Integer;       // exact pixel size, overriding SizePt when > 0
    Weight: TwgFontWeight;
    Slant: TwgFontSlant;
    Scale: Single;         // output scale; 1.0 = 96dpi, 2.0 = HiDPI
  end;

  { TwgFontCache }

  TwgFontCache = class
  private
    type
      TEntry = record
        Key: String;
        Atlas: TwgGlyphAtlas;
      end;
  private
    FEntries: array of TEntry;
    FCount: Integer;
    FDefaultFamily: String;
    FDefaultSizePt: Single;
    FScale: Single;
    function  KeyOf(const ADesc: TwgFontDesc): String;
    function  Find(const AKey: String): TwgGlyphAtlas;
  public
    constructor Create;
    destructor Destroy; override;

    // Resolve and rasterise (or return the cached atlas). Raises EwgFontCache
    // if fontconfig cannot be reached or the chosen file will not open.
    function Get(const ADesc: TwgFontDesc): IwgGlyphSource;
    // Convenience over Get, using DefaultFamily/Scale for what is not given.
    function GetFont(const AFamily: String; ASizePt: Single;
      AWeight: TwgFontWeight = fwRegular;
      ASlant: TwgFontSlant = fsRoman): IwgGlyphSource;
    // The UI default font at ASizePt (or DefaultSizePt when <= 0).
    function DefaultFont(ASizePt: Single = 0): IwgGlyphSource;

    procedure Clear;

    // Applied to every request that does not set its own Scale. Changing it
    // does NOT invalidate the cache — old atlases stay valid for their own
    // scale, and new requests simply key differently.
    property Scale: Single read FScale write FScale;
    property DefaultFamily: String read FDefaultFamily write FDefaultFamily;
    property DefaultSizePt: Single read FDefaultSizePt write FDefaultSizePt;
    // Distinct atlases currently held.
    property Count: Integer read FCount;
  end;

// Build a description, filling in the usual defaults.
function wgFontDesc(const AFamily: String; ASizePt: Single;
  AWeight: TwgFontWeight = fwRegular; ASlant: TwgFontSlant = fsRoman;
  AScale: Single = 1.0): TwgFontDesc;

// Points -> pixels at 96 dpi, with the scale applied. Never returns 0.
function wgPointsToPixels(ASizePt, AScale: Single): Integer;

implementation

const
  // The dpi Wayland desktops assume before output scaling is applied; scaling
  // is expressed by the scale factor rather than by varying this.
  BaseDPI = 96.0;

function wgPointsToPixels(ASizePt, AScale: Single): Integer;
begin
  if ASizePt <= 0 then
    ASizePt := 10;
  if AScale <= 0 then
    AScale := 1;
  Result := Max(1, Round(ASizePt * AScale * BaseDPI / 72.0));
end;

function wgFontDesc(const AFamily: String; ASizePt: Single;
  AWeight: TwgFontWeight; ASlant: TwgFontSlant; AScale: Single): TwgFontDesc;
begin
  Result := Default(TwgFontDesc);
  Result.Family := AFamily;
  Result.SizePt := ASizePt;
  Result.SizePx := 0;
  Result.Weight := AWeight;
  Result.Slant := ASlant;
  Result.Scale := AScale;
end;

function FcWeightOf(AWeight: TwgFontWeight): Integer;
begin
  case AWeight of
    fwLight:  Result := FC_WEIGHT_LIGHT;
    fwMedium: Result := FC_WEIGHT_MEDIUM;
    fwBold:   Result := FC_WEIGHT_BOLD;
    else      Result := FC_WEIGHT_REGULAR;
  end;
end;

function FcSlantOf(ASlant: TwgFontSlant): Integer;
begin
  case ASlant of
    fsItalic:  Result := FC_SLANT_ITALIC;
    fsOblique: Result := FC_SLANT_OBLIQUE;
    else       Result := FC_SLANT_ROMAN;
  end;
end;

{ TwgFontCache }

constructor TwgFontCache.Create;
begin
  inherited Create;
  FScale := 1.0;
  FDefaultFamily := 'Sans';
  FDefaultSizePt := 10;
end;

destructor TwgFontCache.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TwgFontCache.Clear;
var
  i: Integer;
begin
  for i := 0 to FCount - 1 do
    FEntries[i].Atlas.Free;
  FCount := 0;
  SetLength(FEntries, 0);
end;

function TwgFontCache.KeyOf(const ADesc: TwgFontDesc): String;
var
  lPx: Integer;
begin
  if ADesc.SizePx > 0 then
    lPx := ADesc.SizePx
  else
    lPx := wgPointsToPixels(ADesc.SizePt, ADesc.Scale);
  // Keyed on the RESOLVED pixel size, so two descriptions that rasterise
  // identically — 11pt at 2x and 22pt at 1x — share one atlas.
  Result := Format('%s|%d|%d|%d', [LowerCase(ADesc.Family), lPx,
    Ord(ADesc.Weight), Ord(ADesc.Slant)]);
end;

function TwgFontCache.Find(const AKey: String): TwgGlyphAtlas;
var
  i: Integer;
begin
  for i := 0 to FCount - 1 do
    if FEntries[i].Key = AKey then
      Exit(FEntries[i].Atlas);
  Result := nil;
end;

function TwgFontCache.Get(const ADesc: TwgFontDesc): IwgGlyphSource;
var
  lKey: String;
  lAtlas: TwgGlyphAtlas;
  lMatch: TFontMatch;
  lDesc: TwgFontDesc;
  lPx: Integer;
begin
  lDesc := ADesc;
  if lDesc.Family = '' then
    lDesc.Family := FDefaultFamily;
  if lDesc.Scale <= 0 then
    lDesc.Scale := FScale;
  if (lDesc.SizePx <= 0) and (lDesc.SizePt <= 0) then
    lDesc.SizePt := FDefaultSizePt;

  lKey := KeyOf(lDesc);
  lAtlas := Find(lKey);
  if lAtlas <> nil then
    Exit(lAtlas);

  if not FontConfigAvailable then
    raise EwgFontCache.Create(
      'fontconfig is unavailable, so font families cannot be resolved');

  if lDesc.SizePx > 0 then
    lPx := lDesc.SizePx
  else
    lPx := wgPointsToPixels(lDesc.SizePt, lDesc.Scale);

  lMatch := MatchFont(lDesc.Family, FcWeightOf(lDesc.Weight),
    FcSlantOf(lDesc.Slant), lPx);
  if not lMatch.Found then
    raise EwgFontCache.CreateFmt('no font file matched "%s"', [lDesc.Family]);

  lAtlas := TwgGlyphAtlas.Create(lMatch.FileName, lPx, lMatch.FaceIndex);

  if FCount = Length(FEntries) then
    SetLength(FEntries, FCount * 2 + 8);
  FEntries[FCount].Key := lKey;
  FEntries[FCount].Atlas := lAtlas;
  Inc(FCount);
  Result := lAtlas;
end;

function TwgFontCache.GetFont(const AFamily: String; ASizePt: Single;
  AWeight: TwgFontWeight; ASlant: TwgFontSlant): IwgGlyphSource;
begin
  Result := Get(wgFontDesc(AFamily, ASizePt, AWeight, ASlant, FScale));
end;

function TwgFontCache.DefaultFont(ASizePt: Single): IwgGlyphSource;
begin
  if ASizePt <= 0 then
    ASizePt := FDefaultSizePt;
  Result := GetFont(FDefaultFamily, ASizePt);
end;

end.
