// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ xcursor — pure-Pascal Xcursor theme loader.

  Replaces libwayland-cursor / libXcursor: locates a named cursor in an XCursor
  theme (honouring theme inheritance and the XDG/XCURSOR_PATH search dirs), parses
  the binary Xcursor file, and returns the image(s) at the size nearest the
  requested nominal size. No Wayland or X11 dependency — the caller turns the
  returned ARGB pixels into whatever buffer it needs (e.g. a wl_shm buffer).

  Pixel format: each image's Pixels is Width*Height*4 bytes, premultiplied ARGB
  stored little-endian (byte order B,G,R,A) — i.e. directly usable as wl_shm
  ARGB8888 with no conversion.

  Animated cursors return all frames (with per-frame Delay in ms); a static
  consumer can just use frame 0. }
unit xcursor;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { One cursor image (one animation frame). }
  TXCursorImage = record
    Width, Height: Integer;
    XHot, YHot: Integer;     { hotspot, in pixels }
    Delay: Integer;          { frame delay in ms (animated cursors); 0 if static }
    Pixels: TBytes;          { Width*Height*4, premultiplied ARGB, LE (BGRA bytes) }
  end;
  TXCursorImages = array of TXCursorImage;

  { TXCursorTheme — resolves cursor names within a theme (and its inherited
    parents) to image data. Cheap to construct; LoadCursor does the filesystem
    work on demand. }
  TXCursorTheme = class
  private
    FTheme: String;
    FSize: Integer;
    FSearchPaths: TStringArray;
    function ReadInherits(const ATheme: String): TStringArray;
    function ResolveThemeChain(const ATheme: String): TStringArray;
    function FindCursorFile(const AName: String): String;
  public
    { ATheme: theme name (e.g. 'Adwaita'); '' resolves to 'default'. ASize: the
      desired nominal cursor size in px (<=0 defaults to 24). }
    constructor Create(const ATheme: String; ASize: Integer);
    { All frames of AName at the size nearest FSize, or [] if the cursor is not
      found anywhere in the theme chain. }
    function LoadCursor(const AName: String): TXCursorImages;
    property Theme: String read FTheme;
    property Size: Integer read FSize;
  end;

{ Parse an Xcursor file, returning every frame at the nominal size nearest
  ADesiredSize. Returns [] if the file is missing or not a valid Xcursor file. }
function ParseXCursorFile(const AFileName: String; ADesiredSize: Integer): TXCursorImages;

implementation

const
  XC_FILE_MAGIC = 'Xcur';
  XC_TYPE_IMAGE = $fffd0002;

type
  TTocEntry = record
    EntryType: DWord;
    SubType: DWord;     { for images: the nominal size }
    Position: DWord;    { file offset of the chunk }
  end;

function ReadLE32(AStream: TStream): DWord;
begin
  Result := 0;
  AStream.ReadBuffer(Result, 4);
  Result := LEtoN(Result);  { Xcursor stores LSBFirst 32-bit ints }
end;

function ParseXCursorFile(const AFileName: String; ADesiredSize: Integer): TXCursorImages;
var
  lStream: TFileStream;
  lMagic: array[0..3] of AnsiChar;
  lNToc, i: DWord;
  lToc: array of TTocEntry;
  lBestSize: DWord;
  lBestDiff, lDiff: Int64;
  lHaveImage: Boolean;
  lFrame: Integer;
  lWidth, lHeight: DWord;
  lImg: TXCursorImage;
begin
  Result := nil;
  if ADesiredSize <= 0 then
    ADesiredSize := 24;
  if not FileExists(AFileName) then
    Exit;

  lStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    if lStream.Size < 16 then
      Exit;
    lStream.ReadBuffer(lMagic, 4);
    if lMagic <> XC_FILE_MAGIC then
      Exit;
    ReadLE32(lStream);          { header size }
    ReadLE32(lStream);          { file version }
    lNToc := ReadLE32(lStream); { number of TOC entries }
    if lNToc = 0 then
      Exit;

    SetLength(lToc, lNToc);
    for i := 0 to lNToc - 1 do
    begin
      lToc[i].EntryType := ReadLE32(lStream);
      lToc[i].SubType   := ReadLE32(lStream);
      lToc[i].Position  := ReadLE32(lStream);
    end;

    { Pick the nominal size (image SubType) nearest the requested size; on a tie
      prefer the larger image (it scales down more cleanly). }
    lHaveImage := False;
    lBestSize := 0;
    lBestDiff := High(Int64);
    for i := 0 to lNToc - 1 do
      if lToc[i].EntryType = XC_TYPE_IMAGE then
      begin
        lDiff := Abs(Int64(lToc[i].SubType) - ADesiredSize);
        if (not lHaveImage) or (lDiff < lBestDiff) or
           ((lDiff = lBestDiff) and (lToc[i].SubType > lBestSize)) then
        begin
          lBestDiff := lDiff;
          lBestSize := lToc[i].SubType;
          lHaveImage := True;
        end;
      end;
    if not lHaveImage then
      Exit;

    { Collect every frame at the chosen size, in TOC order. }
    for i := 0 to lNToc - 1 do
    begin
      if (lToc[i].EntryType <> XC_TYPE_IMAGE) or (lToc[i].SubType <> lBestSize) then
        Continue;

      lStream.Position := lToc[i].Position;
      ReadLE32(lStream);                 { chunk header size }
      ReadLE32(lStream);                 { chunk type (= image) }
      ReadLE32(lStream);                 { chunk subtype (= nominal size) }
      ReadLE32(lStream);                 { chunk version }
      lWidth  := ReadLE32(lStream);
      lHeight := ReadLE32(lStream);
      { Guard against absurd dimensions (the format caps at 0x7fff). }
      if (lWidth = 0) or (lHeight = 0) or (lWidth > $7fff) or (lHeight > $7fff) then
        Continue;

      lImg := Default(TXCursorImage);
      lImg.Width  := lWidth;
      lImg.Height := lHeight;
      lImg.XHot   := ReadLE32(lStream);
      lImg.YHot   := ReadLE32(lStream);
      lImg.Delay  := ReadLE32(lStream);
      SetLength(lImg.Pixels, lWidth * lHeight * 4);
      lStream.ReadBuffer(lImg.Pixels[0], Length(lImg.Pixels));

      lFrame := Length(Result);
      SetLength(Result, lFrame + 1);
      Result[lFrame] := lImg;
    end;
  finally
    lStream.Free;
  end;
end;

{ TXCursorTheme }

function ExpandUser(const APath: String): String;
var
  lHome: String;
begin
  Result := APath;
  if (Length(APath) >= 1) and (APath[1] = '~') then
  begin
    lHome := GetEnvironmentVariable('HOME');
    if (Length(APath) = 1) or (APath[2] = '/') then
      Result := lHome + Copy(APath, 2, MaxInt);
  end;
end;

function BuildSearchPaths: TStringArray;
var
  lEnv: String;
  lParts: TStringArray;
  i, n: Integer;
begin
  Result := nil;
  lEnv := GetEnvironmentVariable('XCURSOR_PATH');
  if lEnv <> '' then
    lParts := lEnv.Split([':'])
  else
    { The conventional XCursor/XDG fallback search order. }
    lParts := TStringArray.Create(
      '~/.local/share/icons', '~/.icons',
      '/usr/share/icons', '/usr/share/pixmaps',
      '/usr/X11R6/lib/X11/icons');
  SetLength(Result, Length(lParts));
  n := 0;
  for i := 0 to High(lParts) do
    if lParts[i] <> '' then
    begin
      Result[n] := ExcludeTrailingPathDelimiter(ExpandUser(lParts[i]));
      Inc(n);
    end;
  SetLength(Result, n);
end;

constructor TXCursorTheme.Create(const ATheme: String; ASize: Integer);
begin
  FTheme := ATheme;
  if FTheme = '' then
    FTheme := 'default';
  FSize := ASize;
  if FSize <= 0 then
    FSize := 24;
  FSearchPaths := BuildSearchPaths;
end;

function TXCursorTheme.ReadInherits(const ATheme: String): TStringArray;

  function ParseFile(const AFile: String): TStringArray;
  var
    lLines: TStringList;
    i: Integer;
    lLine, lVal: String;
  begin
    Result := nil;
    if not FileExists(AFile) then
      Exit;
    lLines := TStringList.Create;
    try
      lLines.LoadFromFile(AFile);
      for i := 0 to lLines.Count - 1 do
      begin
        lLine := Trim(lLines[i]);
        if (Length(lLine) > 9) and SameText(Copy(lLine, 1, 9), 'Inherits=') then
        begin
          lVal := Trim(Copy(lLine, 10, MaxInt));
          { Inherits is a comma- (sometimes semicolon-) separated theme list. }
          Exit(lVal.Split([',', ';']));
        end;
      end;
    finally
      lLines.Free;
    end;
  end;

var
  i: Integer;
begin
  Result := nil;
  for i := 0 to High(FSearchPaths) do
  begin
    Result := ParseFile(FSearchPaths[i] + '/' + ATheme + '/index.theme');
    if Length(Result) > 0 then Exit;
    Result := ParseFile(FSearchPaths[i] + '/' + ATheme + '/cursor.theme');
    if Length(Result) > 0 then Exit;
  end;
end;

function TXCursorTheme.ResolveThemeChain(const ATheme: String): TStringArray;
var
  lQueue: TStringArray;
  lVisited: TStringList;
  lHead: Integer;
  lTheme: String;
  lInherits: TStringArray;
  i: Integer;

  procedure Push(const AName: String);
  var t: String;
  begin
    t := Trim(AName);
    if (t <> '') and (lVisited.IndexOf(t) < 0) then
    begin
      SetLength(lQueue, Length(lQueue) + 1);
      lQueue[High(lQueue)] := t;
    end;
  end;

begin
  lVisited := TStringList.Create;
  try
    lVisited.CaseSensitive := True;
    lQueue := nil;
    Push(ATheme);
    { 'default' is the conventional root fallback theme. }
    Push('default');
    lHead := 0;
    while lHead <= High(lQueue) do
    begin
      lTheme := lQueue[lHead];
      Inc(lHead);
      if lVisited.IndexOf(lTheme) >= 0 then
        Continue;
      lVisited.Add(lTheme);
      lInherits := ReadInherits(lTheme);
      for i := 0 to High(lInherits) do
        Push(lInherits[i]);
    end;
    Result := lVisited.ToStringArray;
  finally
    lVisited.Free;
  end;
end;

function TXCursorTheme.FindCursorFile(const AName: String): String;
var
  lChain: TStringArray;
  t, p: Integer;
  lCandidate: String;
begin
  Result := '';
  lChain := ResolveThemeChain(FTheme);
  for t := 0 to High(lChain) do
    for p := 0 to High(FSearchPaths) do
    begin
      { Opening the path follows any symlink the theme uses for cursor aliases
        (e.g. 'arrow' -> 'left_ptr'), so we don't resolve aliases ourselves. }
      lCandidate := FSearchPaths[p] + '/' + lChain[t] + '/cursors/' + AName;
      if FileExists(lCandidate) then
        Exit(lCandidate);
    end;
end;

function TXCursorTheme.LoadCursor(const AName: String): TXCursorImages;
var
  lFile: String;
begin
  Result := nil;
  lFile := FindCursorFile(AName);
  if lFile = '' then
    Exit;
  Result := ParseXCursorFile(lFile, FSize);
end;

end.
