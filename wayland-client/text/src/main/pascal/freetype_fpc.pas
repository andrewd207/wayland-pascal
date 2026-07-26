// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ freetype_fpc — a hand-written subset binding to FreeType 2.

  Only what a glyph-atlas rasteriser needs: open a face from a file or a memory
  block, set a pixel size, look up and load a glyph, render it to an 8-bit
  coverage bitmap, and read its metrics and kerning. Outlines, colour layers,
  the cache subsystem, the stroker and the module API are deliberately absent.

  The record layouts mirror freetype/freetype.h, freetype/ftimage.h and
  freetype/fttypes.h. FreeType allocates every one of these itself and hands
  back a pointer, so what matters is that FIELD OFFSETS match; the private tail
  members are declared as opaque pointers. FT_Pos / FT_Long / FT_Fixed /
  FT_F26Dot6 are all C `signed long` — 64-bit on LP64 — hence PtrInt here
  rather than LongInt, which would silently shift every following field.

  Fixed-point: FT_Pos values in glyph and size metrics are 26.6 (units of 1/64
  pixel); FT_Fixed values are 16.16. Div64/To64 below convert. }
unit freetype_fpc;

{$mode ObjFPC}{$H+}
{$PACKRECORDS C}

interface

uses
  SysUtils, ctypes;

type
  EFreeType = class(Exception)
  private
    FErrorCode: Integer;
  public
    constructor Create(const AWhat: String; ACode: Integer);
    property ErrorCode: Integer read FErrorCode;
  end;

  // --- scalars (fttypes.h / ftimage.h) ---
  FT_Bool     = cuchar;
  FT_Byte     = cuchar;
  PFT_Byte    = ^FT_Byte;
  FT_String   = AnsiChar;
  PFT_String  = ^FT_String;
  FT_Short    = cshort;
  FT_UShort   = cushort;
  FT_Int      = cint;
  FT_UInt     = cuint;
  FT_Long     = clong;      // signed long: 64-bit on LP64
  FT_ULong    = culong;
  FT_F26Dot6  = clong;      // 26.6 fixed point
  FT_Fixed    = clong;      // 16.16 fixed point
  FT_Pos      = clong;      // 26.6 in metrics, integer in some contexts
  FT_Error    = cint;

  PFT_UInt  = ^FT_UInt;
  PFT_Int   = ^FT_Int;
  PFT_Fixed = ^FT_Fixed;

  // --- opaque handles ---
  FT_Library = Pointer;
  PFT_Library = ^FT_Library;
  FT_Driver  = Pointer;
  FT_Memory  = Pointer;
  FT_Stream  = Pointer;
  FT_CharMap = Pointer;
  PFT_CharMap = ^FT_CharMap;
  FT_SubGlyph = Pointer;
  FT_Bitmap_Size_Ptr = Pointer;

  FT_Generic = record
    data:      Pointer;
    finalizer: Pointer;
  end;

  FT_ListRec = record
    head: Pointer;
    tail: Pointer;
  end;

  FT_Vector = record
    x: FT_Pos;
    y: FT_Pos;
  end;
  PFT_Vector = ^FT_Vector;

  FT_BBox = record
    xMin, yMin: FT_Pos;
    xMax, yMax: FT_Pos;
  end;

  { FT_Bitmap — the rendered coverage bitmap.

    pitch is the byte stride and may be NEGATIVE, meaning the rows are stored
    bottom-up; buffer then points at the LAST row. Consumers must honour the
    sign rather than assuming a positive stride. With pixel_mode = FT_PIXEL_MODE_GRAY
    each byte is a coverage value scaled to num_grays (256 in practice). }
  FT_Bitmap = record
    rows:         cuint;
    width:        cuint;
    pitch:        cint;
    buffer:       PFT_Byte;
    num_grays:    cushort;
    pixel_mode:   cuchar;
    palette_mode: cuchar;
    palette:      Pointer;
  end;

  FT_Outline = record
    n_contours: cshort;
    n_points:   cshort;
    points:     PFT_Vector;
    tags:       PAnsiChar;
    contours:   ^cshort;
    flags:      cint;
  end;

  FT_Glyph_Metrics = record
    width:        FT_Pos;   // 26.6
    height:       FT_Pos;
    horiBearingX: FT_Pos;
    horiBearingY: FT_Pos;
    horiAdvance:  FT_Pos;
    vertBearingX: FT_Pos;
    vertBearingY: FT_Pos;
    vertAdvance:  FT_Pos;
  end;

  PFT_GlyphSlotRec = ^FT_GlyphSlotRec;
  FT_GlyphSlot = PFT_GlyphSlotRec;

  PFT_SizeRec = ^FT_SizeRec;
  FT_Size = PFT_SizeRec;

  PFT_FaceRec = ^FT_FaceRec;
  FT_Face = PFT_FaceRec;
  PFT_Face = ^FT_Face;

  FT_GlyphSlotRec = record
    library_:           FT_Library;
    face:               FT_Face;
    next:               FT_GlyphSlot;
    glyph_index:        FT_UInt;
    generic_:           FT_Generic;

    metrics:            FT_Glyph_Metrics;
    linearHoriAdvance:  FT_Fixed;
    linearVertAdvance:  FT_Fixed;
    advance:            FT_Vector;   // 26.6

    format:             cint;        // FT_Glyph_Format enum

    bitmap:             FT_Bitmap;
    bitmap_left:        FT_Int;      // integer pixels
    bitmap_top:         FT_Int;

    outline:            FT_Outline;

    num_subglyphs:      FT_UInt;
    subglyphs:          FT_SubGlyph;

    control_data:       Pointer;
    control_len:        clong;

    lsb_delta:          FT_Pos;
    rsb_delta:          FT_Pos;

    other:              Pointer;
    internal_:          Pointer;
  end;

  FT_Size_Metrics = record
    x_ppem:      FT_UShort;
    y_ppem:      FT_UShort;
    x_scale:     FT_Fixed;
    y_scale:     FT_Fixed;
    ascender:    FT_Pos;      // 26.6
    descender:   FT_Pos;      // 26.6 (negative)
    height:      FT_Pos;      // 26.6, baseline-to-baseline
    max_advance: FT_Pos;      // 26.6
  end;

  FT_SizeRec = record
    face:      FT_Face;
    generic_:  FT_Generic;
    metrics:   FT_Size_Metrics;
    internal_: Pointer;
  end;

  FT_FaceRec = record
    num_faces:           FT_Long;
    face_index:          FT_Long;
    face_flags:          FT_Long;
    style_flags:         FT_Long;
    num_glyphs:          FT_Long;

    family_name:         PFT_String;
    style_name:          PFT_String;

    num_fixed_sizes:     FT_Int;
    available_sizes:     FT_Bitmap_Size_Ptr;

    num_charmaps:        FT_Int;
    charmaps:            PFT_CharMap;

    generic_:            FT_Generic;

    // scalable-outline-only from here down to underline_thickness
    bbox:                FT_BBox;      // font units

    units_per_EM:        FT_UShort;
    ascender:            FT_Short;     // font units
    descender:           FT_Short;
    height:              FT_Short;

    max_advance_width:   FT_Short;
    max_advance_height:  FT_Short;

    underline_position:  FT_Short;
    underline_thickness: FT_Short;

    glyph:               FT_GlyphSlot;
    size:                FT_Size;
    charmap:             FT_CharMap;

    // private to FreeType
    driver:              FT_Driver;
    memory:              FT_Memory;
    stream:              FT_Stream;
    sizes_list:          FT_ListRec;
    autohint:            FT_Generic;
    extensions:          Pointer;
    internal_:           Pointer;
  end;

const
  FT_Err_Ok = 0;

  // FT_Load_Glyph / FT_Load_Char flags
  FT_LOAD_DEFAULT         = $0;
  FT_LOAD_NO_SCALE        = 1 shl 0;
  FT_LOAD_NO_HINTING      = 1 shl 1;
  FT_LOAD_RENDER          = 1 shl 2;
  FT_LOAD_NO_BITMAP       = 1 shl 3;
  FT_LOAD_FORCE_AUTOHINT  = 1 shl 5;
  FT_LOAD_MONOCHROME      = 1 shl 12;
  FT_LOAD_COLOR           = 1 shl 20;

  // FT_Render_Mode
  FT_RENDER_MODE_NORMAL = 0;   // 8-bit antialiased coverage
  FT_RENDER_MODE_LIGHT  = 1;
  FT_RENDER_MODE_MONO   = 2;
  FT_RENDER_MODE_LCD    = 3;
  FT_RENDER_MODE_LCD_V  = 4;

  // FT_Pixel_Mode (FT_Bitmap.pixel_mode)
  FT_PIXEL_MODE_NONE  = 0;
  FT_PIXEL_MODE_MONO  = 1;
  FT_PIXEL_MODE_GRAY  = 2;
  FT_PIXEL_MODE_BGRA  = 7;

  // FT_Kerning_Mode
  FT_KERNING_DEFAULT  = 0;   // scaled and grid-fitted, 26.6
  FT_KERNING_UNFITTED = 1;   // scaled, not grid-fitted, 26.6
  FT_KERNING_UNSCALED = 2;   // font units

  // FT_FaceRec.face_flags
  FT_FACE_FLAG_SCALABLE  = 1 shl 0;
  FT_FACE_FLAG_FIXED_WIDTH = 1 shl 2;
  FT_FACE_FLAG_KERNING   = 1 shl 6;

  LIB_FREETYPE = 'libfreetype.so.6';

function FT_Init_FreeType(alibrary: PFT_Library): FT_Error; cdecl; external LIB_FREETYPE;
function FT_Done_FreeType(alibrary: FT_Library): FT_Error; cdecl; external LIB_FREETYPE;

function FT_New_Face(alibrary: FT_Library; filepathname: PAnsiChar;
  face_index: FT_Long; aface: PFT_Face): FT_Error; cdecl; external LIB_FREETYPE;
function FT_New_Memory_Face(alibrary: FT_Library; file_base: PFT_Byte;
  file_size: FT_Long; face_index: FT_Long; aface: PFT_Face): FT_Error; cdecl; external LIB_FREETYPE;
function FT_Done_Face(face: FT_Face): FT_Error; cdecl; external LIB_FREETYPE;
function FT_Reference_Face(face: FT_Face): FT_Error; cdecl; external LIB_FREETYPE;

function FT_Set_Pixel_Sizes(face: FT_Face; pixel_width, pixel_height: FT_UInt): FT_Error; cdecl; external LIB_FREETYPE;
function FT_Set_Char_Size(face: FT_Face; char_width, char_height: FT_F26Dot6;
  horz_resolution, vert_resolution: FT_UInt): FT_Error; cdecl; external LIB_FREETYPE;

function FT_Get_Char_Index(face: FT_Face; charcode: FT_ULong): FT_UInt; cdecl; external LIB_FREETYPE;
function FT_Load_Glyph(face: FT_Face; glyph_index: FT_UInt; load_flags: cint): FT_Error; cdecl; external LIB_FREETYPE;
function FT_Load_Char(face: FT_Face; char_code: FT_ULong; load_flags: cint): FT_Error; cdecl; external LIB_FREETYPE;
function FT_Render_Glyph(slot: FT_GlyphSlot; render_mode: cint): FT_Error; cdecl; external LIB_FREETYPE;

function FT_Get_Kerning(face: FT_Face; left_glyph, right_glyph: FT_UInt;
  kern_mode: FT_UInt; akerning: PFT_Vector): FT_Error; cdecl; external LIB_FREETYPE;

function FT_Select_Charmap(face: FT_Face; encoding: culong): FT_Error; cdecl; external LIB_FREETYPE;
procedure FT_Library_Version(alibrary: FT_Library; amajor, aminor, apatch: PFT_Int); cdecl; external LIB_FREETYPE;

{ 26.6 <-> pixel conversions. From26Dot6 truncates toward zero the way FreeType's
  own FT_FLOOR-style macros do not — use From26Dot6Rounded when you want the
  nearest whole pixel (advances) and the plain form when you want fractions. }
function From26Dot6(AValue: FT_Pos): Double; inline;
function From26Dot6Rounded(AValue: FT_Pos): Integer; inline;
function To26Dot6(AValue: Double): FT_F26Dot6; inline;
function From16Dot16(AValue: FT_Fixed): Double; inline;

// Raise EFreeType if ACode is not FT_Err_Ok. AWhat names the failed call.
procedure FTCheck(ACode: FT_Error; const AWhat: String);

implementation

constructor EFreeType.Create(const AWhat: String; ACode: Integer);
begin
  inherited CreateFmt('%s failed with FreeType error 0x%.2x', [AWhat, ACode]);
  FErrorCode := ACode;
end;

procedure FTCheck(ACode: FT_Error; const AWhat: String);
begin
  if ACode <> FT_Err_Ok then
    raise EFreeType.Create(AWhat, ACode);
end;

function From26Dot6(AValue: FT_Pos): Double;
begin
  Result := AValue / 64.0;
end;

function From26Dot6Rounded(AValue: FT_Pos): Integer;
begin
  Result := (AValue + 32) shr 6;
end;

function To26Dot6(AValue: Double): FT_F26Dot6;
begin
  Result := Round(AValue * 64.0);
end;

function From16Dot16(AValue: FT_Fixed): Double;
begin
  Result := AValue / 65536.0;
end;

end.
