// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ themed_window — a client-side-decorated (CSD) window that draws its own title
  bar using the desktop theme, with working window buttons and the compositor's
  window menu on right-click.

  It reads the running desktop's appearance with `desktop_theme`
  (CreateDesktopTheme): header-bar colours, accent, light/dark, and which
  buttons the user wants on which side. The title bar + buttons are painted with
  TWaylandCanvas; there is no title *text* (the canvas has no font — a real
  toolkit would draw the title with its own text renderer).

  Interactions:
    left-drag on the title bar    — interactive move (compositor-driven)
    click a button                — minimize / maximize-toggle / close
    right-click anywhere          — the compositor's window menu (xdg-shell)

  Requires a Wayland compositor. Tell it we draw our own decorations via
  SetClientSideDecorations so it doesn't add a second frame. }
program themed_window;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, BaseUnix,{$ENDIF}
  SysUtils, Types, fpg_wayland_classes, wayland, wayland_canvas, desktop_theme;

const
  WIN_W   = 520;
  WIN_H   = 340;
  TITLE_H = 38;    { title-bar height = button size }

type
  TBtnSlot = record
    Rect: TRect;
    Kind: TDesktopWindowButton;
  end;

  TApp = class
    Display: TfpgwDisplay;
    Window: TfpgwWindow;
    Theme: TDesktopTheme;
    Slots: array of TBtnSlot;
    MouseX, MouseY: Integer;
    Hover: Integer;        { index into Slots, or -1 }
    Quit, Painted, Dirty: Boolean;
    procedure Layout;
    function  ButtonAt(AX, AY: Integer): Integer;
    procedure DoPaint(Sender: TObject);
    procedure DoMotion(Sender: TObject; ATime: LongWord; AX, AY: Integer);
    procedure DoEnter(Sender: TObject; AX, AY: Integer);
    procedure DoLeave(Sender: TObject);
    procedure DoButton(Sender: TObject; ATime, AButton: LongWord; AState: TWlPointer.TButtonState);
    procedure DoClose(Sender: TObject);
    procedure Run;
  end;

procedure TApp.DoClose(Sender: TObject);
begin
  Quit := True;
end;

{ $00RRGGBB (theme) -> opaque ARGB8888 (canvas) }
function ThemeColor(ARGB24: LongWord): TCanvasColor; inline;
begin
  Result := $FF000000 or (ARGB24 and $FFFFFF);
end;

function Clamp(V: Integer): Byte; inline;
begin
  if V < 0 then Result := 0 else if V > 255 then Result := 255 else Result := V;
end;

{ lighten (+) / darken (-) an opaque canvas colour by ADelta per channel }
function Shade(AColor: TCanvasColor; ADelta: Integer): TCanvasColor;
begin
  Result := ARGB(255,
    Clamp(((AColor shr 16) and $FF) + ADelta),
    Clamp(((AColor shr 8) and $FF) + ADelta),
    Clamp((AColor and $FF) + ADelta));
end;

{ Compute the button slots from the theme's left/right layout. Right group is
  right-aligned, left group left-aligned; within a group the visual order is
  minimize, maximize, close. }
procedure TApp.Layout;
var
  lLeft, lRight: array of TDesktopWindowButton;

  procedure Collect(ASet: TDesktopWindowButtons; var AArr: array of TDesktopWindowButton; out ACount: Integer);
  var b: TDesktopWindowButton;
  begin
    ACount := 0;
    for b := dwbMinimize to dwbClose do
      if b in ASet then begin AArr[ACount] := b; Inc(ACount); end;
  end;

var
  lTmpL, lTmpR: array[0..2] of TDesktopWindowButton;
  nL, nR, i, x: Integer;
begin
  Collect(Theme.ButtonsLeft, lTmpL, nL);
  Collect(Theme.ButtonsRight, lTmpR, nR);
  SetLength(Slots, nL + nR);

  for i := 0 to nL - 1 do
  begin
    Slots[i].Kind := lTmpL[i];
    Slots[i].Rect := Rect(i * TITLE_H, 0, (i + 1) * TITLE_H, TITLE_H);
  end;
  x := WIN_W - nR * TITLE_H;
  for i := 0 to nR - 1 do
  begin
    Slots[nL + i].Kind := lTmpR[i];
    Slots[nL + i].Rect := Rect(x + i * TITLE_H, 0, x + (i + 1) * TITLE_H, TITLE_H);
  end;
end;

function TApp.ButtonAt(AX, AY: Integer): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to High(Slots) do
    with Slots[i].Rect do
      if (AX >= Left) and (AX < Right) and (AY >= Top) and (AY < Bottom) then
        Exit(i);
end;

procedure TApp.DoPaint(Sender: TObject);
var
  lBuf: TfpgwBuffer;
  c: TWaylandCanvas;
  i, cx, cy: Integer;
  bar, fg, body, hov: TCanvasColor;
begin
  lBuf := Window.NextBuffer;
  if lBuf = nil then Exit;
  bar  := ThemeColor(Theme.HeaderbarBg);
  fg   := ThemeColor(Theme.HeaderbarFg);
  if Theme.IsDark then body := RGB(36, 36, 40) else body := RGB(246, 246, 248);

  c := TWaylandCanvas.Create(lBuf.Data, lBuf.Width, lBuf.Height, lBuf.Stride);
  try
    c.Clear(body);
    c.FillRect(0, 0, WIN_W, TITLE_H, bar);                 { title bar }
    c.HLine(0, TITLE_H - 1, WIN_W, Shade(bar, -24));       { separator }

    { a little themed content: an accent bar + framed area }
    c.FillRect(0, TITLE_H, WIN_W, 4, ThemeColor(Theme.Accent));
    c.Rectangle(24, TITLE_H + 28, WIN_W - 48, WIN_H - TITLE_H - 56, Shade(body, -40));

    for i := 0 to High(Slots) do
    begin
      with Slots[i].Rect do begin cx := (Left + Right) div 2; cy := (Top + Bottom) div 2; end;
      if i = Hover then
      begin
        if Slots[i].Kind = dwbClose then
          hov := RGB(232, 76, 60)                          { close: red hover }
        else
          hov := Shade(bar, 30);
        c.FillCircle(cx, cy, TITLE_H div 2 - 5, hov);
      end;
      case Slots[i].Kind of
        dwbClose:
          begin
            c.Line(cx - 6, cy - 6, cx + 6, cy + 6, fg);
            c.Line(cx - 6, cy + 6, cx + 6, cy - 6, fg);
            c.Line(cx - 6, cy - 5, cx + 6, cy + 7, fg);    { 2px-ish }
            c.Line(cx - 6, cy + 5, cx + 6, cy - 7, fg);
          end;
        dwbMaximize:
          if Window.SurfaceShell.IsMaximized then
          begin
            c.Rectangle(cx - 6, cy - 3, 9, 9, fg);         { overlapping squares }
            c.Rectangle(cx - 3, cy - 6, 9, 9, fg);
          end
          else
            c.Rectangle(cx - 6, cy - 6, 13, 13, fg);
        dwbMinimize:
          begin
            c.HLine(cx - 6, cy + 6, 13, fg);
            c.HLine(cx - 6, cy + 5, 13, fg);
          end;
      end;
    end;
    { rounded, anti-aliased, transparent window corners (top + bottom) }
    c.RoundCorners(0, 0, WIN_W, WIN_H, 12);
  finally
    c.Free;
  end;
  lBuf.SetPaintRect(0, 0, lBuf.Width, lBuf.Height);
  Window.Paint(lBuf);
end;

procedure TApp.DoMotion(Sender: TObject; ATime: LongWord; AX, AY: Integer);
var h: Integer;
begin
  MouseX := AX; MouseY := AY;
  h := ButtonAt(AX, AY);
  if h <> Hover then begin Hover := h; Dirty := True; end;
end;

procedure TApp.DoEnter(Sender: TObject; AX, AY: Integer);
begin
  MouseX := AX; MouseY := AY;
  Display.SetCursor(['left_ptr', 'default']);
end;

procedure TApp.DoLeave(Sender: TObject);
begin
  if Hover <> -1 then begin Hover := -1; Dirty := True; end;
end;

procedure TApp.DoButton(Sender: TObject; ATime, AButton: LongWord; AState: TWlPointer.TButtonState);
var b: Integer;
begin
  if AState <> TWlPointer.TButtonState.buPressed then Exit;

  if AButton = BTN_RIGHT then
  begin
    { the compositor's window menu (minimize/maximize/move/close…) }
    Window.SurfaceShell.ShowWindowMenu(Window.ButtonPressSerial, MouseX, MouseY);
    Exit;
  end;

  if AButton <> BTN_LEFT then Exit;

  b := ButtonAt(MouseX, MouseY);
  if b >= 0 then
    case Slots[b].Kind of
      dwbClose:    Quit := True;
      dwbMinimize: Window.SurfaceShell.SetMinimized;
      dwbMaximize: Window.SurfaceShell.SetMaximized(not Window.SurfaceShell.IsMaximized);
    end
  else if MouseY < TITLE_H then
    { left-drag on the bar (not on a button) -> compositor-driven move }
    Window.SurfaceShell.Move(Window.ButtonPressSerial);
end;

procedure TApp.Run;
begin
  {$IFDEF UNIX}FpSignal(SIGPIPE, SignalHandler(SIG_IGN));{$ENDIF}
  Theme := CreateDesktopTheme;
  WriteLn(Format('theme: %s  (%s)  accent=#%.6x  buttons L=%d R=%d',
    [Theme.ThemeName, BoolToStr(Theme.IsDark, 'dark', 'light'),
     Theme.Accent, Integer(Theme.ButtonsLeft <> []), Integer(Theme.ButtonsRight <> [])]));
  Flush(Output);

  Display := TfpgwDisplay.Create(Self, '');
  if not Display.Connected then
  begin
    WriteLn('no Wayland compositor (is WAYLAND_DISPLAY set?)');
    Halt(1);
  end;
  Display.OnMouseMotion := @DoMotion;
  Display.OnMouseEnter := @DoEnter;
  Display.OnMouseLeave := @DoLeave;
  Display.OnMouseButton := @DoButton;
  Display.AfterCreate;

  Hover := -1;
  Window := TfpgwWindow.Create(Self, Display, nil, 0, 0, WIN_W, WIN_H, nil);
  Window.OnPaint := @DoPaint;
  Window.OnClose := @DoClose;
  Window.SurfaceShell.SetTitle('themed_window');
  Window.SurfaceShell.SetClientSideDecorations;   { we draw our own frame }
  Window.SurfaceShell.SetWindowGeometry(0, 0, WIN_W, WIN_H);
  Layout;

  WriteLn('left-drag the bar to move; click close to quit; right-click for the window menu');
  Flush(Output);

  while not Quit do
  begin
    Display.WaitEvent(50);
    if Window.Configured and not Painted then begin Painted := True; Window.Redraw; end
    else if Dirty then begin Dirty := False; Window.Redraw; end;
  end;

  Window.Free;
  Display.Free;
  Theme.Free;
end;

var
  app: TApp;
begin
  app := TApp.Create;
  try app.Run; finally app.Free; end;
end.
