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

  The scrolling list on the left is the interesting part. It is full of buttons,
  which is exactly the case ordinary input handling cannot serve: a press
  legitimately lands on a button, and only once the pointer has travelled does
  it become a scroll. Click a button and it fires; drag one and the pan
  recogniser claims the sequence, the button is CANCELLED rather than clicked,
  and the list scrolls — then coasts under friction when you let go. Watch the
  click counter to see that a drag never counts as a click.

  Close the window to quit. }
program gl_widget_demo;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, Types, Math,
  fpg_wayland_classes,
  wlg.surface, wlg.canvas.base, wlg.text.fontcache,
  wlg.widget.types, wlg.widget.core, wlg.widget.input, wlg.widget.layout,
  wlg.widget.gesture,      // paVertical — the pan axis the scroll box uses
  wlg.widget.theme, wlg.widget.controls, wlg.widget.scroll, wlg.widget.text,
  wlg.widget.popup, wlg.widget.window,
  wlg.widget.presenter.gl, wlg.widget.keyboard.xkb;

type

  { TDemoButton — a button that says when it was cancelled.

    An ordinary TwgButton simply does not fire when a gesture steals its
    sequence, which is correct but invisible. This one counts the cancels so
    the demo can show the handshake happening rather than only its absence. }

  TDemoButton = class(TwgButton)
  private
    FOnCancelled: TNotifyEvent;
  public
    procedure PointerCancel(var AEvent: TwgPointerEvent); override;
    property OnCancelled: TNotifyEvent read FOnCancelled write FOnCancelled;
  end;

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
    FScroll: TwgScrollBox;
    FEntry: TwgTextEdit;
    FSecret: TwgTextEdit;
    FEcho: TwgLabel;
    FSpinner: TwgSpinner;
    FMenu: TwgPopup;
    FTip: TwgTooltip;
    FPopupWhere: String;
    FShowPopups: Boolean;
    FTipAnchor: TwgButton;
    FTitle: TwgLabel;
    FSpinBtn: TwgButton;
    FRepaints: Integer;
    FLastStatusMs: QWord;
    FClicks: Integer;
    FCancels: Integer;
    FFrames: Integer;
    FStart: QWord;
    FBackend: String;
    procedure BuildUI;
    procedure ButtonClicked(Sender: TObject);
    procedure ButtonCancelled(Sender: TObject);
    procedure EntryChanged(Sender: TObject);
    procedure EntryAccepted(Sender: TObject);
    procedure SpinClicked(Sender: TObject);
    procedure PopupClicked(Sender: TObject);
    procedure TipClicked(Sender: TObject);
    procedure OpenBoth;
    procedure MenuItemClicked(Sender: TObject);
    procedure Repainted(Sender: TObject);
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

{ TDemoButton }

procedure TDemoButton.PointerCancel(var AEvent: TwgPointerEvent);
begin
  inherited PointerCancel(AEvent);
  if Assigned(FOnCancelled) then
    FOnCancelled(Self);
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

  FWin := TwgWindow.Create(FDisplay, 'wlg — widgets', 760, 580);
  FWin.Font := FFonts.GetFont(FTheme.FontFamily, FTheme.FontSize);
  FWin.Window.SurfaceShell.SetServerSideDecorations;

  // The ONLY difference between a CPU-rendered and a GPU-rendered window.
  // Everything below this line — tree, layouts, theme, controls, input — is
  // identical either way.
  FPopupWhere := 'no popup yet';
  FBackend := 'software (wl_shm)';
  if ParamStr(1) = '--gl' then
  begin
    if wgUseGLPresenter(FWin, 2) then
      FBackend := 'OpenGL (dmabuf, 2x AA)'
    else
      FBackend := 'software (GL unavailable, fell back)';
  end;

  // Keysym and UTF-8 translation for wl_keyboard's raw evdev codes. Without
  // it the text fields below would take focus and show a caret but never
  // receive a character — see IwgKeyTranslator.
  wgUseXkbKeyboard(FWin);

  BuildUI;
  FWin.OnPainted := @Repainted;
  // --spin starts the animation immediately, so the loop's animating cost can
  // be measured without a human holding the button down.
  if (ParamStr(1) = '--spin') or (ParamStr(2) = '--spin') then
    SpinClicked(nil);
  { Opens BOTH popups so a screenshot can show each backend at once: the hint
    is anchored to the title at the top, where it fits and therefore uses the
    free overlay; the menu is anchored to a button near the bottom, where it
    does not fit and therefore becomes a real xdg_popup. }
  if (ParamStr(1) = '--popup') or (ParamStr(2) = '--popup') then
    FShowPopups := True;
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
  lRoot, lBody, lLeft, lRight, lList, lRow: TwgPanel;
  lBtn: TwgButton;
  lDemoBtn: TDemoButton;
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
  // The backend is reported in the status line rather than claimed here; this
  // same tree runs on either one.
  lLbl.Caption := 'wlg widget toolkit — desktop theme, ' + FTheme.FontFamily;
  lLbl.Align := chLeft;
  Hint(lLbl, 0, 24);
  FTitle := lLbl;

  lBody := TwgPanel.Create(FWin);
  lBody.Parent := lRoot;
  lBody.Layout := TwgBoxLayout.Create(bdHorizontal, 12, caStretch);
  lBody.Padding := wgMargin(0);
  Hint(lBody, 1);

  { --- left: a scrolling list of buttons --- }
  lLeft := TwgPanel.Create(FWin);
  lLeft.Parent := lBody;
  lLeft.Padding := wgMargin(12);
  lLeft.Layout := TwgBoxLayout.Create(bdVertical, 8, caStretch);
  Hint(lLeft, 1);

  lLbl := TwgLabel.Create(FWin);
  lLbl.Parent := lLeft;
  lLbl.Caption := 'click a button — or DRAG the list to scroll';
  lLbl.Dim := True;
  lLbl.Align := chLeft;
  Hint(lLbl, 0, 20);

  // The viewport. Weight 1 so the box layout gives it the rest of the column:
  // TwgScrollBox measures to a deliberately tiny 64x64, because reporting the
  // content's size would make the layout big enough to need no scrolling.
  FScroll := TwgScrollBox.Create(FWin);
  FScroll.Parent := lLeft;
  FScroll.Axis := paVertical;
  Hint(FScroll, 1);

  // The content. A plain panel with a vertical box layout — the scroll box
  // gives it the viewport's width and as much HEIGHT as it measures to, which
  // is what makes it overflow and therefore scroll.
  lList := TwgPanel.Create(FWin);
  lList.Padding := wgMargin(8);
  lList.Layout := TwgBoxLayout.Create(bdVertical, 6, caStretch);
  FScroll.SetContent(lList);

  for i := 1 to 20 do
  begin
    lDemoBtn := TDemoButton.Create(FWin);
    lDemoBtn.Parent := lList;
    lDemoBtn.Caption := Format('item %d', [i]);
    lDemoBtn.OnClick := @ButtonClicked;
    lDemoBtn.OnCancelled := @ButtonCancelled;
    Hint(lDemoBtn, 0, FTheme.Metrics.ControlHeight);
  end;
  // A disabled one, to show it is neither hit nor focusable.
  lBtn := TwgButton.Create(FWin);
  lBtn.Parent := lList;
  lBtn.Caption := 'disabled';
  lBtn.Enabled := False;
  Hint(lBtn, 0, FTheme.Metrics.ControlHeight);

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
  Hint(FSliderValue, 0, 20);

  { --- text entry --- }
  lLbl := TwgLabel.Create(FWin);
  lLbl.Parent := lRight;
  lLbl.Caption := 'type here — select, drag, double-click, Ctrl+A/C/X/V';
  lLbl.Dim := True;
  lLbl.Align := chLeft;
  Hint(lLbl, 0, 20);

  FEntry := TwgTextEdit.Create(FWin);
  FEntry.Parent := lRight;
  FEntry.Placeholder := 'your name';
  FEntry.OnChange := @EntryChanged;
  FEntry.OnAccept := @EntryAccepted;
  Hint(FEntry, 0, FTheme.Metrics.ControlHeight);

  FSecret := TwgTextEdit.Create(FWin);
  FSecret.Parent := lRight;
  FSecret.Placeholder := 'a password';
  FSecret.PasswordChar := '*';
  FSecret.MaxLength := 32;
  Hint(FSecret, 0, FTheme.Metrics.ControlHeight);

  FEcho := TwgLabel.Create(FWin);
  FEcho.Parent := lRight;
  FEcho.Caption := '(nothing typed yet)';
  FEcho.Dim := True;
  FEcho.Align := chLeft;
  Hint(FEcho, 1, 20);

  { --- popups: the same popup, two backends, chosen by whether it fits --- }
  lRow := TwgPanel.Create(FWin);
  lRow.Parent := lRight;
  lRow.Padding := wgMargin(0);
  lRow.Layout := TwgBoxLayout.Create(bdHorizontal, 8, caCenter);
  Hint(lRow, 0, FTheme.Metrics.ControlHeight);

  lBtn := TwgButton.Create(FWin);
  lBtn.Parent := lRow;
  lBtn.Caption := 'menu';
  lBtn.OnClick := @PopupClicked;
  Hint(lBtn, 1, FTheme.Metrics.ControlHeight);

  FTipAnchor := TwgButton.Create(FWin);
  FTipAnchor.Parent := lRow;
  FTipAnchor.Caption := 'hint';
  FTipAnchor.OnClick := @TipClicked;
  Hint(FTipAnchor, 1, FTheme.Metrics.ControlHeight);

  { --- a continuous animation, to show the loop adapt --- }
  lRow := TwgPanel.Create(FWin);
  lRow.Parent := lRight;
  lRow.Padding := wgMargin(0);
  lRow.Layout := TwgBoxLayout.Create(bdHorizontal, 8, caCenter);
  Hint(lRow, 0, FTheme.Metrics.ControlHeight);

  FSpinner := TwgSpinner.Create(FWin);
  FSpinner.Parent := lRow;
  Hint(FSpinner, 0, FTheme.Metrics.ControlHeight);

  FSpinBtn := TwgButton.Create(FWin);
  FSpinBtn.Parent := lRow;
  FSpinBtn.Caption := 'start spinner';
  FSpinBtn.OnClick := @SpinClicked;
  Hint(FSpinBtn, 1, FTheme.Metrics.ControlHeight);

  { --- status --- }
  FStatus := TwgLabel.Create(FWin);
  FStatus.Parent := lRoot;
  FStatus.Align := chLeft;
  FStatus.Dim := True;
  Hint(FStatus, 0, 22);

  // The pan recogniser has to be registered with the router, and a scroll box
  // has no way to reach one on its own — it only knows its parent chain, not
  // the window at the top of it. Doing it here, once the tree is assembled, is
  // the whole of the wiring.
  FScroll.AttachTo(FWin.Router);
end;

procedure TApp.ButtonClicked(Sender: TObject);
begin
  Inc(FClicks);
end;

procedure TApp.ButtonCancelled(Sender: TObject);
begin
  // The pan claimed the sequence out from under this button. It was pressed,
  // it is now unwinding, and it must NOT count as a click.
  Inc(FCancels);
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

procedure TApp.EntryChanged(Sender: TObject);
begin
  if FEntry.Text = '' then
    FEcho.Caption := '(nothing typed yet)'
  else
    FEcho.Caption := Format('%d bytes: "%s"', [Length(FEntry.Text), FEntry.Text]);
end;

procedure TApp.EntryAccepted(Sender: TObject);
begin
  FEcho.Caption := Format('accepted: "%s"', [FEntry.Text]);
end;

{ One popup, opened from a button near the bottom of the window. Its content
  does not fit below the anchor, so the fit rule picks an xdg_popup; drag the
  window up until it does fit and the same call uses the free overlay path
  instead. The status line reports which. }
procedure TApp.PopupClicked(Sender: TObject);
var
  lPanel: TwgPanel;
  lItem: TwgButton;
  i: Integer;
begin
  if FMenu = nil then
  begin
    FMenu := TwgPopup.Create(FWin);
    FMenu.Grab := True;          // a menu wants dismiss-on-outside-click
    lPanel := TwgPanel.Create(FMenu);
    lPanel.Layout := TwgBoxLayout.Create(bdVertical, 4, caStretch);
    lPanel.Padding := wgMargin(0);
    for i := 1 to 3 do
    begin
      lItem := TwgButton.Create(FMenu);
      lItem.Parent := lPanel;
      lItem.Caption := Format('menu item %d', [i]);
      lItem.OnClick := @MenuItemClicked;
      Hint(lItem, 0, FTheme.Metrics.ControlHeight);
    end;
    FMenu.SetContent(lPanel);
  end;
  if FMenu.IsOpen then
    FMenu.Close
  else
  begin
    FMenu.ShowFor(TwgWidget(Sender), Rect(0, 0, 0, 0));
    if FMenu.UsedSurface then
    begin
      FPopupWhere := FPopupWhere + ' menu=surface';
      WriteLn(Format('menu: asked for %d,%d %dx%d; compositor put it at %d,%d',
        [FMenu.RequestedRect.Left, FMenu.RequestedRect.Top,
         FMenu.RequestedRect.Right - FMenu.RequestedRect.Left,
         FMenu.RequestedRect.Bottom - FMenu.RequestedRect.Top,
         FMenu.SurfaceWindow.Window.PopupX, FMenu.SurfaceWindow.Window.PopupY]));
      Flush(Output);
    end
    else
      FPopupWhere := FPopupWhere + ' menu=overlay';
  end;
end;

procedure TApp.MenuItemClicked(Sender: TObject);
begin
  FPopupWhere := 'chose ' + TwgButton(Sender).Caption;
  FMenu.Close;
end;

{ A hint, same machinery, never grabbing — a tooltip that took the pointer
  grab would stop you clicking the thing it describes. }
procedure TApp.TipClicked(Sender: TObject);
begin
  if FTip = nil then
  begin
    FTip := TwgTooltip.Create(FWin);
    FTip.Text := 'a hint — same two backends, same fit rule';
  end;
  if FTip.IsOpen then
    FTip.Close
  else
  begin
    FTip.ShowFor(TwgWidget(Sender), Rect(0, 0, 0, 0));
    if FTip.UsedSurface then
      FPopupWhere := 'hint=surface'
    else
      FPopupWhere := 'hint=overlay';
  end;
end;

procedure TApp.OpenBoth;
begin
  FShowPopups := False;
  TipClicked(FTitle);          // top of the window: fits -> overlay
  PopupClicked(FTipAnchor);    // bottom of the window: does not fit -> surface
end;

procedure TApp.SpinClicked(Sender: TObject);
begin
  FSpinner.Active := not FSpinner.Active;
  if FSpinner.Active then
    FSpinBtn.Caption := 'stop spinner'
  else
    FSpinBtn.Caption := 'start spinner';
end;

{ Counts what actually reached the compositor, which is the only number worth
  reporting. The old counter counted LOOP ITERATIONS and updated a label every
  one of them — so it dirtied the window every iteration and then reported the
  resulting repaint rate as if it were a benchmark. It was measuring itself. }
procedure TApp.Repainted(Sender: TObject);
begin
  Inc(FRepaints);
  { Open the demo popups only once something has actually been painted, which
    means the layout has run. Anchoring to a widget that has not been laid out
    yet gives its bounds as 0x0 at the origin, and the popup lands in the
    corner rather than at the button. }
  { Wait until the anchor has actually been laid out. A widget with 0x0 bounds
    anchors the popup at the window origin, which looks like a positioning bug
    but is just an impatient caller. }
  if FShowPopups and (FTipAnchor.Width > 0) then
    OpenBoth;
end;

procedure TApp.Tick;
var
  lSecs: Double;
begin
  { Update at most twice a second. Rewriting this label is itself a damage
    event, so doing it every iteration is a self-sustaining repaint loop — it
    was costing 22% of a core to display a window that was doing nothing. }
  if GetTickCount64 - FLastStatusMs < 500 then
    Exit;
  FLastStatusMs := GetTickCount64;
  { Ask to be woken for the next update. The loop BLOCKS when nothing is
    damaged and nothing is scheduled, so an application that wants periodic
    work has to say so — that is the whole point of the adaptive loop. Any
    widget will do as the peg; the wake is what matters. }
  FStatus.RequestTick(500);
  lSecs := (GetTickCount64 - FStart) / 1000.0;
  if lSecs <= 0 then
    Exit;
  FStatus.Caption := Format(
    '%d repaints · %.1f/s · %d clicks · %s · %s',
    [FRepaints, FRepaints / lSecs, FClicks, FPopupWhere, FBackend]);
end;

procedure TApp.Run;
begin
  WriteLn('widget demo open (', FBackend, ') — close the window to quit');
  WriteLn('  drag the list to scroll (or use the wheel); flick it to coast');
  WriteLn('  Tab to the text fields and type; Ctrl+A/C/X/V work');
  WriteLn('  the spinner button starts a continuous animation — watch the rate');
  WriteLn('  pass --gl to render on the GPU');
  Flush(Output);
  while not FWin.Closed do
  begin
    { The window says how long it may sleep: -1 (block until the compositor
      says something) when nothing is damaged and nothing is animating, the
      time until the next caret blink or spinner frame otherwise. Hard-coding
      an interval here is choosing to wake that often forever. }
    FDisplay.WaitEvent(FWin.WaitTimeout);
    if FWin.Window.Configured then
      Tick;
    FWin.ProcessFrame;
  end;
  WriteLn(Format('presented %d repaints, %d clicks, %d cancelled by the pan',
    [FRepaints, FClicks, FCancels]));
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
