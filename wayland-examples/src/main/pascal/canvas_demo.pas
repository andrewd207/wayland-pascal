{ canvas_demo — draws a scene with TWaylandCanvas into an shm window buffer.

  Demonstrates the minimal software canvas (wayland_canvas) over the wayland-
  classes shm buffer: a TfpgwBuffer exposes Data/Width/Height/Stride, which is
  all TWaylandCanvas needs. Open against a Wayland compositor; the window shows
  rectangles, filled shapes, lines, circles and an ellipse. Close to quit. }
program canvas_demo;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, BaseUnix,{$ENDIF}
  SysUtils, fpg_wayland_classes, wayland, wayland_canvas;

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
  c: TWaylandCanvas;
  i: Integer;
begin
  lBuf := Window.NextBuffer;
  if lBuf = nil then
    Exit;
  c := TWaylandCanvas.Create(lBuf.Data, lBuf.Width, lBuf.Height, lBuf.Stride);
  try
    c.Clear(RGB(24, 24, 32));                          { dark background }

    c.FillRect(20, 20, 120, 80, RGB(60, 120, 200));    { filled rectangle }
    c.Rectangle(20, 20, 120, 80, RGB(255, 255, 255));  { white outline      }

    c.FillCircle(240, 70, 45, RGB(220, 80, 80));       { filled circle }
    c.Circle(240, 70, 45, RGB(255, 255, 255));

    c.FillEllipse(110, 200, 80, 40, RGB(90, 190, 110));{ filled ellipse }
    c.Ellipse(110, 200, 80, 40, RGB(255, 255, 255));

    { a little fan of lines }
    for i := 0 to 8 do
      c.Line(220, 160, 220 + i * 12, 260, RGB(230, 200, 90));

    c.Line(0, 0, c.Width - 1, c.Height - 1, RGB(120, 120, 140)); { diagonal }
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
  Window.SurfaceShell.SetTitle('wayland_canvas demo');
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
