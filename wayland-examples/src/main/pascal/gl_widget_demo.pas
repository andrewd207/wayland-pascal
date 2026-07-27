// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ gl_widget_demo — the widget toolkit in a real Wayland window.

  Despite the gl_ prefix (which is only what makes the Makefile link freetype
  and fontconfig) this runs on the SOFTWARE canvas: TwgWindow defaults to
  TwgShmPresenter, drawing into the window's own wl_shm buffers with no GPU
  involved. The same tree runs on the GL presenter unchanged.

  It exercises the whole stack: real controls from wlg.widget.controls, a theme
  seeded from the running desktop, box layouts with weights (no hard-coded
  coordinates anywhere), damage-driven partial repaint, and the input router's
  hover, press, click, focus, Tab traversal and drag capture.

  Close the window to quit. }
program gl_widget_demo;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, Types, Math,
  fpg_wayland_classes,
  wlg.surface, wlg.canvas.base, wlg.text.fontcache,
  wlg.widget.types, wlg.widget.core, wlg.widget.input, wlg.widget.layout,
  wlg.widget.theme, wlg.widget.controls, wlg.widget.window,
  wlg.widget.presenter.gl;

type

  { TApp }

  TApp = class
  private
    FDisplay: TfpgwDisplay;
    FWin: TwgWindow;
    FFonts: TwgFontCache;
    FTheme: TwgDesktopTheme;
    FStatus: TwgLabel;
    FSliderValue: TwgLabel;
    FSlider: TwgSlider;
    FCheck: TwgCheckBox;
    FClicks: Integer;
    FFrames: Integer;
    FStart: QWord;
    FBackend: String;
    procedure BuildUI;
    procedure ButtonClicked(Sender: TObject);
    procedure SliderChanged(Sender: TObject);
    procedure CheckChanged(Sender: TObject);
    procedure Tick;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run;
  end;

{ Hints live on the CHILD, so a small helper keeps the calls readable. }
procedure Hint(AWidget: TwgWidget; AWeight: Single; AMinH: Integer = 0);
var
  h: TwgLayoutHints;
begin
  h := AWidget.LayoutHints;
  h.Weight := AWeight;
  if AMinH > 0 then
    h.MinHeight := AMinH;
  AWidget.LayoutHints := h;
end;

{ TApp }

constructor TApp.Create;
begin
  inherited Create;
  FDisplay := TfpgwDisplay.Create(nil, '');
  if not FDisplay.Connected then
    raise Exception.Create(
      'could not connect to a Wayland compositor (is WAYLAND_DISPLAY set?)');
  FDisplay.AfterCreate;

  // The theme reads the running desktop for scheme, accent and UI font, so
  // the font cache is asked for whatever GNOME/KDE actually specifies.
  FTheme := TwgDesktopTheme.Create;
  FFonts := TwgFontCache.Create;

  FWin := TwgWindow.Create(FDisplay, 'wlg — widgets', 760, 500);
  FWin.Font := FFonts.GetFont(FTheme.FontFamily, FTheme.FontSize);
  FWin.Window.SurfaceShell.SetServerSideDecorations;

  // The ONLY difference between a CPU-rendered and a GPU-rendered window.
  // Everything below this line — tree, layouts, theme, controls, input — is
  // identical either way.
  FBackend := 'software (wl_shm)';
  if ParamStr(1) = '--gl' then
  begin
    if wgUseGLPresenter(FWin, 2) then
      FBackend := 'OpenGL (dmabuf, 2x AA)'
    else
      FBackend := 'software (GL unavailable, fell back)';
  end;

  BuildUI;
  FStart := GetTickCount64;
end;

destructor TApp.Destroy;
begin
  FWin.Free;
  FFonts.Free;
  FTheme.Free;
  FDisplay.Free;
  inherited Destroy;
end;

procedure TApp.BuildUI;
var
  lRoot, lBody, lLeft, lRight: TwgPanel;
  lBtn: TwgButton;
  lRadio: TwgRadioButton;
  lLbl: TwgLabel;
  i: Integer;
begin
  // The ROOT needs a layout, or nothing below it is ever given bounds.
  FWin.Root.Layout := TwgBoxLayout.Create(bdVertical, 0, caStretch);

  lRoot := TwgPanel.Create(FWin);
  lRoot.Parent := FWin.Root;
  lRoot.SetTheme(FTheme);          // set once; every descendant inherits it
  lRoot.Padding := wgMargin(14);
  lRoot.Layout := TwgBoxLayout.Create(bdVertical, 12, caStretch);
  Hint(lRoot, 1);

  lLbl := TwgLabel.Create(FWin);
  lLbl.Parent := lRoot;
  lLbl.Caption := 'wlg widget toolkit — software canvas, desktop theme';
  lLbl.Align := chLeft;
  Hint(lLbl, 0, 24);

  lBody := TwgPanel.Create(FWin);
  lBody.Parent := lRoot;
  lBody.Layout := TwgBoxLayout.Create(bdHorizontal, 12, caStretch);
  lBody.Padding := wgMargin(0);
  Hint(lBody, 1);

  { --- left: buttons --- }
  lLeft := TwgPanel.Create(FWin);
  lLeft.Parent := lBody;
  lLeft.Padding := wgMargin(12);
  lLeft.Layout := TwgBoxLayout.Create(bdVertical, 8, caStretch);
  Hint(lLeft, 1);

  lLbl := TwgLabel.Create(FWin);
  lLbl.Parent := lLeft;
  lLbl.Caption := 'buttons — hover, click, Tab, Space';
  lLbl.Dim := True;
  lLbl.Align := chLeft;
  Hint(lLbl, 0, 20);

  for i := 1 to 3 do
  begin
    lBtn := TwgButton.Create(FWin);
    lBtn.Parent := lLeft;
    lBtn.Caption := Format('button %d', [i]);
    lBtn.OnClick := @ButtonClicked;
    Hint(lBtn, 0, FTheme.Metrics.ControlHeight);
  end;
  // A disabled one, to show it is neither hit nor focusable.
  lBtn := TwgButton.Create(FWin);
  lBtn.Parent := lLeft;
  lBtn.Caption := 'disabled';
  lBtn.Enabled := False;
  Hint(lBtn, 0, FTheme.Metrics.ControlHeight);
  Hint(TwgWidget(lLeft.Children[lLeft.ChildCount - 1]), 0,
       FTheme.Metrics.ControlHeight);

  { --- right: toggles and a slider --- }
  lRight := TwgPanel.Create(FWin);
  lRight.Parent := lBody;
  lRight.Padding := wgMargin(12);
  lRight.Layout := TwgBoxLayout.Create(bdVertical, 8, caStretch);
  Hint(lRight, 1);

  lLbl := TwgLabel.Create(FWin);
  lLbl.Parent := lRight;
  lLbl.Caption := 'toggles and a slider';
  lLbl.Dim := True;
  lLbl.Align := chLeft;
  Hint(lLbl, 0, 20);

  FCheck := TwgCheckBox.Create(FWin);
  FCheck.Parent := lRight;
  FCheck.Caption := 'a checkbox';
  FCheck.OnChange := @CheckChanged;
  Hint(FCheck, 0, FTheme.Metrics.ControlHeight);

  for i := 1 to 2 do
  begin
    lRadio := TwgRadioButton.Create(FWin);
    lRadio.Parent := lRight;
    lRadio.Caption := Format('option %d', [i]);
    lRadio.Checked := i = 1;
    Hint(lRadio, 0, FTheme.Metrics.ControlHeight);
  end;

  FSlider := TwgSlider.Create(FWin);
  FSlider.Parent := lRight;
  FSlider.Value := 35;
  FSlider.OnChange := @SliderChanged;
  Hint(FSlider, 0, FTheme.Metrics.ControlHeight);

  FSliderValue := TwgLabel.Create(FWin);
  FSliderValue.Parent := lRight;
  FSliderValue.Caption := 'slider: 35 — drag past the edge, it keeps tracking';
  FSliderValue.Dim := True;
  FSliderValue.Align := chLeft;
  Hint(FSliderValue, 1, 20);

  { --- status --- }
  FStatus := TwgLabel.Create(FWin);
  FStatus.Parent := lRoot;
  FStatus.Align := chLeft;
  FStatus.Dim := True;
  Hint(FStatus, 0, 22);
end;

procedure TApp.ButtonClicked(Sender: TObject);
begin
  Inc(FClicks);
end;

procedure TApp.SliderChanged(Sender: TObject);
begin
  FSliderValue.Caption := Format(
    'slider: %.0f — drag past the edge, it keeps tracking', [FSlider.Value]);
end;

procedure TApp.CheckChanged(Sender: TObject);
begin
  // Nothing to do; the control repaints itself from its own state.
end;

procedure TApp.Tick;
var
  lSecs: Double;
begin
  Inc(FFrames);
  lSecs := (GetTickCount64 - FStart) / 1000.0;
  if lSecs <= 0 then
    Exit;
  FStatus.Caption := Format('%d frames · %.0f fps · %d clicks · %s · %s',
    [FFrames, FFrames / lSecs, FClicks, FBackend, FTheme.FontFamily]);
end;

procedure TApp.Run;
begin
  WriteLn('widget demo open (', FBackend, ') — close the window to quit');
  WriteLn('  pass --gl to render on the GPU');
  Flush(Output);
  while not FWin.Closed do
  begin
    FDisplay.WaitEvent(16);
    if FWin.Window.Configured then
      Tick;
    FWin.ProcessFrame;
  end;
  WriteLn(Format('presented %d frames, %d clicks', [FFrames, FClicks]));
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
