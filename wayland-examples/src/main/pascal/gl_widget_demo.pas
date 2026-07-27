// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ gl_widget_demo — a widget tree in a real Wayland window.

  Despite the gl_ prefix (which is what makes the Makefile link libfreetype and
  libfontconfig for the font cache), this runs on the SOFTWARE canvas: TwgWindow
  defaults to TwgShmPresenter, drawing into the window's own wl_shm buffers with
  no GPU involved. That is the point — the same widget tree will run on the GL
  presenter when it lands, unchanged.

  What it demonstrates:

    * a nested widget tree painting itself into a live surface
    * damage-driven PARTIAL repaint: the animated box invalidates only itself,
      so each frame repaints ~1% of the window rather than all of it
    * per-buffer damage: with double buffering, a change must be repainted into
      both buffers before it stops reappearing, and the counter proves it
    * text through the fontconfig-backed font cache
    * child clipping, and resize handling

  Close the window to quit. }
program gl_widget_demo;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, Types, Math, StrUtils,
  fpg_wayland_classes,
  wlg.surface, wlg.canvas.base,
  wlg.text.fontcache,
  wlg.widget.types, wlg.widget.core, wlg.widget.input, wlg.widget.layout,
  wlg.widget.window;

type

  { TBox — a coloured panel that paints its own background and a caption.

    Painting its OWN background matters: a partial repaint never clears the
    surface, so anything that does not draw its background leaves stale pixels. }

  TBox = class(TwgWidget)
  private
    FColor: TwgColor;
    FCaption: String;
    FRadius: Integer;
  protected
    procedure Paint(ACanvas: TwgCanvas); override;
  public
    property Color: TwgColor read FColor write FColor;
    property Caption: String read FCaption write FCaption;
    property Radius: Integer read FRadius write FRadius;
  end;

  { TButton — an actual interactive widget.

    Implements IwgInputTarget, which is how the router finds it. Note that it
    paints from States rather than tracking its own hover/press flags: the
    router maintains those, so the visual and the routing can never disagree. }

  TButton = class(TwgWidget, IwgInputTarget)
  private
    FCaption: String;
    FClicks: Integer;
    FOnClick: TNotifyEvent;
  protected
    procedure Paint(ACanvas: TwgCanvas); override;
  public
    { IwgInputTarget }
    procedure PointerDown(var AEvent: TwgPointerEvent);
    procedure PointerUp(var AEvent: TwgPointerEvent);
    procedure PointerMove(var AEvent: TwgPointerEvent);
    procedure PointerEnter(var AEvent: TwgPointerEvent);
    procedure PointerLeave(var AEvent: TwgPointerEvent);
    procedure Click(var AEvent: TwgPointerEvent);
    procedure PointerCancel(var AEvent: TwgPointerEvent);
    procedure Scroll(var AEvent: TwgScrollEvent);
    procedure KeyDown(var AEvent: TwgKeyEvent);
    procedure KeyUp(var AEvent: TwgKeyEvent);
    procedure FocusIn;
    procedure FocusOut;
    function  CanFocus: Boolean;

    property Caption: String read FCaption write FCaption;
    property Clicks: Integer read FClicks;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
  end;

  { TApp }

  TApp = class
  private
    FDisplay: TfpgwDisplay;
    FWin: TwgWindow;
    FFonts: TwgFontCache;
    FPanel: TBox;
    FMover: TBox;
    FStatus: TBox;
    FMoverStrip: TwgWidget;
    FButtons: array[0..2] of TButton;
    FLastClicked: String;
    FFrames: Integer;
    FStart: QWord;
    FDirX: Integer;
    procedure BuildUI;
    procedure ButtonClicked(Sender: TObject);
    procedure Animate;
    procedure DoLayout(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run;
  end;

{ TBox }

procedure TBox.Paint(ACanvas: TwgCanvas);
var
  lFont: IwgGlyphSource;
begin
  if FRadius > 0 then
    ACanvas.FillRoundRect(0, 0, Width, Height, FRadius, FRadius, FColor)
  else
    ACanvas.FillRect(0, 0, Width, Height, FColor);

  ACanvas.LineWidth := 1;
  if FRadius > 0 then
    ACanvas.RoundRect(0.5, 0.5, Width - 1, Height - 1, FRadius, FRadius,
      wgARGB(70, 255, 255, 255))
  else
    ACanvas.Rectangle(0.5, 0.5, Width - 1, Height - 1, wgARGB(70, 255, 255, 255));

  if FCaption <> '' then
  begin
    lFont := EffectiveFont;
    if lFont <> nil then
    begin
      ACanvas.Font := lFont;
      ACanvas.DrawTextTopLeft(FCaption, 10, 7, wgARGB(255, 240, 243, 250));
    end;
  end;
end;

{ TButton }

procedure TButton.Paint(ACanvas: TwgCanvas);
var
  lFace, lText: TwgColor;
  lFont: IwgGlyphSource;
  lDY: Integer;
begin
  // Straight from the router-maintained state set.
  if wsDisabled in States then
    lFace := wgARGB(255, 48, 52, 62)
  else if wsPressed in States then
    lFace := wgARGB(255, 44, 92, 168)
  else if wsHovered in States then
    lFace := wgARGB(255, 92, 152, 240)
  else
    lFace := wgARGB(255, 70, 122, 210);

  if wsPressed in States then lDY := 1 else lDY := 0;

  ACanvas.FillRoundRect(0, lDY, Width, Height - lDY, 8, 8, lFace);
  if wsFocused in States then
  begin
    // Focus ring, so keyboard traversal is visible.
    ACanvas.LineWidth := 2;
    ACanvas.RoundRect(1, 1 + lDY, Width - 2, Height - 2 - lDY, 8, 8,
      wgARGB(255, 250, 220, 120));
  end;

  lFont := EffectiveFont;
  if lFont <> nil then
  begin
    ACanvas.Font := lFont;
    lText := wgARGB(255, 245, 248, 255);
    ACanvas.DrawTextTopLeft(Format('%s (%d)', [FCaption, FClicks]),
      Round((Width - ACanvas.TextWidth(Format('%s (%d)', [FCaption, FClicks]))) / 2),
      Round((Height - lFont.GetLineHeight) / 2) + lDY, lText);
  end;
end;

procedure TButton.PointerDown(var AEvent: TwgPointerEvent);
begin
  AEvent.Handled := True;   // claim it, so it does not bubble to the panel
end;

procedure TButton.PointerUp(var AEvent: TwgPointerEvent);
begin
  AEvent.Handled := True;
end;

procedure TButton.Click(var AEvent: TwgPointerEvent);
begin
  Inc(FClicks);
  Invalidate;
  AEvent.Handled := True;
  if Assigned(FOnClick) then
    FOnClick(Self);
end;

procedure TButton.PointerCancel(var AEvent: TwgPointerEvent);
begin
  // A gesture or the compositor took the sequence: unwind, do NOT click.
  Invalidate;
end;

procedure TButton.PointerMove(var AEvent: TwgPointerEvent); begin end;
procedure TButton.PointerEnter(var AEvent: TwgPointerEvent); begin end;
procedure TButton.PointerLeave(var AEvent: TwgPointerEvent); begin end;
procedure TButton.Scroll(var AEvent: TwgScrollEvent); begin end;
procedure TButton.KeyUp(var AEvent: TwgKeyEvent); begin end;
procedure TButton.FocusIn; begin Invalidate; end;
procedure TButton.FocusOut; begin Invalidate; end;
function  TButton.CanFocus: Boolean; begin Result := Enabled and Visible; end;

procedure TButton.KeyDown(var AEvent: TwgKeyEvent);
var
  lFake: TwgPointerEvent;
begin
  // Space and Return activate a focused button, as they should.
  if (AEvent.KeySym = wgKeySpace) or (AEvent.KeySym = wgKeyReturn) then
  begin
    lFake := Default(TwgPointerEvent);
    Click(lFake);
    AEvent.Handled := True;
  end;
end;

{ TApp }

constructor TApp.Create;
begin
  inherited Create;
  FDirX := 3;
  FDisplay := TfpgwDisplay.Create(nil, '');
  if not FDisplay.Connected then
    raise Exception.Create(
      'could not connect to a Wayland compositor (is WAYLAND_DISPLAY set?)');
  // Binds the registry globals. A window cannot be created before this.
  FDisplay.AfterCreate;
  FFonts := TwgFontCache.Create;

  FWin := TwgWindow.Create(FDisplay, 'wlg — widget tree (software canvas)', 720, 460);
  FWin.Font := FFonts.GetFont('Sans', 10);
  FWin.OnLayout := @DoLayout;
  FWin.Window.SurfaceShell.SetServerSideDecorations;

  BuildUI;
  FStart := GetTickCount64;
end;

destructor TApp.Destroy;
begin
  FWin.Free;
  FFonts.Free;
  FDisplay.Free;
  inherited Destroy;
end;

procedure TApp.BuildUI;
var
  lBg, lRow, lCol: TwgWidget;
  lChild: TBox;
  lHints: TwgLayoutHints;
  i: Integer;

  // Hints live on the CHILD, so this is the ergonomic way to set them.
  procedure Hint(AWidget: TwgWidget; AWeight: Single; AMargin: Integer);
  var h: TwgLayoutHints;
  begin
    h := AWidget.LayoutHints;
    h.Weight := AWeight;
    h.Margin := wgMargin(AMargin);
    AWidget.LayoutHints := h;
  end;

begin
  // The ROOT needs a layout too, or nothing below it is ever given bounds —
  // TwgWindow sizes the root, and the root's layout sizes what is inside.
  FWin.Root.Layout := TwgBoxLayout.Create(bdVertical, 0, caStretch);

  // Backdrop fills the window and is itself a vertical box: content on top,
  // status bar pinned below. No coordinates anywhere in this routine.
  lBg := TBox.Create(FWin);
  lBg.Parent := FWin.Root;
  TBox(lBg).Color := wgARGB(255, 20, 24, 34);
  lBg.Padding := wgMargin(16);
  lBg.Layout := TwgBoxLayout.Create(bdVertical, 12, caStretch);
  Hint(lBg, 1, 0);   // weighted, so it takes the whole root

  // A row: panel on the left (weighted, so it takes the slack) and a column
  // of buttons on the right at its natural width.
  lRow := TwgWidget.Create(FWin);
  lRow.Parent := lBg;
  lRow.Layout := TwgBoxLayout.Create(bdHorizontal, 16, caStretch);
  Hint(lRow, 1, 0);

  FPanel := TBox.Create(FWin);
  FPanel.Parent := lRow;
  FPanel.Color := wgARGB(255, 36, 44, 64);
  FPanel.Radius := 14;
  FPanel.Caption := 'panel — vertical box, weighted children';
  FPanel.Padding := wgMargin(14, 34, 14, 14);
  FPanel.Layout := TwgBoxLayout.Create(bdVertical, 8, caStretch);
  Hint(FPanel, 1, 0);

  for i := 0 to 2 do
  begin
    lChild := TBox.Create(FWin);
    lChild.Parent := FPanel;
    lChild.Radius := 8;
    lChild.Caption := Format('child %d (weight %d)', [i + 1, i]);
    case i of
      0: lChild.Color := wgARGB(255, 70, 130, 220);
      1: lChild.Color := wgARGB(255, 220, 120, 70);
      2: lChild.Color := wgARGB(230, 120, 200, 140);
    end;
    // Weights 0, 1, 2 — the slack divides 1:2 between the last two.
    Hint(lChild, i, 0);
    // A weight-0 child keeps its NATURAL size, and TBox has no intrinsic one
    // (it reports its current bounds, initially zero), so give it a minimum.
    // Without this, child 1 collapses to nothing — correct, but not a useful
    // demonstration.
    lHints := lChild.LayoutHints;
    lHints.MinHeight := 48;
    lChild.LayoutHints := lHints;
  end;

  lCol := TwgWidget.Create(FWin);
  lCol.Parent := lRow;
  lCol.Layout := TwgBoxLayout.Create(bdVertical, 10, caStretch);
  lCol.LayoutHints := lCol.LayoutHints;   // natural width, no weight

  for i := 0 to 2 do
  begin
    FButtons[i] := TButton.Create(FWin);
    FButtons[i].Parent := lCol;
    FButtons[i].Caption := Format('button %d', [i + 1]);
    FButtons[i].OnClick := @ButtonClicked;
    Hint(FButtons[i], 0, 0);
    // Minimum size via hints rather than SetBounds; the layout honours it.
    lHints := FButtons[i].LayoutHints;
    lHints.MinWidth := 200;
    lHints.MinHeight := 44;
    FButtons[i].LayoutHints := lHints;
  end;
  FButtons[2].Enabled := False;   // proves disabled widgets are not hit

  FMover := TBox.Create(FWin);
  FMover.Parent := lBg;
  FMover.Color := wgARGB(255, 240, 90, 140);
  FMover.Radius := 10;
  FMover.Caption := 'moving';
  // Not laid out: the animation drives its bounds directly, which is exactly
  // what a box layout would fight over, so it goes in its own fixed strip.
  FMoverStrip := TwgWidget.Create(FWin);
  FMoverStrip.Parent := lBg;
  FMover.Parent := FMoverStrip;
  FMover.SetBounds(0, 0, 120, 56);
  lHints := FMoverStrip.LayoutHints;
  lHints.MinHeight := 56;
  FMoverStrip.LayoutHints := lHints;

  FStatus := TBox.Create(FWin);
  FStatus.Parent := lBg;
  FStatus.Color := wgARGB(255, 28, 34, 48);
  FStatus.Radius := 8;
  lHints := FStatus.LayoutHints;
  lHints.MinHeight := 46;
  FStatus.LayoutHints := lHints;
end;

procedure TApp.ButtonClicked(Sender: TObject);
begin
  FLastClicked := Format('%s clicked %d time(s)',
    [TButton(Sender).Caption, TButton(Sender).Clicks]);
end;

procedure TApp.DoLayout(Sender: TObject);
begin
  // Nothing to do: the box layouts handle the whole form, including resize.
  // Kept so the hook is visible in the example.
end;

procedure TApp.Animate;
var
  lX: Integer;
  lSecs: Double;
begin
  lX := FMover.Left + FDirX;
  if (lX < 0) or (lX + FMover.Width > FMoverStrip.Width) then
  begin
    FDirX := -FDirX;
    lX := FMover.Left + FDirX;
  end;
  // SetBounds invalidates BOTH the vacated and the newly occupied rectangles
  // through the parent, which is what keeps the trail clean.
  FMover.SetBounds(lX, FMover.Top, FMover.Width, FMover.Height);

  Inc(FFrames);
  lSecs := (GetTickCount64 - FStart) / 1000.0;
  if lSecs > 0 then
    FStatus.Caption := Format(
      '%d frames · %.1f fps · %s',
      [FFrames, FFrames / lSecs,
       IfThen(FLastClicked = '',
              'hover/click the buttons · Tab to move focus · Space to press',
              FLastClicked)]);
  FStatus.Invalidate;
end;

procedure TApp.Run;
begin
  WriteLn('widget demo open — close the window to quit');
  Flush(Output);
  while not FWin.Closed do
  begin
    FDisplay.WaitEvent(16);
    if FWin.Window.Configured then
      Animate;
    FWin.ProcessFrame;
  end;
  WriteLn(Format('presented %d frames', [FFrames]));
end;

var
  lApp: TApp;
begin
  lApp := TApp.Create;
  try
    lApp.Run;
  finally
    lApp.Free;
  end;
end.
