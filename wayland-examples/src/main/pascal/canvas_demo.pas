// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ canvas_demo — draws a scene with TwgRasterCanvas into an shm window buffer.

  Demonstrates the minimal software canvas (wlg.canvas.raster) over the wayland-
  classes shm buffer: a TfpgwBuffer exposes Data/Width/Height/Stride, which is
  all TwgRasterCanvas needs. Open against a Wayland compositor; the window shows
  rectangles, filled shapes, lines, circles and an ellipse. Close to quit. }
program canvas_demo;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, BaseUnix,{$ENDIF}
  SysUtils, Types, fpg_wayland_classes, wayland, wlg.canvas.raster;

type
  TDemo = class
    Display: TfpgwDisplay;
    Window: TfpgwWindow;
    Quit: Boolean;
    Painted: Boolean;
    procedure DoPaint(Sender: TObject);
    procedure DoClose(Sender: TObject);
    procedure Run;
  end;

procedure TDemo.DoPaint(Sender: TObject);
var
  lBuf: TfpgwBuffer;
  c: TwgRasterCanvas;
  i: Integer;
  lStar: array[0..4] of TPoint;
begin
  lBuf := Window.NextBuffer;
  if lBuf = nil then
    Exit;
  c := TwgRasterCanvas.Create(lBuf.Data, lBuf.Width, lBuf.Height, lBuf.Stride);
  try
    c.Clear(wgRGB(24, 24, 32));                          { dark background }

    c.FillRoundRect(20, 20, 120, 80, 16, 16, wgRGB(60, 120, 200)); { rounded rect }
    c.RoundRect(20, 20, 120, 80, 16, 16, wgRGB(255, 255, 255));    { white outline }

    c.FillCircle(240, 70, 45, wgRGB(220, 80, 80));       { filled circle }
    c.Circle(240, 70, 45, wgRGB(255, 255, 255));

    c.FillEllipse(110, 200, 80, 40, wgRGB(90, 190, 110));{ filled ellipse }
    c.Ellipse(110, 200, 80, 40, wgRGB(255, 255, 255));

    { a little fan of lines }
    for i := 0 to 8 do
      c.Line(220, 160, 220 + i * 12, 260, wgRGB(230, 200, 90));

    { a five-pointed star drawn as a closed polygon }
    lStar[0] := Point(300, 150);
    lStar[1] := Point(318, 205);
    lStar[2] := Point(263, 171);
    lStar[3] := Point(337, 171);
    lStar[4] := Point(282, 205);
    c.Polygon(lStar, wgRGB(230, 220, 120));

    c.Line(0, 0, c.Width - 1, c.Height - 1, wgRGB(120, 120, 140)); { diagonal }
  finally
    c.Free;
  end;
  lBuf.SetPaintRect(0, 0, lBuf.Width, lBuf.Height);
  Window.Paint(lBuf);
end;

procedure TDemo.DoClose(Sender: TObject);
begin
  Quit := True;
end;

procedure TDemo.Run;
begin
  {$IFDEF UNIX}
  FpSignal(SIGPIPE, SignalHandler(SIG_IGN));
  {$ENDIF}
  Display := TfpgwDisplay.Create(Self, '');
  if not Display.Connected then
  begin
    WriteLn('could not connect to a Wayland compositor (is WAYLAND_DISPLAY set?)');
    Halt(1);
  end;
  Display.AfterCreate;

  Window := TfpgwWindow.Create(Self, Display, nil, 0, 0, 360, 280, nil);
  Window.OnPaint := @DoPaint;
  Window.OnClose := @DoClose;
  Window.SurfaceShell.SetTitle('wlg.canvas.raster demo');
  Window.SurfaceShell.SetServerSideDecorations;

  WriteLn('canvas demo open — close the window to quit');
  Flush(Output);

  while not Quit do
  begin
    Display.WaitEvent(50);
    if Window.Configured and not Painted then
    begin
      Painted := True;
      Window.Redraw;
    end;
  end;

  Window.Free;
  Display.Free;
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
