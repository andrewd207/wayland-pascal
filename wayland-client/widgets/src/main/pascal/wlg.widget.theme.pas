// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.widget.theme — what widgets look like, in one place.

  Widgets must not hardcode colours or draw their own chrome. They ask the
  theme for a palette, for metrics, and for the handful of shapes that make up
  a control — a face, a frame, a focus ring. Restyling the toolkit is then one
  class rather than an audit of every widget.

  SEEDED FROM THE DESKTOP. TwgDesktopTheme reads the existing desktop_theme
  unit, which already knows how to interrogate GNOME and KDE for the colour
  scheme, the accent colour and the UI font. So the toolkit looks approximately
  native on first run and follows a light/dark switch, instead of shipping an
  invented palette that matches nothing.

  desktop_theme only exposes a few colours — a headerbar background, a
  foreground and an accent — so the rest of the palette is DERIVED from those
  by lightening and darkening, with the direction chosen by whether the scheme
  is dark. That is a deliberate trade: a handful of real values plus consistent
  derivation looks coherent, whereas guessing a dozen independent colours does
  not.

  TOUCH AFFECTS METRICS, not layout. A finger needs roughly 9mm of target where
  a mouse needs 2mm, so TwgMetrics carries a minimum touch target that grows
  when the last input was touch. Widgets feed it into their size hints; nothing
  else has to change. }
unit wlg.widget.theme;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Types, Math,
  desktop_theme,
  wlg.surface, wlg.canvas.base, wlg.widget.types;

type
  { Horizontal placement for DrawCaption. Its own type rather than reusing the
    box layout's cross-alignment, which means something different. }
  TwgCrossAlignH = (chLeft, chCenter, chRight);

  { TwgPalette — every colour a widget is allowed to use. }
  TwgPalette = record
    Window: TwgColor;        // the window behind everything
    Surface: TwgColor;       // raised areas: panels, cards
    SurfaceAlt: TwgColor;    // alternating rows, wells, entry backgrounds
    Border: TwgColor;
    Text: TwgColor;
    TextDim: TwgColor;       // secondary text
    TextDisabled: TwgColor;
    Accent: TwgColor;        // selection, checked state, primary buttons
    AccentText: TwgColor;    // text drawn ON the accent
    ControlFace: TwgColor;   // a button at rest
    ControlHover: TwgColor;
    ControlPressed: TwgColor;
    ControlDisabled: TwgColor;
    Focus: TwgColor;         // the focus ring
    Shadow: TwgColor;
  end;

  TwgMetrics = record
    Padding: Integer;          // inside a control, around its content
    Spacing: Integer;          // between sibling controls
    CornerRadius: Integer;
    BorderWidth: Single;
    FocusRingWidth: Single;
    ControlHeight: Integer;    // natural height of a button or entry
    // Smallest comfortable hit target. Grows for touch.
    MinTouchTarget: Integer;
    ScrollBarSize: Integer;
  end;

  { TwgTheme }

  TwgTheme = class
  private
    FPalette: TwgPalette;
    FMetrics: TwgMetrics;
    FFontFamily: String;
    FFontSize: Single;
    FIsDark: Boolean;
    FTouchMode: Boolean;
    procedure SetTouchMode(AValue: Boolean);
  public
    constructor Create;

    // Public because controls live in another unit and every one of them
    // needs to ask which colour its current state calls for.
    function  FaceFor(AStates: TwgWidgetStates): TwgColor; virtual;
    function  TextFor(AStates: TwgWidgetStates): TwgColor; virtual;

    { --- primitives widgets draw with --- }
    // A button-like face, filled and outlined, in the state's colours.
    procedure DrawControlFace(ACanvas: TwgCanvas; const ARect: TRect;
      AStates: TwgWidgetStates); virtual;
    // A sunken area: entries, list backgrounds.
    procedure DrawWell(ACanvas: TwgCanvas; const ARect: TRect;
      AStates: TwgWidgetStates); virtual;
    // A raised container: panels, cards, popups.
    procedure DrawPanel(ACanvas: TwgCanvas; const ARect: TRect); virtual;
    procedure DrawBorder(ACanvas: TwgCanvas; const ARect: TRect;
      AColor: TwgColor); virtual;
    // Drawn INSIDE the control's bounds, so it is never clipped away by a
    // parent that clips its children — an outset ring usually is.
    procedure DrawFocusRing(ACanvas: TwgCanvas; const ARect: TRect); virtual;
    // Text in the state's colour, positioned within ARect.
    procedure DrawCaption(ACanvas: TwgCanvas; const ARect: TRect;
      const AText: String; AStates: TwgWidgetStates;
      AHAlign: TwgCrossAlignH = chCenter); virtual;

    property Palette: TwgPalette read FPalette write FPalette;
    property Metrics: TwgMetrics read FMetrics write FMetrics;
    property FontFamily: String read FFontFamily write FFontFamily;
    property FontSize: Single read FFontSize write FFontSize;
    property IsDark: Boolean read FIsDark;
    // Set when the last input was a finger; grows MinTouchTarget and the
    // control height so the same widgets stay usable.
    property TouchMode: Boolean read FTouchMode write SetTouchMode;
  end;

  { TwgDesktopTheme — a TwgTheme seeded from the running desktop. }

  TwgDesktopTheme = class(TwgTheme)
  private
    FDesktop: TDesktopTheme;
    procedure Adopt;
  public
    constructor Create;
    destructor Destroy; override;
    // Re-read the desktop settings (after a light/dark switch, say).
    procedure Refresh;
    property Desktop: TDesktopTheme read FDesktop;
  end;

// $00RRGGBB (what desktop_theme produces) -> an opaque TwgColor.
function wgFromRGB24(AValue: LongWord): TwgColor; inline;
// Blend towards white / towards black by 0..1.
function wgLighten(AColor: TwgColor; AAmount: Single): TwgColor;
function wgDarken(AColor: TwgColor; AAmount: Single): TwgColor;
// Mix two colours, 0 = A, 1 = B.
function wgMix(A, B: TwgColor; AAmount: Single): TwgColor;
// Perceived brightness 0..1, for deciding what reads on top of a colour.
function wgLuminance(AColor: TwgColor): Single;
// Black or white, whichever is legible on AColor.
function wgContrastText(AColor: TwgColor): TwgColor;

implementation

function wgFromRGB24(AValue: LongWord): TwgColor;
begin
  Result := wgARGB(255, (AValue shr 16) and $FF, (AValue shr 8) and $FF,
    AValue and $FF);
end;

function wgMix(A, B: TwgColor; AAmount: Single): TwgColor;
begin
  if AAmount <= 0 then Exit(A);
  if AAmount >= 1 then Exit(B);
  Result := wgARGB(
    Round(wgAlphaOf(A) + (wgAlphaOf(B) - wgAlphaOf(A)) * AAmount),
    Round(wgRedOf(A) + (wgRedOf(B) - wgRedOf(A)) * AAmount),
    Round(wgGreenOf(A) + (wgGreenOf(B) - wgGreenOf(A)) * AAmount),
    Round(wgBlueOf(A) + (wgBlueOf(B) - wgBlueOf(A)) * AAmount));
end;

function wgLighten(AColor: TwgColor; AAmount: Single): TwgColor;
begin
  Result := wgMix(AColor, wgARGB(wgAlphaOf(AColor), 255, 255, 255), AAmount);
end;

function wgDarken(AColor: TwgColor; AAmount: Single): TwgColor;
begin
  Result := wgMix(AColor, wgARGB(wgAlphaOf(AColor), 0, 0, 0), AAmount);
end;

function wgLuminance(AColor: TwgColor): Single;
begin
  // Rec. 601 weights: good enough for "is this light or dark", and cheaper
  // than a correct sRGB-linear conversion which this does not need.
  Result := (0.299 * wgRedOf(AColor) + 0.587 * wgGreenOf(AColor)
           + 0.114 * wgBlueOf(AColor)) / 255.0;
end;

function wgContrastText(AColor: TwgColor): TwgColor;
begin
  if wgLuminance(AColor) > 0.55 then
    Result := wgARGB(255, 20, 20, 24)
  else
    Result := wgARGB(255, 250, 250, 252);
end;

{ TwgTheme }

constructor TwgTheme.Create;
begin
  inherited Create;
  FFontFamily := 'Sans';
  FFontSize := 10;

  FMetrics.Padding := 10;
  FMetrics.Spacing := 8;
  FMetrics.CornerRadius := 8;
  FMetrics.BorderWidth := 1;
  FMetrics.FocusRingWidth := 2;
  FMetrics.ControlHeight := 32;
  FMetrics.MinTouchTarget := 24;
  FMetrics.ScrollBarSize := 12;

  // A neutral dark default, replaced wholesale by TwgDesktopTheme.
  FIsDark := True;
  FPalette.Window := wgARGB(255, 24, 27, 36);
  FPalette.Surface := wgARGB(255, 36, 41, 56);
  FPalette.SurfaceAlt := wgARGB(255, 30, 34, 47);
  FPalette.Border := wgARGB(90, 255, 255, 255);
  FPalette.Text := wgARGB(255, 236, 239, 246);
  FPalette.TextDim := wgARGB(180, 236, 239, 246);
  FPalette.TextDisabled := wgARGB(90, 236, 239, 246);
  FPalette.Accent := wgARGB(255, 62, 126, 220);
  FPalette.AccentText := wgARGB(255, 255, 255, 255);
  FPalette.ControlFace := wgARGB(255, 55, 62, 82);
  FPalette.ControlHover := wgARGB(255, 68, 77, 100);
  FPalette.ControlPressed := wgARGB(255, 44, 50, 66);
  FPalette.ControlDisabled := wgARGB(255, 40, 44, 56);
  FPalette.Focus := wgARGB(255, 240, 200, 90);
  FPalette.Shadow := wgARGB(90, 0, 0, 0);
end;

procedure TwgTheme.SetTouchMode(AValue: Boolean);
begin
  if FTouchMode = AValue then
    Exit;
  FTouchMode := AValue;
  // ~9mm versus ~2mm at a typical density. Widgets that feed MinTouchTarget
  // into their hints then grow without any other change.
  if FTouchMode then
  begin
    FMetrics.MinTouchTarget := 44;
    FMetrics.ControlHeight := Max(FMetrics.ControlHeight, 44);
    FMetrics.ScrollBarSize := 18;
  end
  else
  begin
    FMetrics.MinTouchTarget := 24;
    FMetrics.ControlHeight := 32;
    FMetrics.ScrollBarSize := 12;
  end;
end;

function TwgTheme.FaceFor(AStates: TwgWidgetStates): TwgColor;
begin
  // Order matters: disabled beats pressed beats hovered.
  if wsDisabled in AStates then
    Result := FPalette.ControlDisabled
  else if wsPressed in AStates then
    Result := FPalette.ControlPressed
  else if wsHovered in AStates then
    Result := FPalette.ControlHover
  else
    Result := FPalette.ControlFace;
end;

function TwgTheme.TextFor(AStates: TwgWidgetStates): TwgColor;
begin
  if wsDisabled in AStates then
    Result := FPalette.TextDisabled
  else
    Result := FPalette.Text;
end;

procedure TwgTheme.DrawControlFace(ACanvas: TwgCanvas; const ARect: TRect;
  AStates: TwgWidgetStates);
var
  lW, lH: Integer;
begin
  lW := ARect.Right - ARect.Left;
  lH := ARect.Bottom - ARect.Top;
  if (lW <= 0) or (lH <= 0) then
    Exit;
  ACanvas.FillRoundRect(ARect.Left, ARect.Top, lW, lH,
    FMetrics.CornerRadius, FMetrics.CornerRadius, FaceFor(AStates));
  DrawBorder(ACanvas, ARect, FPalette.Border);
  if wsFocused in AStates then
    DrawFocusRing(ACanvas, ARect);
end;

procedure TwgTheme.DrawWell(ACanvas: TwgCanvas; const ARect: TRect;
  AStates: TwgWidgetStates);
var
  lW, lH: Integer;
begin
  lW := ARect.Right - ARect.Left;
  lH := ARect.Bottom - ARect.Top;
  if (lW <= 0) or (lH <= 0) then
    Exit;
  ACanvas.FillRoundRect(ARect.Left, ARect.Top, lW, lH,
    FMetrics.CornerRadius, FMetrics.CornerRadius, FPalette.SurfaceAlt);
  DrawBorder(ACanvas, ARect, FPalette.Border);
  if wsFocused in AStates then
    DrawFocusRing(ACanvas, ARect);
end;

procedure TwgTheme.DrawPanel(ACanvas: TwgCanvas; const ARect: TRect);
var
  lW, lH: Integer;
begin
  lW := ARect.Right - ARect.Left;
  lH := ARect.Bottom - ARect.Top;
  if (lW <= 0) or (lH <= 0) then
    Exit;
  ACanvas.FillRoundRect(ARect.Left, ARect.Top, lW, lH,
    FMetrics.CornerRadius, FMetrics.CornerRadius, FPalette.Surface);
  DrawBorder(ACanvas, ARect, FPalette.Border);
end;

procedure TwgTheme.DrawBorder(ACanvas: TwgCanvas; const ARect: TRect;
  AColor: TwgColor);
var
  lW, lH: Integer;
  lInset: Single;
begin
  lW := ARect.Right - ARect.Left;
  lH := ARect.Bottom - ARect.Top;
  if (lW <= 0) or (lH <= 0) or (FMetrics.BorderWidth <= 0) then
    Exit;
  // Half the pen inside the edge, so a 1px stroke lands ON the boundary pixel
  // instead of straddling it and coming out as two half-covered rows.
  lInset := FMetrics.BorderWidth / 2;
  ACanvas.LineWidth := FMetrics.BorderWidth;
  ACanvas.RoundRect(ARect.Left + lInset, ARect.Top + lInset,
    lW - FMetrics.BorderWidth, lH - FMetrics.BorderWidth,
    FMetrics.CornerRadius, FMetrics.CornerRadius, AColor);
end;

procedure TwgTheme.DrawFocusRing(ACanvas: TwgCanvas; const ARect: TRect);
var
  lW, lH: Integer;
  lInset: Single;
begin
  lW := ARect.Right - ARect.Left;
  lH := ARect.Bottom - ARect.Top;
  if (lW <= 0) or (lH <= 0) then
    Exit;
  // Inside the bounds on purpose: a ring drawn outside would be clipped away
  // by any parent with ClipChildren, which is the default.
  lInset := FMetrics.BorderWidth + FMetrics.FocusRingWidth / 2;
  ACanvas.LineWidth := FMetrics.FocusRingWidth;
  ACanvas.RoundRect(ARect.Left + lInset, ARect.Top + lInset,
    lW - lInset * 2, lH - lInset * 2,
    Max(0, FMetrics.CornerRadius - 1), Max(0, FMetrics.CornerRadius - 1),
    FPalette.Focus);
end;

procedure TwgTheme.DrawCaption(ACanvas: TwgCanvas; const ARect: TRect;
  const AText: String; AStates: TwgWidgetStates; AHAlign: TwgCrossAlignH);
var
  lFont: IwgGlyphSource;
  lW, lX, lY: Integer;
begin
  if AText = '' then
    Exit;
  lFont := ACanvas.Font;
  if lFont = nil then
    Exit;
  lW := Round(ACanvas.TextWidth(AText));
  case AHAlign of
    chLeft:  lX := ARect.Left + FMetrics.Padding;
    chRight: lX := ARect.Right - FMetrics.Padding - lW;
    else     lX := ARect.Left + ((ARect.Right - ARect.Left) - lW) div 2;
  end;
  // Centre on the LINE BOX, not the glyph extents, so captions of different
  // text sit on the same baseline.
  lY := ARect.Top + Round(((ARect.Bottom - ARect.Top) - lFont.GetLineHeight) / 2);
  ACanvas.DrawTextTopLeft(AText, lX, lY, TextFor(AStates));
end;

{ TwgDesktopTheme }

constructor TwgDesktopTheme.Create;
begin
  inherited Create;
  FDesktop := CreateDesktopTheme;
  Adopt;
end;

destructor TwgDesktopTheme.Destroy;
begin
  FDesktop.Free;
  inherited Destroy;
end;

procedure TwgDesktopTheme.Refresh;
begin
  FDesktop.Refresh;
  Adopt;
end;

procedure TwgDesktopTheme.Adopt;
var
  lBg, lFg, lAccent: TwgColor;
  lP: TwgPalette;
begin
  FIsDark := FDesktop.IsDark;
  lBg := wgFromRGB24(FDesktop.HeaderbarBg);
  lFg := wgFromRGB24(FDesktop.HeaderbarFg);
  lAccent := wgFromRGB24(FDesktop.Accent);

  // desktop_theme gives three real colours; the rest is derived from them so
  // the result stays coherent. Which direction to move depends on the scheme:
  // on a dark theme raised surfaces are LIGHTER than the window, on a light
  // theme they are darker.
  lP := Palette;
  lP.Accent := lAccent;
  lP.AccentText := wgContrastText(lAccent);
  lP.Text := lFg;
  lP.TextDim := wgMix(lFg, lBg, 0.35);
  lP.TextDisabled := wgMix(lFg, lBg, 0.62);

  if FIsDark then
  begin
    lP.Window := wgDarken(lBg, 0.25);
    lP.Surface := lBg;
    lP.SurfaceAlt := wgDarken(lBg, 0.12);
    lP.ControlFace := wgLighten(lBg, 0.10);
    lP.ControlHover := wgLighten(lBg, 0.20);
    lP.ControlPressed := wgDarken(lBg, 0.10);
    lP.ControlDisabled := wgMix(lBg, lP.Window, 0.5);
    lP.Border := wgARGB(70, 255, 255, 255);
    lP.Shadow := wgARGB(120, 0, 0, 0);
  end
  else
  begin
    lP.Window := wgDarken(lBg, 0.06);
    lP.Surface := wgLighten(lBg, 0.55);
    lP.SurfaceAlt := wgLighten(lBg, 0.35);
    lP.ControlFace := wgLighten(lBg, 0.45);
    lP.ControlHover := wgLighten(lBg, 0.62);
    lP.ControlPressed := wgDarken(lBg, 0.08);
    lP.ControlDisabled := wgMix(lBg, lP.Window, 0.4);
    lP.Border := wgARGB(60, 0, 0, 0);
    lP.Shadow := wgARGB(50, 0, 0, 0);
  end;
  // The focus ring must read against BOTH the control face and the accent, so
  // it is derived from the accent rather than being another guess.
  lP.Focus := wgLighten(lAccent, 0.35);
  Palette := lP;

  if FDesktop.FontFamily <> '' then
    FontFamily := FDesktop.FontFamily;
  if FDesktop.FontSize > 0 then
    FontSize := FDesktop.FontSize;
end;

end.
