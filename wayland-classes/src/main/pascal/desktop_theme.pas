{ desktop_theme — read the running desktop environment's appearance so a client
  drawing its own decorations (CSD) can match the native look.

  No Wayland or fpGUI dependency; works under X11 too. Any toolkit can use it.

  The public face is the abstract TDesktopTheme: light/dark preference, theme
  name, header-bar bg/fg/accent colours, window-button layout + side, and UI
  font. A consumer calls CreateDesktopTheme, which detects the desktop and
  returns the matching backend:

    TGtkDesktopTheme  — GNOME / GTK   (gsettings + the theme's gtk.gresource)
    TKdeDesktopTheme  — KDE / Qt      (kreadconfig5/6 over kdeglobals + kwinrc)

  New desktops are added by subclassing TDesktopTheme and overriding the
  protected Load* hooks; the base orchestrates Refresh and supplies the shared
  parsing helpers and a curated fallback palette, so every property is always
  usable even when the desktop tools are absent. Refresh never raises. }
unit desktop_theme;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TDesktopColorScheme = (dcsDefault, dcsPreferDark, dcsPreferLight);

  { One of the three standard title-bar buttons. }
  TDesktopWindowButton = (dwbMinimize, dwbMaximize, dwbClose);
  TDesktopWindowButtons = set of TDesktopWindowButton;

  { TDesktopTheme — abstract base / public interface. }

  TDesktopTheme = class
  protected
    FColorScheme: TDesktopColorScheme;
    FThemeName: string;
    FHeaderbarBg: LongWord;   { $00RRGGBB }
    FHeaderbarFg: LongWord;
    FAccent: LongWord;
    FButtonsLeft: TDesktopWindowButtons;
    FButtonsRight: TDesktopWindowButtons;
    FFontName: string;
    FFontFamily: string;
    FFontSize: Integer;

    { ---- shared helpers available to every backend ---- }
    { Run a command and capture stdout. False (and '') if the tool is missing. }
    function  RunCapture(const AExe: string; const AArgs: array of string;
      out AOutput: string): Boolean;
    { Parse a GNOME button-layout string ("left:right" of comma tokens) into the
      two button sets. }
    procedure ParseGtkButtonLayout(const ALayout: string);
    { Parse a Pango font string ("Family Style 11") into family + size. }
    procedure ParsePangoFont(const AFontName: string);
    { Overwrite the three header colours with the curated Adwaita-ish palette
      for the current light/dark scheme. Backends call this first, then refine. }
    procedure ApplyFallbackColors;

    { ---- per-desktop hooks (override these) ---- }
    procedure LoadColorScheme; virtual; abstract;  { set FColorScheme }
    procedure LoadThemeName; virtual;              { set FThemeName (default '') }
    procedure LoadButtons; virtual; abstract;      { set FButtonsLeft/FButtonsRight }
    procedure LoadFont; virtual;                   { set font fields (default none) }
    procedure LoadColors; virtual;                 { refine colours past the fallback }
  public
    { (Re-)read every setting from the live desktop. Cheap enough to call at
      startup and again on a change signal. Never raises. }
    procedure Refresh;
    function  IsDark: Boolean;
    property ColorScheme: TDesktopColorScheme read FColorScheme;
    property ThemeName: string read FThemeName;
    { Header-bar colours as $00RRGGBB (matches fpGUI's TfpgColor RGB layout). }
    property HeaderbarBg: LongWord read FHeaderbarBg;
    property HeaderbarFg: LongWord read FHeaderbarFg;
    property Accent: LongWord read FAccent;
    { Which buttons the user wants, and on which side of the title bar. The two
      sets are disjoint; usually everything is on the right. }
    property ButtonsLeft: TDesktopWindowButtons read FButtonsLeft;
    property ButtonsRight: TDesktopWindowButtons read FButtonsRight;
    property FontName: string read FFontName;     { raw, e.g. "Ubuntu Sans 11" }
    property FontFamily: string read FFontFamily;  { "Ubuntu Sans" }
    property FontSize: Integer read FFontSize;     { 11, 0 if unknown }
  end;

  { TGtkDesktopTheme — GNOME / GTK backend. }
  TGtkDesktopTheme = class(TDesktopTheme)
  protected
    function  GSetting(const ASchema, AKey: string): string;
    procedure LoadColorScheme; override;
    procedure LoadThemeName; override;
    procedure LoadButtons; override;
    procedure LoadFont; override;
    procedure LoadColors; override;  { extract colours from the gtk.gresource }
  end;

  { TKdeDesktopTheme — KDE / Qt backend. }
  TKdeDesktopTheme = class(TDesktopTheme)
  protected
    function  KRead(const AFile, AGroup, AKey: string): string;
    procedure LoadColorScheme; override;
    procedure LoadThemeName; override;
    procedure LoadButtons; override;
    procedure LoadFont; override;
    procedure LoadColors; override;
  end;

{ Detect the running desktop (XDG_CURRENT_DESKTOP) and return the matching,
  already-Refreshed backend. Caller owns the instance. Defaults to GTK. }
function CreateDesktopTheme: TDesktopTheme;

{ Parse a CSS/GTK colour literal ("#rgb", "#rrggbb", "rgb(r,g,b)", "rgba(...)")
  into $00RRGGBB. False if the form isn't a resolvable literal. }
function TryParseCssColor(const AText: string; out AColor: LongWord): Boolean;

{ Parse a KDE "r,g,b" colour triplet into $00RRGGBB. }
function TryParseRgbTriplet(const AText: string; out AColor: LongWord): Boolean;

implementation

uses
  process;

const
  { Curated Adwaita header-bar colours, used when a theme's colours can't be
    read. Accent is Adwaita blue. }
  ADW_DARK_BG  = $00303030;
  ADW_DARK_FG  = $00FFFFFF;
  ADW_LIGHT_BG = $00EBEBEB;
  ADW_LIGHT_FG = $002E3436;
  ADW_ACCENT   = $003584E4;

{ ---- standalone parsers ---- }

function HexNibble(c: Char): Integer;
begin
  case c of
    '0'..'9': Result := Ord(c) - Ord('0');
    'a'..'f': Result := Ord(c) - Ord('a') + 10;
    'A'..'F': Result := Ord(c) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function TryParseCssColor(const AText: string; out AColor: LongWord): Boolean;
var
  s, hexpart, inner: string;
  r, g, b: Integer;
  parts: TStringArray;

  function Hex2(const h: string; idx: Integer): Integer;
  var hi, lo: Integer;
  begin
    hi := HexNibble(h[idx]); lo := HexNibble(h[idx + 1]);
    if (hi < 0) or (lo < 0) then Result := -1 else Result := hi * 16 + lo;
  end;

begin
  Result := False;
  AColor := 0;
  s := Trim(AText);
  if s = '' then Exit;

  if s[1] = '#' then
  begin
    hexpart := Copy(s, 2, Length(s) - 1);
    if Length(hexpart) = 3 then
    begin
      r := HexNibble(hexpart[1]); g := HexNibble(hexpart[2]); b := HexNibble(hexpart[3]);
      if (r < 0) or (g < 0) or (b < 0) then Exit;
      AColor := (LongWord(r * 17) shl 16) or (LongWord(g * 17) shl 8) or LongWord(b * 17);
      Exit(True);
    end
    else if Length(hexpart) >= 6 then
    begin
      r := Hex2(hexpart, 1); g := Hex2(hexpart, 3); b := Hex2(hexpart, 5);
      if (r < 0) or (g < 0) or (b < 0) then Exit;
      AColor := (LongWord(r) shl 16) or (LongWord(g) shl 8) or LongWord(b);
      Exit(True);
    end;
    Exit;
  end;

  if (Pos('rgb(', LowerCase(s)) = 1) or (Pos('rgba(', LowerCase(s)) = 1) then
  begin
    inner := Copy(s, Pos('(', s) + 1, Length(s));
    inner := StringReplace(inner, ')', '', [rfReplaceAll]);
    parts := inner.Split([',']);
    if Length(parts) < 3 then Exit;
    r := StrToIntDef(Trim(parts[0]), -1);
    g := StrToIntDef(Trim(parts[1]), -1);
    b := StrToIntDef(Trim(parts[2]), -1);
    if (r < 0) or (g < 0) or (b < 0) then Exit;
    AColor := (LongWord(r and $FF) shl 16) or (LongWord(g and $FF) shl 8) or LongWord(b and $FF);
    Exit(True);
  end;
end;

function TryParseRgbTriplet(const AText: string; out AColor: LongWord): Boolean;
var
  parts: TStringArray;
  r, g, b: Integer;
begin
  Result := False;
  AColor := 0;
  parts := Trim(AText).Split([',']);
  if Length(parts) < 3 then Exit;
  r := StrToIntDef(Trim(parts[0]), -1);
  g := StrToIntDef(Trim(parts[1]), -1);
  b := StrToIntDef(Trim(parts[2]), -1);
  if (r < 0) or (g < 0) or (b < 0) then Exit;
  AColor := (LongWord(r and $FF) shl 16) or (LongWord(g and $FF) shl 8) or LongWord(b and $FF);
  Result := True;
end;

{ Rec. 601 luma; used to classify a window background as dark or light. }
function ColorIsDark(AColor: LongWord): Boolean;
var r, g, b: Integer;
begin
  r := (AColor shr 16) and $FF;
  g := (AColor shr 8) and $FF;
  b := AColor and $FF;
  Result := (r * 299 + g * 587 + b * 114) div 1000 < 128;
end;

{ ---- TDesktopTheme (base) ---- }

procedure TDesktopTheme.LoadThemeName;
begin
  FThemeName := '';
end;

procedure TDesktopTheme.LoadFont;
begin
  { default: leave font fields as set by ParsePangoFont('') }
end;

procedure TDesktopTheme.LoadColors;
begin
  { default: keep the fallback palette already applied by Refresh }
end;

function TDesktopTheme.IsDark: Boolean;
begin
  Result := FColorScheme = dcsPreferDark;
end;

function TDesktopTheme.RunCapture(const AExe: string;
  const AArgs: array of string; out AOutput: string): Boolean;
begin
  AOutput := '';
  try
    Result := RunCommand(AExe, AArgs, AOutput);
  except
    Result := False;  { tool not installed / not on PATH }
  end;
end;

procedure TDesktopTheme.ParseGtkButtonLayout(const ALayout: string);

  procedure ParseSide(const ATokens: string; out ASet: TDesktopWindowButtons);
  var t: string;
  begin
    ASet := [];
    for t in ATokens.Split([',']) do
      case Trim(t) of
        'minimize': Include(ASet, dwbMinimize);
        'maximize': Include(ASet, dwbMaximize);
        'close':    Include(ASet, dwbClose);
      end;
  end;

var
  colon: Integer;
begin
  FButtonsLeft := [];
  FButtonsRight := [];
  colon := Pos(':', ALayout);
  if colon = 0 then
  begin
    ParseSide(ALayout, FButtonsRight);
    Exit;
  end;
  ParseSide(Copy(ALayout, 1, colon - 1), FButtonsLeft);
  ParseSide(Copy(ALayout, colon + 1, Length(ALayout)), FButtonsRight);
end;

procedure TDesktopTheme.ParsePangoFont(const AFontName: string);
var
  sp: Integer;
  tail: string;
begin
  FFontName := AFontName;
  FFontFamily := AFontName;
  FFontSize := 0;
  sp := LastDelimiter(' ', AFontName);
  if sp > 0 then
  begin
    tail := Copy(AFontName, sp + 1, Length(AFontName));
    if StrToIntDef(tail, 0) > 0 then
    begin
      FFontSize := StrToIntDef(tail, 0);
      FFontFamily := Trim(Copy(AFontName, 1, sp - 1));
    end;
  end;
end;

procedure TDesktopTheme.ApplyFallbackColors;
begin
  if IsDark then
  begin
    FHeaderbarBg := ADW_DARK_BG;
    FHeaderbarFg := ADW_DARK_FG;
  end
  else
  begin
    FHeaderbarBg := ADW_LIGHT_BG;
    FHeaderbarFg := ADW_LIGHT_FG;
  end;
  FAccent := ADW_ACCENT;
end;

procedure TDesktopTheme.Refresh;
begin
  LoadColorScheme;
  LoadThemeName;
  LoadButtons;
  if (FButtonsLeft = []) and (FButtonsRight = []) then
    FButtonsRight := [dwbMinimize, dwbMaximize, dwbClose];
  ParsePangoFont('');
  LoadFont;
  ApplyFallbackColors;   { guarantees usable colours ... }
  LoadColors;            { ... backend refines from the real theme if it can }
end;

{ ---- TGtkDesktopTheme ---- }

{ Strip the wrapping single quotes gsettings prints around string values. }
function Unquote(const s: string): string;
begin
  Result := Trim(s);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

function TGtkDesktopTheme.GSetting(const ASchema, AKey: string): string;
begin
  if RunCapture('gsettings', ['get', ASchema, AKey], Result) then
    Result := Unquote(Result)
  else
    Result := '';
end;

procedure TGtkDesktopTheme.LoadColorScheme;
var
  s: string;
begin
  s := LowerCase(GSetting('org.gnome.desktop.interface', 'color-scheme'));
  if Pos('dark', s) > 0 then begin FColorScheme := dcsPreferDark; Exit; end;
  if Pos('light', s) > 0 then begin FColorScheme := dcsPreferLight; Exit; end;
  if s = 'default' then begin FColorScheme := dcsDefault; Exit; end;

  { Fallback: the cross-desktop portal. "(<<uint32 1>>,)" => 1 dark, 2 light. }
  if RunCapture('gdbus', ['call', '--session',
      '--dest', 'org.freedesktop.portal.Desktop',
      '--object-path', '/org/freedesktop/portal/desktop',
      '--method', 'org.freedesktop.portal.Settings.Read',
      'org.freedesktop.appearance', 'color-scheme'], s) then
  begin
    if Pos('uint32 1', s) > 0 then begin FColorScheme := dcsPreferDark; Exit; end;
    if Pos('uint32 2', s) > 0 then begin FColorScheme := dcsPreferLight; Exit; end;
  end;
  FColorScheme := dcsDefault;
end;

procedure TGtkDesktopTheme.LoadThemeName;
begin
  FThemeName := GSetting('org.gnome.desktop.interface', 'gtk-theme');
end;

procedure TGtkDesktopTheme.LoadButtons;
begin
  ParseGtkButtonLayout(GSetting('org.gnome.desktop.wm.preferences', 'button-layout'));
end;

procedure TGtkDesktopTheme.LoadFont;
begin
  ParsePangoFont(GSetting('org.gnome.desktop.interface', 'font-name'));
end;

procedure TGtkDesktopTheme.LoadColors;
var
  candidates: TStringArray;
  gres, home, listing, css, line, name, rawval, resPath: string;
  i, eq, semi: Integer;
  names: TStringList;

  function PickColor(const AKeys: array of string; ADefault: LongWord): LongWord;
  var k, v: string; depth: Integer; c: LongWord;
  begin
    for k in AKeys do
    begin
      v := names.Values[k];
      depth := 0;
      while (v <> '') and (v[1] = '@') and (depth < 8) do  { resolve @alias hops }
      begin
        v := names.Values[Copy(v, 2, Length(v))];
        Inc(depth);
      end;
      if (v <> '') and TryParseCssColor(v, c) then
        Exit(c);
    end;
    Result := ADefault;
  end;

begin
  if FThemeName = '' then Exit;

  home := GetEnvironmentVariable('HOME');
  candidates := [
    home + '/.themes/' + FThemeName + '/gtk-3.0/gtk.gresource',
    home + '/.local/share/themes/' + FThemeName + '/gtk-3.0/gtk.gresource',
    '/usr/share/themes/' + FThemeName + '/gtk-3.0/gtk.gresource'
  ];
  gres := '';
  for i := 0 to High(candidates) do
    if FileExists(candidates[i]) then begin gres := candidates[i]; Break; end;
  if gres = '' then Exit;

  if not RunCapture('gresource', ['list', gres], listing) then Exit;
  resPath := '';
  if IsDark then
    for line in listing.Split([#10]) do
      if line.EndsWith('gtk-dark.css') then begin resPath := Trim(line); Break; end;
  if resPath = '' then
    for line in listing.Split([#10]) do
      if line.EndsWith('/gtk.css') then begin resPath := Trim(line); Break; end;
  if resPath = '' then Exit;

  if not RunCapture('gresource', ['extract', gres, resPath], css) then Exit;
  if css = '' then Exit;

  names := TStringList.Create;
  try
    names.NameValueSeparator := '=';
    for line in css.Split([#10]) do
    begin
      i := Pos('@define-color', line);
      if i = 0 then Continue;
      rawval := Trim(Copy(line, i + Length('@define-color'), Length(line)));
      eq := Pos(' ', rawval);
      if eq = 0 then Continue;
      name := Copy(rawval, 1, eq - 1);
      rawval := Trim(Copy(rawval, eq + 1, Length(rawval)));
      semi := Pos(';', rawval);
      if semi > 0 then rawval := Trim(Copy(rawval, 1, semi - 1));
      if name <> '' then
        names.Values[name] := rawval;
    end;

    FHeaderbarBg := PickColor(['headerbar_bg_color', 'theme_bg_color', 'window_bg_color'], FHeaderbarBg);
    FHeaderbarFg := PickColor(['headerbar_fg_color', 'theme_fg_color', 'window_fg_color'], FHeaderbarFg);
    FAccent := PickColor(['accent_bg_color', 'theme_selected_bg_color', 'accent_color'], FAccent);
  finally
    names.Free;
  end;
end;

{ ---- TKdeDesktopTheme ---- }

{ kreadconfig5/6 reader. Tries v6 then v5; '' if neither is present. }
function TKdeDesktopTheme.KRead(const AFile, AGroup, AKey: string): string;

  function TryExe(const AExe: string; out AOut: string): Boolean;
  begin
    if AFile <> '' then
      Result := RunCapture(AExe, ['--file', AFile, '--group', AGroup, '--key', AKey], AOut)
    else
      Result := RunCapture(AExe, ['--group', AGroup, '--key', AKey], AOut);
    Result := Result and (Trim(AOut) <> '');
  end;

begin
  if TryExe('kreadconfig6', Result) then begin Result := Trim(Result); Exit; end;
  if TryExe('kreadconfig5', Result) then begin Result := Trim(Result); Exit; end;
  Result := '';
end;

procedure TKdeDesktopTheme.LoadColorScheme;
var
  bg: LongWord;
  s: string;
begin
  { KDE has no single dark/light flag; infer it from the window background. }
  if TryParseRgbTriplet(KRead('kdeglobals', 'Colors:Window', 'BackgroundNormal'), bg) then
  begin
    if ColorIsDark(bg) then FColorScheme := dcsPreferDark
    else FColorScheme := dcsPreferLight;
    Exit;
  end;
  { Fallback to the portal (KDE implements it too). }
  if RunCapture('gdbus', ['call', '--session',
      '--dest', 'org.freedesktop.portal.Desktop',
      '--object-path', '/org/freedesktop/portal/desktop',
      '--method', 'org.freedesktop.portal.Settings.Read',
      'org.freedesktop.appearance', 'color-scheme'], s) then
  begin
    if Pos('uint32 1', s) > 0 then begin FColorScheme := dcsPreferDark; Exit; end;
    if Pos('uint32 2', s) > 0 then begin FColorScheme := dcsPreferLight; Exit; end;
  end;
  FColorScheme := dcsDefault;
end;

procedure TKdeDesktopTheme.LoadThemeName;
begin
  FThemeName := KRead('kdeglobals', 'General', 'ColorScheme');
end;

procedure TKdeDesktopTheme.LoadButtons;

  procedure ParseSide(const ACodes: string; out ASet: TDesktopWindowButtons);
  var c: Char;
  begin
    { KDE decoration button codes: I=minimize, A=maximize, X=close (others —
      M menu, S keep-above, etc. — aren't standard title buttons here). }
    ASet := [];
    for c in ACodes do
      case c of
        'I': Include(ASet, dwbMinimize);
        'A': Include(ASet, dwbMaximize);
        'X': Include(ASet, dwbClose);
      end;
  end;

begin
  ParseSide(KRead('kwinrc', 'org.kde.kdecoration2', 'ButtonsOnLeft'), FButtonsLeft);
  ParseSide(KRead('kwinrc', 'org.kde.kdecoration2', 'ButtonsOnRight'), FButtonsRight);
end;

procedure TKdeDesktopTheme.LoadFont;
begin
  { kdeglobals General/font is "Family,size,..." (comma-separated). }
  ParsePangoFont(StringReplace(KRead('kdeglobals', 'General', 'font'), ',', ' ', []));
end;

procedure TKdeDesktopTheme.LoadColors;
var
  c: LongWord;
begin
  if TryParseRgbTriplet(KRead('kdeglobals', 'Colors:Window', 'BackgroundNormal'), c) then
    FHeaderbarBg := c;
  if TryParseRgbTriplet(KRead('kdeglobals', 'Colors:Window', 'ForegroundNormal'), c) then
    FHeaderbarFg := c;
  if TryParseRgbTriplet(KRead('kdeglobals', 'Colors:Selection', 'BackgroundNormal'), c) then
    FAccent := c;
end;

{ ---- factory ---- }

function CreateDesktopTheme: TDesktopTheme;
var
  desk: string;
begin
  desk := LowerCase(GetEnvironmentVariable('XDG_CURRENT_DESKTOP'));
  if (Pos('kde', desk) > 0) or (Pos('plasma', desk) > 0) then
    Result := TKdeDesktopTheme.Create
  else
    Result := TGtkDesktopTheme.Create;  { GNOME and everything else }
  Result.Refresh;
end;

end.
