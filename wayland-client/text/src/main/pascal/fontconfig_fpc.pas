// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ fontconfig_fpc — a hand-written subset binding to fontconfig.

  Only what is needed to answer one question: given "Sans", bold, 11pt, which
  font FILE and face index should FreeType open? That is the whole gap between
  what a toolkit wants to say and what TwgGlyphAtlas accepts.

  Doing it properly matters more than it looks. "Sans", "Serif" and "Monospace"
  are generic aliases that only fontconfig can resolve; users retarget them, and
  distributions ship different defaults. A built-in table of guessed paths gets
  this wrong on any system that has been configured at all.

  The matching dance is fontconfig's prescribed one and every step is load
  bearing:

    FcPatternCreate / FcPatternAddString    say what you want
    FcConfigSubstitute (FcMatchPattern)     apply the user's rules and aliases
    FcDefaultSubstitute                     fill in defaults you did not set
    FcFontMatch                             pick the best real font

  Skipping the two substitute calls is the classic mistake: FcFontMatch would
  then match against the raw request, so "Sans" resolves to a font literally
  named Sans (usually nothing) instead of the user's configured sans-serif.

  Naming: like egl_fpc and freetype_fpc, this is a binding to a third-party C
  library and keeps that library's own names rather than the project's wg
  prefix. }
unit fontconfig_fpc;

{$mode ObjFPC}{$H+}
{$PACKRECORDS C}

interface

uses
  SysUtils, ctypes;

type
  EFontConfig = class(Exception);

  FcChar8  = cuchar;
  PFcChar8 = ^FcChar8;
  PPFcChar8 = ^PFcChar8;
  FcBool   = cint;

  FcConfig  = Pointer;
  FcPattern = Pointer;

  // FcResult
  FcResult = cint;

const
  FcResultMatch        = 0;
  FcResultNoMatch      = 1;
  FcResultTypeMismatch = 2;
  FcResultNoId         = 3;
  FcResultOutOfMemory  = 4;

  // FcMatchKind
  FcMatchPattern = 0;
  FcMatchFont    = 1;
  FcMatchScan    = 2;

  FcFalse = 0;
  FcTrue  = 1;

  // Pattern property names.
  FC_FAMILY     = 'family';
  FC_SLANT      = 'slant';
  FC_WEIGHT     = 'weight';
  FC_SIZE       = 'size';
  FC_PIXEL_SIZE = 'pixelsize';
  FC_FILE       = 'file';
  FC_INDEX      = 'index';

  // Weights, on fontconfig's own scale (not OS/2 units).
  FC_WEIGHT_LIGHT   = 50;
  FC_WEIGHT_REGULAR = 80;
  FC_WEIGHT_MEDIUM  = 100;
  FC_WEIGHT_BOLD    = 200;

  FC_SLANT_ROMAN   = 0;
  FC_SLANT_ITALIC  = 100;
  FC_SLANT_OBLIQUE = 110;

  LIB_FONTCONFIG = 'libfontconfig.so.1';

function FcInitLoadConfigAndFonts: FcConfig; cdecl; external LIB_FONTCONFIG;

function FcPatternCreate: FcPattern; cdecl; external LIB_FONTCONFIG;
procedure FcPatternDestroy(p: FcPattern); cdecl; external LIB_FONTCONFIG;
function FcPatternAddString(p: FcPattern; obj: PAnsiChar; s: PFcChar8): FcBool; cdecl; external LIB_FONTCONFIG;
function FcPatternAddInteger(p: FcPattern; obj: PAnsiChar; i: cint): FcBool; cdecl; external LIB_FONTCONFIG;
function FcPatternAddDouble(p: FcPattern; obj: PAnsiChar; d: cdouble): FcBool; cdecl; external LIB_FONTCONFIG;
function FcPatternGetString(p: FcPattern; obj: PAnsiChar; n: cint; s: PPFcChar8): FcResult; cdecl; external LIB_FONTCONFIG;
function FcPatternGetInteger(p: FcPattern; obj: PAnsiChar; n: cint; i: pcint): FcResult; cdecl; external LIB_FONTCONFIG;

function FcConfigSubstitute(config: FcConfig; p: FcPattern; kind: cint): FcBool; cdecl; external LIB_FONTCONFIG;
procedure FcDefaultSubstitute(p: FcPattern); cdecl; external LIB_FONTCONFIG;
function FcFontMatch(config: FcConfig; p: FcPattern; out res: FcResult): FcPattern; cdecl; external LIB_FONTCONFIG;

type
  { TFontMatch — the answer, in the terms FreeType needs. }
  TFontMatch = record
    FileName: String;
    FaceIndex: Integer;
    // What fontconfig actually chose, which may differ from what was asked
    // for — useful for diagnostics and for reporting the real family.
    Family: String;
    Found: Boolean;
  end;

{ Resolve a family name (or generic alias: Sans, Serif, Monospace) plus style
  to a concrete font file. AWeight/ASlant use the FC_WEIGHT_* / FC_SLANT_*
  scales. APixelSize only influences selection among bitmap strikes; scalable
  fonts ignore it, so passing 0 is fine.

  Never raises for "no such family" — fontconfig always substitutes something,
  which is the behaviour you want in a UI. Found is False only if fontconfig
  itself failed. }
function MatchFont(const AFamily: String; AWeight: Integer = FC_WEIGHT_REGULAR;
  ASlant: Integer = FC_SLANT_ROMAN; APixelSize: Integer = 0): TFontMatch;

// True once fontconfig has been initialised successfully (done lazily).
function FontConfigAvailable: Boolean;

implementation

var
  GConfig: FcConfig = nil;
  GTried: Boolean = False;

function EnsureConfig: FcConfig;
begin
  if not GTried then
  begin
    GTried := True;
    // Loading the whole font set is what makes matching accurate; it is done
    // once per process and cached by fontconfig itself between runs.
    GConfig := FcInitLoadConfigAndFonts;
  end;
  Result := GConfig;
end;

function FontConfigAvailable: Boolean;
begin
  Result := EnsureConfig <> nil;
end;

function MatchFont(const AFamily: String; AWeight: Integer; ASlant: Integer;
  APixelSize: Integer): TFontMatch;
var
  lConfig: FcConfig;
  lPat, lMatched: FcPattern;
  lRes: FcResult;
  lStr: PFcChar8;
  lIdx: cint;
begin
  Result := Default(TFontMatch);
  Result.FaceIndex := 0;

  lConfig := EnsureConfig;
  if lConfig = nil then
    raise EFontConfig.Create('fontconfig could not be initialised');

  lPat := FcPatternCreate;
  if lPat = nil then
    raise EFontConfig.Create('FcPatternCreate failed');
  try
    if AFamily <> '' then
      FcPatternAddString(lPat, FC_FAMILY, PFcChar8(PAnsiChar(AFamily)));
    FcPatternAddInteger(lPat, FC_WEIGHT, AWeight);
    FcPatternAddInteger(lPat, FC_SLANT, ASlant);
    if APixelSize > 0 then
      FcPatternAddDouble(lPat, FC_PIXEL_SIZE, APixelSize);

    // Both of these before FcFontMatch, or generic aliases never resolve.
    FcConfigSubstitute(lConfig, lPat, FcMatchPattern);
    FcDefaultSubstitute(lPat);

    lMatched := FcFontMatch(lConfig, lPat, lRes);
    if (lMatched = nil) or (lRes <> FcResultMatch) then
      Exit;
    try
      if FcPatternGetString(lMatched, FC_FILE, 0, @lStr) = FcResultMatch then
      begin
        Result.FileName := String(PAnsiChar(lStr));
        Result.Found := Result.FileName <> '';
      end;
      if FcPatternGetInteger(lMatched, FC_INDEX, 0, @lIdx) = FcResultMatch then
        Result.FaceIndex := lIdx;
      if FcPatternGetString(lMatched, FC_FAMILY, 0, @lStr) = FcResultMatch then
        Result.Family := String(PAnsiChar(lStr));
    finally
      FcPatternDestroy(lMatched);
    end;
  finally
    FcPatternDestroy(lPat);
  end;
end;

end.
