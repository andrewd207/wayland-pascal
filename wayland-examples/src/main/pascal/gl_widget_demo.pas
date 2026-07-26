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
  SysUtils, Classes, Types, Math,
  fpg_wayland_classes,
  wlg.surface, wlg.canvas.base,
  wlg.text.fontcache,
  wlg.widget.types, wlg.widget.core, wlg.widget.window;

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

  { TApp }

  TApp = class
  private
    FDisplay: TfpgwDisplay;
    FWin: TwgWindow;
    FFonts: TwgFontCache;
    FPanel: TBox;
    FMover: TBox;
    FStatus: TBox;
    FFrames: Integer;
    FStart: QWord;
    FDirX: Integer;
    procedure BuildUI;
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
  lRoot, lBg, lChild: TwgWidget;
  i: Integer;
begin
  lRoot := FWin.Root;

  // Opaque backdrop. The root TwgWidget paints nothing, so without this a
  // partial repaint would show whatever was in the buffer before.
  lBg := TBox.Create(FWin);
  lBg.Parent := lRoot;
  TBox(lBg).Color := wgARGB(255, 20, 24, 34);
  TBox(lBg).Radius := 0;
  lBg.SetBounds(0, 0, 720, 460);

  FPanel := TBox.Create(FWin);
  FPanel.Parent := lBg;
  FPanel.Color := wgARGB(255, 36, 44, 64);
  FPanel.Radius := 14;
  FPanel.Caption := 'panel — children are clipped to me';
  FPanel.SetBounds(24, 24, 420, 240);

  for i := 0 to 2 do
  begin
    lChild := TBox.Create(FWin);
    lChild.Parent := FPanel;
    TBox(lChild).Radius := 8;
    TBox(lChild).Caption := Format('child %d', [i + 1]);
    case i of
      0: TBox(lChild).Color := wgARGB(255, 70, 130, 220);
      1: TBox(lChild).Color := wgARGB(255, 220, 120, 70);
      2: TBox(lChild).Color := wgARGB(230, 120, 200, 140);
    end;
    // The third one deliberately overhangs the panel, to show clipping.
    lChild.SetBounds(16 + i * 140, 60 + i * 55, 130, 46);
  end;

  // The only thing that changes each frame; it invalidates just itself.
  FMover := TBox.Create(FWin);
  FMover.Parent := lBg;
  FMover.Color := wgARGB(255, 240, 90, 140);
  FMover.Radius := 10;
  FMover.Caption := 'moving';
  FMover.SetBounds(24, 300, 120, 60);

  FStatus := TBox.Create(FWin);
  FStatus.Parent := lBg;
  FStatus.Color := wgARGB(255, 28, 34, 48);
  FStatus.Radius := 8;
  FStatus.SetBounds(24, 380, 660, 52);
end;

procedure TApp.DoLayout(Sender: TObject);
var
  lBg: TwgWidget;
begin
  // Root is sized by TwgWindow; keep the backdrop and the status bar with it.
  if FWin.Root.ChildCount = 0 then
    Exit;
  lBg := FWin.Root.Children[0];
  lBg.SetBounds(0, 0, FWin.ClientWidth, FWin.ClientHeight);
  FStatus.SetBounds(24, FWin.ClientHeight - 80,
    Max(80, FWin.ClientWidth - 48), 52);
end;

procedure TApp.Animate;
var
  lX: Integer;
  lSecs: Double;
begin
  lX := FMover.Left + FDirX;
  if (lX < 24) or (lX + FMover.Width > FWin.ClientWidth - 24) then
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
      '%d frames · %.1f fps · software canvas · partial repaint',
      [FFrames, FFrames / lSecs]);
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
