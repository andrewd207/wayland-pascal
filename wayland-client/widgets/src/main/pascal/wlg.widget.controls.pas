// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.widget.controls — the starter set of widgets.

  Label, button, checkbox, radio, slider and panel. Between them they exercise
  every part of the machinery underneath — intrinsic measurement, theming,
  hover and press state, focus and keyboard activation, per-sequence capture —
  so they double as the worked examples for writing more.

  Two habits every control here follows, and any new one should:

  1. PAINT FROM States, never from private hover/press flags. The router owns
     that state, so reading it back is the only way the visual and the routing
     cannot drift apart.
  2. ASK THE THEME. No colours, radii or paddings appear in this unit except
     through TwgTheme, which is what makes a restyle one class.

  TwgControl carries the shared plumbing — a theme reference, the IwgInputTarget
  boilerplate with harmless defaults — so an individual control only overrides
  what it actually does. }
unit wlg.widget.controls;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Types, Math,
  wlg.surface, wlg.canvas.base,
  wlg.widget.types, wlg.widget.core, wlg.widget.input, wlg.widget.theme;

type
  { TwgControl — base for anything interactive. }

  TwgControl = class(TwgWidget, IwgInputTarget)
  private
    FTheme: TwgTheme;
    FCaption: String;
    procedure SetCaption(const AValue: String);
  protected
    // Inherited from the parent chain, so setting it on a form's root is
    // enough. Never nil once a control is in a themed tree.
    function  Theme: TwgTheme;
    function  MeasureSize(AAvailW, AAvailH: Integer): TSize; override;
    // Width of the caption in the control's font, for measurement.
    function  CaptionWidth(AFont: IwgGlyphSource): Integer;
  public
    { IwgInputTarget — harmless defaults; override what you need. }
    procedure PointerDown(var AEvent: TwgPointerEvent); virtual;
    procedure PointerUp(var AEvent: TwgPointerEvent); virtual;
    procedure PointerMove(var AEvent: TwgPointerEvent); virtual;
    procedure PointerEnter(var AEvent: TwgPointerEvent); virtual;
    procedure PointerLeave(var AEvent: TwgPointerEvent); virtual;
    procedure Click(var AEvent: TwgPointerEvent); virtual;
    procedure PointerCancel(var AEvent: TwgPointerEvent); virtual;
    procedure Scroll(var AEvent: TwgScrollEvent); virtual;
    procedure KeyDown(var AEvent: TwgKeyEvent); virtual;
    procedure KeyUp(var AEvent: TwgKeyEvent); virtual;
    procedure FocusIn; virtual;
    procedure FocusOut; virtual;
    function  CanFocus: Boolean; virtual;

    // Assign on the root of a form; descendants inherit it.
    procedure SetTheme(ATheme: TwgTheme);
    property Caption: String read FCaption write SetCaption;
  end;

  { TwgLabel — non-interactive text. Measures to its own content. }

  TwgLabel = class(TwgControl)
  private
    FAlign: TwgCrossAlignH;
    FDim: Boolean;
  protected
    procedure Paint(ACanvas: TwgCanvas); override;
    function  MeasureSize(AAvailW, AAvailH: Integer): TSize; override;
  public
    function  CanFocus: Boolean; override;
    // Labels are transparent to the pointer, so a click lands on whatever is
    // behind them rather than being swallowed by decoration.
    function  ContainsPoint(X, Y: Integer): Boolean; override;
    property  Align: TwgCrossAlignH read FAlign write FAlign;
    property  Dim: Boolean read FDim write FDim;
  end;

  { TwgButton }

  TwgButton = class(TwgControl)
  private
    FOnClick: TNotifyEvent;
  protected
    procedure Paint(ACanvas: TwgCanvas); override;
  public
    procedure Click(var AEvent: TwgPointerEvent); override;
    procedure KeyDown(var AEvent: TwgKeyEvent); override;
    procedure PointerDown(var AEvent: TwgPointerEvent); override;
    procedure PointerUp(var AEvent: TwgPointerEvent); override;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
  end;

  { TwgCheckBox }

  TwgCheckBox = class(TwgControl)
  private
    FChecked: Boolean;
    FOnChange: TNotifyEvent;
    procedure SetChecked(AValue: Boolean);
  protected
    procedure Paint(ACanvas: TwgCanvas); override;
    function  MeasureSize(AAvailW, AAvailH: Integer): TSize; override;
    function  BoxSize: Integer;
  public
    procedure Click(var AEvent: TwgPointerEvent); override;
    procedure KeyDown(var AEvent: TwgKeyEvent); override;
    procedure PointerDown(var AEvent: TwgPointerEvent); override;
    property Checked: Boolean read FChecked write SetChecked;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { TwgRadioButton — one of a group; the group is the set of sibling radios. }

  TwgRadioButton = class(TwgCheckBox)
  protected
    procedure Paint(ACanvas: TwgCanvas); override;
  public
    procedure Click(var AEvent: TwgPointerEvent); override;
  end;

  { TwgSlider — the control that proves capture works.

    Dragging must keep tracking after the pointer leaves the slider, which only
    happens because the router holds the grab from press to release. }

  TwgSlider = class(TwgControl)
  private
    FMin, FMax, FValue: Single;
    FDragging: Boolean;
    FOnChange: TNotifyEvent;
    procedure SetValue(AValue: Single);
    function  ValueFromX(X: Integer): Single;
    function  TrackRect: TRect;
    function  KnobCentre: Integer;
    function  KnobRadius: Integer;
  protected
    procedure Paint(ACanvas: TwgCanvas); override;
    function  MeasureSize(AAvailW, AAvailH: Integer): TSize; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure PointerDown(var AEvent: TwgPointerEvent); override;
    procedure PointerMove(var AEvent: TwgPointerEvent); override;
    procedure PointerUp(var AEvent: TwgPointerEvent); override;
    procedure PointerCancel(var AEvent: TwgPointerEvent); override;
    procedure KeyDown(var AEvent: TwgKeyEvent); override;

    property Min: Single read FMin write FMin;
    property Max: Single read FMax write FMax;
    property Value: Single read FValue write SetValue;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { TwgPanel — a themed container. Not interactive; exists to be a surface. }

  TwgPanel = class(TwgControl)
  protected
    procedure Paint(ACanvas: TwgCanvas); override;
  public
    function CanFocus: Boolean; override;
  end;

implementation

{ TwgControl }

function TwgControl.Theme: TwgTheme;
var
  w: TwgWidget;
begin
  // Walk up rather than copying a reference into every widget: a form sets it
  // once on the root and re-parenting cannot leave a stale one behind.
  w := Self;
  while w <> nil do
  begin
    if (w is TwgControl) and (TwgControl(w).FTheme <> nil) then
      Exit(TwgControl(w).FTheme);
    w := w.Parent;
  end;
  Result := nil;
end;

procedure TwgControl.SetTheme(ATheme: TwgTheme);
begin
  FTheme := ATheme;
  Invalidate;
  InvalidateLayout;
end;

procedure TwgControl.SetCaption(const AValue: String);
begin
  if FCaption = AValue then
    Exit;
  FCaption := AValue;
  Invalidate;
  // The caption is part of the intrinsic size, so the layout may need redoing.
  InvalidateLayout;
end;

function TwgControl.CaptionWidth(AFont: IwgGlyphSource): Integer;
var
  i: Integer;
  lIdx: LongWord;
  lInfo: TwgGlyphInfo;
  lW: Single;
begin
  Result := 0;
  if (AFont = nil) or (FCaption = '') then
    Exit;
  // Sum advances directly: TwgCanvas.TextWidth needs a canvas, and measurement
  // happens during layout when there is none.
  lW := 0;
  for i := 1 to Length(FCaption) do
  begin
    lIdx := AFont.GetGlyphIndex(Byte(FCaption[i]));
    if AFont.GetGlyph(lIdx, lInfo) then
      lW := lW + lInfo.Advance;
  end;
  Result := Round(lW);
end;

function TwgControl.MeasureSize(AAvailW, AAvailH: Integer): TSize;
var
  lTheme: TwgTheme;
  lFont: IwgGlyphSource;
begin
  lTheme := Theme;
  if lTheme = nil then
    Exit(inherited MeasureSize(AAvailW, AAvailH));
  lFont := EffectiveFont;
  Result.cx := CaptionWidth(lFont) + lTheme.Metrics.Padding * 2;
  Result.cy := Math.Max(lTheme.Metrics.ControlHeight,
                          lTheme.Metrics.MinTouchTarget);
end;

procedure TwgControl.PointerDown(var AEvent: TwgPointerEvent); begin end;
procedure TwgControl.PointerUp(var AEvent: TwgPointerEvent); begin end;
procedure TwgControl.PointerMove(var AEvent: TwgPointerEvent); begin end;
procedure TwgControl.PointerEnter(var AEvent: TwgPointerEvent); begin end;
procedure TwgControl.PointerLeave(var AEvent: TwgPointerEvent); begin end;
procedure TwgControl.Click(var AEvent: TwgPointerEvent); begin end;
procedure TwgControl.PointerCancel(var AEvent: TwgPointerEvent); begin Invalidate; end;
procedure TwgControl.Scroll(var AEvent: TwgScrollEvent); begin end;
procedure TwgControl.KeyDown(var AEvent: TwgKeyEvent); begin end;
procedure TwgControl.KeyUp(var AEvent: TwgKeyEvent); begin end;
procedure TwgControl.FocusIn; begin Invalidate; end;
procedure TwgControl.FocusOut; begin Invalidate; end;
function  TwgControl.CanFocus: Boolean; begin Result := Enabled and Visible; end;

{ TwgLabel }

function TwgLabel.CanFocus: Boolean;
begin
  Result := False;
end;

function TwgLabel.ContainsPoint(X, Y: Integer): Boolean;
begin
  Result := False;   // click-through
end;

function TwgLabel.MeasureSize(AAvailW, AAvailH: Integer): TSize;
var
  lFont: IwgGlyphSource;
begin
  lFont := EffectiveFont;
  Result.cx := CaptionWidth(lFont);
  if lFont <> nil then
    Result.cy := Round(lFont.GetLineHeight)
  else
    Result.cy := 0;
end;

procedure TwgLabel.Paint(ACanvas: TwgCanvas);
var
  lTheme: TwgTheme;
  lFont: IwgGlyphSource;
  lColor: TwgColor;
  lX, lW: Integer;
begin
  lTheme := Theme;
  lFont := EffectiveFont;
  if (lTheme = nil) or (lFont = nil) or (Caption = '') then
    Exit;
  ACanvas.Font := lFont;
  if wsDisabled in States then
    lColor := lTheme.Palette.TextDisabled
  else if FDim then
    lColor := lTheme.Palette.TextDim
  else
    lColor := lTheme.Palette.Text;
  lW := Round(ACanvas.TextWidth(Caption));
  case FAlign of
    chRight:  lX := Width - lW;
    chCenter: lX := (Width - lW) div 2;
    else      lX := 0;
  end;
  ACanvas.DrawTextTopLeft(Caption, lX,
    Round((Height - lFont.GetLineHeight) / 2), lColor);
end;

{ TwgButton }

procedure TwgButton.Paint(ACanvas: TwgCanvas);
var
  lTheme: TwgTheme;
  lFont: IwgGlyphSource;
  lR: TRect;
begin
  lTheme := Theme;
  if lTheme = nil then
    Exit;
  lR := ClientRect;
  // A pressed button shifts down a pixel; cheap, and it reads as tactile.
  if wsPressed in States then
    OffsetRect(lR, 0, 1);
  lTheme.DrawControlFace(ACanvas, lR, States);
  lFont := EffectiveFont;
  if lFont <> nil then
  begin
    ACanvas.Font := lFont;
    lTheme.DrawCaption(ACanvas, lR, Caption, States, chCenter);
  end;
end;

procedure TwgButton.PointerDown(var AEvent: TwgPointerEvent);
begin
  AEvent.Handled := True;   // claim it, so it does not bubble to a container
end;

procedure TwgButton.PointerUp(var AEvent: TwgPointerEvent);
begin
  AEvent.Handled := True;
end;

procedure TwgButton.Click(var AEvent: TwgPointerEvent);
begin
  AEvent.Handled := True;
  Invalidate;
  if Assigned(FOnClick) then
    FOnClick(Self);
end;

procedure TwgButton.KeyDown(var AEvent: TwgKeyEvent);
var
  lFake: TwgPointerEvent;
begin
  if (AEvent.KeySym = wgKeySpace) or (AEvent.KeySym = wgKeyReturn) then
  begin
    lFake := Default(TwgPointerEvent);
    Click(lFake);
    AEvent.Handled := True;
  end;
end;

{ TwgCheckBox }

function TwgCheckBox.BoxSize: Integer;
var
  lTheme: TwgTheme;
begin
  lTheme := Theme;
  if lTheme = nil then
    Exit(16);
  Result := Math.Max(16, lTheme.Metrics.ControlHeight - lTheme.Metrics.Padding);
end;

procedure TwgCheckBox.SetChecked(AValue: Boolean);
begin
  if FChecked = AValue then
    Exit;
  FChecked := AValue;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TwgCheckBox.MeasureSize(AAvailW, AAvailH: Integer): TSize;
var
  lTheme: TwgTheme;
begin
  Result := inherited MeasureSize(AAvailW, AAvailH);
  lTheme := Theme;
  if lTheme <> nil then
    Inc(Result.cx, BoxSize + lTheme.Metrics.Padding);
end;

procedure TwgCheckBox.Paint(ACanvas: TwgCanvas);
var
  lTheme: TwgTheme;
  lFont: IwgGlyphSource;
  lB, lY, lPad: Integer;
  lBox: TRect;
  lFill: TwgColor;
begin
  lTheme := Theme;
  if lTheme = nil then
    Exit;
  lB := BoxSize;
  lY := (Height - lB) div 2;
  lPad := lTheme.Metrics.Padding;
  lBox := Rect(0, lY, lB, lY + lB);

  if FChecked and not (wsDisabled in States) then
    lFill := lTheme.Palette.Accent
  else
    lFill := lTheme.FaceFor(States);
  ACanvas.FillRoundRect(lBox.Left, lBox.Top, lB, lB, 4, 4, lFill);
  lTheme.DrawBorder(ACanvas, lBox, lTheme.Palette.Border);
  if wsFocused in States then
    lTheme.DrawFocusRing(ACanvas, lBox);

  if FChecked then
  begin
    // A tick drawn as two strokes; no glyph needed, so no font dependency.
    ACanvas.LineWidth := Math.Max(2, lB div 8);
    ACanvas.LineCap := clcRound;
    ACanvas.LineJoin := cljRound;
    ACanvas.Polyline([
      wgPointF(lBox.Left + lB * 0.24, lBox.Top + lB * 0.52),
      wgPointF(lBox.Left + lB * 0.44, lBox.Top + lB * 0.72),
      wgPointF(lBox.Left + lB * 0.78, lBox.Top + lB * 0.28)],
      lTheme.Palette.AccentText);
  end;

  lFont := EffectiveFont;
  if (lFont <> nil) and (Caption <> '') then
  begin
    ACanvas.Font := lFont;
    ACanvas.DrawTextTopLeft(Caption, lB + lPad,
      Round((Height - lFont.GetLineHeight) / 2), lTheme.TextFor(States));
  end;
end;

procedure TwgCheckBox.PointerDown(var AEvent: TwgPointerEvent);
begin
  AEvent.Handled := True;
end;

procedure TwgCheckBox.Click(var AEvent: TwgPointerEvent);
begin
  AEvent.Handled := True;
  Checked := not FChecked;
end;

procedure TwgCheckBox.KeyDown(var AEvent: TwgKeyEvent);
begin
  if AEvent.KeySym = wgKeySpace then
  begin
    Checked := not FChecked;
    AEvent.Handled := True;
  end;
end;

{ TwgRadioButton }

procedure TwgRadioButton.Paint(ACanvas: TwgCanvas);
var
  lTheme: TwgTheme;
  lFont: IwgGlyphSource;
  lB, lY, lPad, lCX, lCY: Integer;
  lFill: TwgColor;
begin
  lTheme := Theme;
  if lTheme = nil then
    Exit;
  lB := BoxSize;
  lY := (Height - lB) div 2;
  lPad := lTheme.Metrics.Padding;
  lCX := lB div 2;
  lCY := lY + lB div 2;

  if Checked and not (wsDisabled in States) then
    lFill := lTheme.Palette.Accent
  else
    lFill := lTheme.FaceFor(States);
  ACanvas.FillCircle(lCX, lCY, lB / 2, lFill);
  ACanvas.LineWidth := lTheme.Metrics.BorderWidth;
  ACanvas.Circle(lCX, lCY, lB / 2 - lTheme.Metrics.BorderWidth / 2,
    lTheme.Palette.Border);
  if wsFocused in States then
  begin
    ACanvas.LineWidth := lTheme.Metrics.FocusRingWidth;
    ACanvas.Circle(lCX, lCY, lB / 2 - lTheme.Metrics.FocusRingWidth,
      lTheme.Palette.Focus);
  end;
  if Checked then
    ACanvas.FillCircle(lCX, lCY, lB * 0.22, lTheme.Palette.AccentText);

  lFont := EffectiveFont;
  if (lFont <> nil) and (Caption <> '') then
  begin
    ACanvas.Font := lFont;
    ACanvas.DrawTextTopLeft(Caption, lB + lPad,
      Round((Height - lFont.GetLineHeight) / 2), lTheme.TextFor(States));
  end;
end;

procedure TwgRadioButton.Click(var AEvent: TwgPointerEvent);
var
  i: Integer;
  lSib: TwgWidget;
begin
  AEvent.Handled := True;
  if Checked then
    Exit;   // radios do not toggle off
  // The group is the set of sibling radios, which needs no group id and no
  // registration — re-parenting moves a radio between groups automatically.
  if Parent <> nil then
    for i := 0 to Parent.ChildCount - 1 do
    begin
      lSib := Parent.Children[i];
      if (lSib <> Self) and (lSib is TwgRadioButton) then
        TwgRadioButton(lSib).Checked := False;
    end;
  Checked := True;
end;

{ TwgSlider }

constructor TwgSlider.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMin := 0;
  FMax := 100;
  FValue := 0;
end;

function TwgSlider.KnobRadius: Integer;
var
  lTheme: TwgTheme;
begin
  lTheme := Theme;
  if lTheme = nil then
    Exit(8);
  Result := Math.Max(8, lTheme.Metrics.MinTouchTarget div 3);
end;

function TwgSlider.TrackRect: TRect;
var
  lR, lH: Integer;
begin
  lR := KnobRadius;
  lH := Math.Max(4, lR div 2);
  Result := Rect(lR, (Height - lH) div 2, Width - lR, (Height + lH) div 2);
end;

function TwgSlider.KnobCentre: Integer;
var
  lT: Single;
  lTrack: TRect;
begin
  if FMax > FMin then
    lT := (FValue - FMin) / (FMax - FMin)
  else
    lT := 0;
  lTrack := TrackRect;
  Result := lTrack.Left + Round((lTrack.Right - lTrack.Left) * lT);
end;

function TwgSlider.ValueFromX(X: Integer): Single;
var
  lTrack: TRect;
  lT: Single;
begin
  lTrack := TrackRect;
  if lTrack.Right <= lTrack.Left then
    Exit(FMin);
  lT := (X - lTrack.Left) / (lTrack.Right - lTrack.Left);
  if lT < 0 then lT := 0;
  if lT > 1 then lT := 1;
  Result := FMin + lT * (FMax - FMin);
end;

procedure TwgSlider.SetValue(AValue: Single);
begin
  if AValue < FMin then AValue := FMin;
  if AValue > FMax then AValue := FMax;
  if FValue = AValue then
    Exit;
  FValue := AValue;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TwgSlider.MeasureSize(AAvailW, AAvailH: Integer): TSize;
var
  lTheme: TwgTheme;
begin
  lTheme := Theme;
  Result.cx := 120;
  if lTheme <> nil then
    Result.cy := Math.Max(lTheme.Metrics.ControlHeight,
                            lTheme.Metrics.MinTouchTarget)
  else
    Result.cy := 32;
end;

procedure TwgSlider.Paint(ACanvas: TwgCanvas);
var
  lTheme: TwgTheme;
  lTrack: TRect;
  lCX, lR: Integer;
begin
  lTheme := Theme;
  if lTheme = nil then
    Exit;
  lTrack := TrackRect;
  lR := KnobRadius;
  lCX := KnobCentre;

  ACanvas.FillRoundRect(lTrack.Left, lTrack.Top,
    lTrack.Right - lTrack.Left, lTrack.Bottom - lTrack.Top,
    (lTrack.Bottom - lTrack.Top) div 2, (lTrack.Bottom - lTrack.Top) div 2,
    lTheme.Palette.SurfaceAlt);
  // Filled portion up to the knob.
  if lCX > lTrack.Left then
    ACanvas.FillRoundRect(lTrack.Left, lTrack.Top, lCX - lTrack.Left,
      lTrack.Bottom - lTrack.Top,
      (lTrack.Bottom - lTrack.Top) div 2, (lTrack.Bottom - lTrack.Top) div 2,
      lTheme.Palette.Accent);

  ACanvas.FillCircle(lCX, Height / 2, lR, lTheme.FaceFor(States));
  ACanvas.LineWidth := lTheme.Metrics.BorderWidth;
  ACanvas.Circle(lCX, Height / 2, lR - lTheme.Metrics.BorderWidth / 2,
    lTheme.Palette.Border);
  if wsFocused in States then
  begin
    ACanvas.LineWidth := lTheme.Metrics.FocusRingWidth;
    ACanvas.Circle(lCX, Height / 2, lR - lTheme.Metrics.FocusRingWidth,
      lTheme.Palette.Focus);
  end;
end;

procedure TwgSlider.PointerDown(var AEvent: TwgPointerEvent);
begin
  FDragging := True;
  Value := ValueFromX(AEvent.X);   // jump to where it was clicked
  AEvent.Handled := True;
end;

procedure TwgSlider.PointerMove(var AEvent: TwgPointerEvent);
begin
  if not FDragging then
    Exit;
  // AEvent.X can be far outside the slider — the router holds the grab, which
  // is exactly what makes dragging past the end keep working.
  Value := ValueFromX(AEvent.X);
  AEvent.Handled := True;
end;

procedure TwgSlider.PointerUp(var AEvent: TwgPointerEvent);
begin
  FDragging := False;
  AEvent.Handled := True;
end;

procedure TwgSlider.PointerCancel(var AEvent: TwgPointerEvent);
begin
  // A claimed sequence must not leave the slider stuck in a drag.
  FDragging := False;
  Invalidate;
end;

procedure TwgSlider.KeyDown(var AEvent: TwgKeyEvent);
var
  lStep: Single;
begin
  lStep := (FMax - FMin) / 20;
  case AEvent.KeySym of
    wgKeyLeft, wgKeyDown:  begin Value := FValue - lStep; AEvent.Handled := True; end;
    wgKeyRight, wgKeyUp:   begin Value := FValue + lStep; AEvent.Handled := True; end;
    wgKeyHome:             begin Value := FMin; AEvent.Handled := True; end;
    wgKeyEnd:              begin Value := FMax; AEvent.Handled := True; end;
  end;
end;

{ TwgPanel }

function TwgPanel.CanFocus: Boolean;
begin
  Result := False;
end;

procedure TwgPanel.Paint(ACanvas: TwgCanvas);
var
  lTheme: TwgTheme;
begin
  lTheme := Theme;
  if lTheme = nil then
    Exit;
  lTheme.DrawPanel(ACanvas, ClientRect);
end;

end.
