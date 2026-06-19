{ canvas_dmabuf — draw with TWaylandCanvas into a dma-buf and present it.

  Shows that the software canvas is buffer-source agnostic: instead of wl_shm,
  the pixels live in a CPU-mapped dma-buf, presented zero-extra-copy via
  zwp_linux_dmabuf_v1. The dma-buf is obtained with udmabuf — a sealed memfd
  wrapped as a dma-buf through /dev/udmabuf — so it needs no GPU and no external
  library; the memfd's mmap'd memory IS the canvas's buffer. We present it with
  the LINEAR modifier and DRM_FORMAT_ARGB8888, which every dma-buf-capable
  compositor accepts, and bracket CPU drawing with DMA_BUF_IOCTL_SYNC for cache
  coherency.

  Requires a compositor with zwp_linux_dmabuf_v1 and access to /dev/udmabuf
  (typically the 'kvm' group). Close the window to quit. }
program canvas_dmabuf;

{$mode objfpc}{$H+}
{$PackRecords c}

uses
  cthreads, BaseUnix, ctypes, SysUtils, Types,
  Wayland_Core, wayland, linux_dmabuf_v1_protocol, xdg_shell_protocol,
  wayland_canvas, wayland_dmabuf;

const
  WIN_W = 360;
  WIN_H = 280;

type
  TApp = class
    Display: TWlDisplay;
    Registry: TWlRegistry;
    Compositor: TWlCompositor;
    WM: TXdgWmBase;
    Dmabuf: TWpLinuxDmabufV1;
    Surface: TWlSurface;
    XdgSurface: TXdgSurface;
    Toplevel: TXdgToplevel;
    Buffer: TWlBuffer;

    Buf: TWaylandUdmabuf;   { the CPU-mapped dma-buf (shared helper) }
    Stride: Integer;

    Quit: Boolean;
    Presented: Boolean;

    procedure OnError(Sender: TWlDisplay; aObjectId: Cardinal; aCode: DWord; aMessage: String);
    procedure OnGlobal(Sender: TWlRegistry; aName: DWord; aInterface: String; aVersion: DWord);
    procedure OnPing(Sender: TXdgWmBase; aSerial: DWord);
    procedure OnXdgConfigure(Sender: TXdgSurface; aSerial: DWord);
    procedure OnToplevelConfigure(Sender: TXdgToplevel; aWidth, aHeight: LongInt; aStates: TBytes);
    procedure OnToplevelClose(Sender: TXdgToplevel);

    function AllocUdmabuf: Boolean;
    procedure DrawScene;
    procedure Present;
    procedure Run;
    destructor Destroy; override;
  end;

destructor TApp.Destroy;
begin
  Buf.Free;   { munmaps + closes the memfd/dma-buf fds }
  inherited Destroy;
end;

procedure TApp.OnError(Sender: TWlDisplay; aObjectId: Cardinal; aCode: DWord; aMessage: String);
begin
  WriteLn(Format('PROTOCOL ERROR: object %d code %d: %s', [aObjectId, aCode, aMessage]));
  Flush(Output);
  Quit := True;
end;

procedure TApp.OnGlobal(Sender: TWlRegistry; aName: DWord; aInterface: String; aVersion: DWord);
begin
  if aInterface = 'wl_compositor' then
    Sender.Bind(aName, aInterface, aVersion, TWlCompositor, Compositor)
  else if aInterface = 'xdg_wm_base' then
  begin
    Sender.Bind(aName, aInterface, aVersion, TXdgWmBase, WM);
    WM.OnPing := @OnPing;
  end
  else if aInterface = 'zwp_linux_dmabuf_v1' then
    Sender.Bind(aName, aInterface, aVersion, TWpLinuxDmabufV1, Dmabuf);
end;

procedure TApp.OnPing(Sender: TXdgWmBase; aSerial: DWord);
begin
  Sender.Pong(aSerial);
end;

procedure TApp.OnXdgConfigure(Sender: TXdgSurface; aSerial: DWord);
begin
  Sender.AckConfigure(aSerial);
  if not Presented then
  begin
    Presented := True;
    Present;
  end;
end;

procedure TApp.OnToplevelConfigure(Sender: TXdgToplevel; aWidth, aHeight: LongInt; aStates: TBytes);
begin
  // fixed-size demo: ignore the suggested size
end;

procedure TApp.OnToplevelClose(Sender: TXdgToplevel);
begin
  Quit := True;
end;

function TApp.AllocUdmabuf: Boolean;
begin
  Result := False;
  if not TWaylandUdmabuf.Available then
  begin
    WriteLn('/dev/udmabuf not available (need the kvm group / udmabuf module)');
    Exit;
  end;
  // GPU dma-buf import (e.g. mutter's EGL path) generally needs the linear stride
  // 256-byte aligned; the helper rounds for us. The canvas is told the real
  // stride, so pixels still land correctly.
  Stride := TWaylandUdmabuf.RoundStride(WIN_W * 4);
  Buf := TWaylandUdmabuf.Create;
  Result := Buf.Alloc(csize_t(Stride) * WIN_H);
  if not Result then
    WriteLn('udmabuf alloc failed: ', fpgeterrno);
end;

procedure TApp.DrawScene;
var
  c: TWaylandCanvas;
  i: Integer;
  lZig: array[0..4] of TPoint;
begin
  // Bracket CPU writes with dma-buf sync so the compositor sees coherent pixels.
  Buf.BeginCpuAccess;
  try
    c := TWaylandCanvas.Create(Buf.Data, WIN_W, WIN_H, Stride);
    try
      c.Clear(RGB(32, 28, 24));
      c.FillRoundRect(20, 20, 120, 80, 18, 18, RGB(200, 120, 60));
      c.RoundRect(20, 20, 120, 80, 18, 18, RGB(255, 255, 255));
      c.FillCircle(250, 70, 45, RGB(80, 160, 220));
      c.Circle(250, 70, 45, RGB(255, 255, 255));
      c.FillEllipse(120, 200, 80, 40, RGB(150, 110, 200));
      c.Ellipse(120, 200, 80, 40, RGB(255, 255, 255));
      for i := 0 to 8 do
        c.Line(230, 150, 230 + i * 12, 250, RGB(230, 220, 120));
      for i := 0 to High(lZig) do
        lZig[i] := Point(220 + i * 30, 150 + (i and 1) * 40);
      c.Polyline(lZig, RGB(120, 230, 160));
    finally
      c.Free;
    end;
  finally
    Buf.EndCpuAccess;
  end;
end;

procedure TApp.Present;
var
  lParams: TWpLinuxBufferParamsV1;
  lFlags: TWpLinuxBufferParamsV1.TFlags;
begin
  DrawScene;
  // LINEAR modifier (0) so the compositor reads our row-major pixels directly.
  lParams := Dmabuf.CreateParams;
  lParams.Add(Buf.DmabufFd, 0, 0, Stride, 0, 0);
  lFlags.Value := 0;
  Buffer := lParams.CreateImmed(WIN_W, WIN_H, DRM_FORMAT_ARGB8888, lFlags);
  lParams.Free;

  Surface.Attach(Buffer, 0, 0);
  Surface.DamageBuffer(0, 0, WIN_W, WIN_H);
  Surface.Commit;
  WriteLn('canvas dma-buf presented — close the window to quit');
  Flush(Output);
end;

procedure TApp.Run;
begin
  FpSignal(SIGPIPE, SignalHandler(SIG_IGN));

  if not AllocUdmabuf then
    Halt(1);

  TWlDisplay.TryCreateConnection(Display);
  Display.OnError := @OnError;
  Registry := Display.GetRegistry;
  Registry.OnGlobal := @OnGlobal;
  Display.SyncAndWait;
  Display.SyncAndWait;

  if not Assigned(Compositor) then begin WriteLn('no wl_compositor'); Halt(1); end;
  if not Assigned(WM) then begin WriteLn('no xdg_wm_base'); Halt(1); end;
  if not Assigned(Dmabuf) then begin WriteLn('no zwp_linux_dmabuf_v1'); Halt(1); end;

  Surface := Compositor.CreateSurface;
  XdgSurface := WM.GetXdgSurface(Surface);
  XdgSurface.OnConfigure := @OnXdgConfigure;
  Toplevel := XdgSurface.GetToplevel;
  Toplevel.SetTitle('wayl — canvas dma-buf');
  Toplevel.OnConfigure := @OnToplevelConfigure;
  Toplevel.OnClose := @OnToplevelClose;
  Surface.Commit; // buffer-less commit -> first xdg configure -> Present

  while not Quit do
    Display.WaitMessage(100);
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
