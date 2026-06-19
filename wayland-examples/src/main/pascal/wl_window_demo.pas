// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wl_window_demo — minimal windowed client built on the wayland-classes
  abstraction (TfpgwDisplay / TfpgwWindow), on top of the pure-Pascal wayl
  binding. Opens a toplevel window, fills it with a solid colour, and runs the
  event loop until the window is closed.

  This is the canonical "how to use wayland-classes standalone" example: it does
  by hand what fpGUI's backend does internally — connect, create a window, wire
  OnPaint/OnClose, drive the event loop with WaitEvent, and paint on the first
  configure. Requires a running Wayland compositor (WAYLAND_DISPLAY set). }
program wl_window_demo;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  SysUtils, fpg_wayland_classes, wayland;

type
  TDemo = class
  private
    FDisplay: TfpgwDisplay;
    FWindow: TfpgwWindow;
    FQuit: Boolean;
    FPainted: Boolean;
    procedure DoPaint(Sender: TObject);
    procedure DoClose(Sender: TObject);
    procedure DoError(Sender: TWlDisplay; aObjectId: Cardinal; aCode: DWord; aMessage: String);
  public
    procedure Run;
  end;

procedure TDemo.DoPaint(Sender: TObject);
var
  lBuf: TfpgwBuffer;
  lPx: PDWord;
  i, lCount: Integer;
begin
  lBuf := FWindow.NextBuffer;       { a free, correctly-sized shm buffer (or nil) }
  if lBuf = nil then
    Exit;
  { Fill it with an opaque steel-blue (wl_shm ARGB8888 = 0xAARRGGBB). }
  lPx := PDWord(lBuf.Data);
  lCount := lBuf.Width * lBuf.Height;
  for i := 0 to lCount - 1 do
    lPx[i] := $FF3060A0;
  lBuf.SetPaintRect(0, 0, lBuf.Width, lBuf.Height);
  FWindow.Paint(lBuf);              { attach + damage + commit + frame callback }
end;

procedure TDemo.DoClose(Sender: TObject);
begin
  FQuit := True;
end;

procedure TDemo.DoError(Sender: TWlDisplay; aObjectId: Cardinal; aCode: DWord; aMessage: String);
begin
  WriteLn(Format('PROTOCOL ERROR: object %d code %d: %s', [aObjectId, aCode, aMessage]));
  Flush(Output);
  FQuit := True;
end;

procedure TDemo.Run;
begin
  {$IFDEF UNIX}
  { A Wayland client must not die from SIGPIPE if the compositor closes the
    socket (e.g. on a protocol error) — let writes fail with EPIPE instead. }
  FpSignal(SIGPIPE, SignalHandler(SIG_IGN));
  {$ENDIF}

  FDisplay := TfpgwDisplay.Create(Self, '');
  if not FDisplay.Connected then
  begin
    WriteLn('could not connect to a Wayland compositor (is WAYLAND_DISPLAY set?)');
    Halt(1);
  end;
  FDisplay.Display.OnError := @DoError;

  { Enumerate + bind the globals (compositor, shm, seat, xdg_wm_base, ...) BEFORE
    creating any window: TfpgwWindow.Create needs the bound shell (FSurfaceClass)
    to build its surface. }
  FDisplay.AfterCreate;

  FWindow := TfpgwWindow.Create(Self, FDisplay, nil, 0, 0, 480, 320, nil);
  FWindow.OnPaint := @DoPaint;
  FWindow.OnClose := @DoClose;
  FWindow.SurfaceShell.SetTitle('wayland-classes demo');
  { Prefer compositor-drawn decorations so there's a titlebar/close button to
    exercise OnClose; harmless no-op if the compositor lacks xdg-decoration. }
  FWindow.SurfaceShell.SetServerSideDecorations;

  WriteLn('window open — close it to quit');
  Flush(Output);

  while not FQuit do
  begin
    FDisplay.WaitEvent(50);
    { Paint once the surface has its first acked configure (xdg-shell forbids
      attaching a buffer before that). }
    if FWindow.Configured and not FPainted then
    begin
      FPainted := True;
      FWindow.Redraw;
    end;
  end;

  FWindow.Free;
  FDisplay.Free;
end;

var
  lDemo: TDemo;
begin
  lDemo := TDemo.Create;
  try
    lDemo.Run;
  finally
    lDemo.Free;
  end;
end.
