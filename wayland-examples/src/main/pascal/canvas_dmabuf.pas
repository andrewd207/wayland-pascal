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
  cthreads, BaseUnix, ctypes, SysUtils,
  Wayland_Core, wayland, linux_dmabuf_v1_protocol, xdg_shell_protocol,
  wayland_canvas;

const
  WIN_W = 360;
  WIN_H = 280;

  MFD_CLOEXEC       = $0001;
  MFD_ALLOW_SEALING = $0002;
  F_ADD_SEALS       = 1033;
  F_SEAL_SHRINK     = $0002;

  // ioctl request numbers (generic _IOC encoding: dir<<30 | size<<16 | type<<8 | nr)
  UDMABUF_CREATE     = (1 shl 30) or (24 shl 16) or (Ord('u') shl 8) or $42; // _IOW('u',0x42, sizeof(udmabuf_create))
  DMA_BUF_IOCTL_SYNC = (1 shl 30) or (8  shl 16) or (Ord('b') shl 8) or 0;   // _IOW('b',0, sizeof(__u64))
  DMA_BUF_SYNC_WRITE = 2;
  DMA_BUF_SYNC_RW    = 3;
  DMA_BUF_SYNC_START = 0;
  DMA_BUF_SYNC_END   = 4;

  DRM_FORMAT_ARGB8888 = $34325241; // 'AR24'

type
  Tudmabuf_create = record
    memfd: cuint32;
    flags: cuint32;
    offset: cuint64;
    size: cuint64;
  end;
  Tdma_buf_sync = record
    flags: cuint64;
  end;

function memfd_create(name: PChar; flags: cuint): cint; cdecl; external 'c' name 'memfd_create';

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

    MemFd: cint;
    DmabufFd: cint;
    Pixels: PByte;
    Size: csize_t;
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
var
  lCreate: Tudmabuf_create;
  lUdmabuf: cint;
  p: Pointer;
begin
  Result := False;
  // GPU dma-buf import (e.g. mutter's EGL path) generally needs the linear stride
  // 256-byte aligned; pad rows up to that. The canvas is told the real stride, so
  // pixels still land correctly.
  Stride := ((WIN_W * 4 + 255) div 256) * 256;
  // udmabuf requires the memfd size to be a multiple of the page size; round up
  // (the canvas only uses the first Stride*WIN_H bytes).
  Size := ((csize_t(Stride) * WIN_H + 4095) div 4096) * 4096;

  MemFd := memfd_create('wayl-canvas', MFD_CLOEXEC or MFD_ALLOW_SEALING);
  if MemFd < 0 then
  begin
    WriteLn('memfd_create failed: ', fpgeterrno);
    Exit;
  end;
  if fpftruncate(MemFd, Size) <> 0 then
  begin
    WriteLn('ftruncate failed: ', fpgeterrno);
    Exit;
  end;
  // udmabuf requires the memfd be sealed against shrinking.
  if FpFcntl(MemFd, F_ADD_SEALS, F_SEAL_SHRINK) <> 0 then
  begin
    WriteLn('F_ADD_SEALS failed: ', fpgeterrno);
    Exit;
  end;

  lUdmabuf := FpOpen('/dev/udmabuf', O_RDWR);
  if lUdmabuf < 0 then
  begin
    WriteLn('open /dev/udmabuf failed: ', fpgeterrno, ' (need the kvm group / udmabuf module)');
    Exit;
  end;
  FillChar(lCreate, SizeOf(lCreate), 0);
  lCreate.memfd := MemFd;
  lCreate.size := Size;
  DmabufFd := FpIOCtl(lUdmabuf, UDMABUF_CREATE, @lCreate);
  FpClose(lUdmabuf);
  if DmabufFd < 0 then
  begin
    WriteLn('UDMABUF_CREATE failed: ', fpgeterrno);
    Exit;
  end;

  // CPU access via the memfd mapping (same pages as the dma-buf).
  p := Fpmmap(nil, Size, PROT_READ or PROT_WRITE, MAP_SHARED, MemFd, 0);
  if p = MAP_FAILED then
  begin
    WriteLn('mmap failed: ', fpgeterrno);
    Exit;
  end;
  Pixels := PByte(p);
  Result := True;
end;

procedure TApp.DrawScene;
var
  c: TWaylandCanvas;
  lSync: Tdma_buf_sync;
  i: Integer;
begin
  // Bracket CPU writes with dma-buf sync so the compositor sees coherent pixels.
  lSync.flags := DMA_BUF_SYNC_START or DMA_BUF_SYNC_RW;
  FpIOCtl(DmabufFd, DMA_BUF_IOCTL_SYNC, @lSync);
  try
    c := TWaylandCanvas.Create(Pixels, WIN_W, WIN_H, Stride);
    try
      c.Clear(RGB(32, 28, 24));
      c.FillRect(20, 20, 120, 80, RGB(200, 120, 60));
      c.Rectangle(20, 20, 120, 80, RGB(255, 255, 255));
      c.FillCircle(250, 70, 45, RGB(80, 160, 220));
      c.Circle(250, 70, 45, RGB(255, 255, 255));
      c.FillEllipse(120, 200, 80, 40, RGB(150, 110, 200));
      c.Ellipse(120, 200, 80, 40, RGB(255, 255, 255));
      for i := 0 to 8 do
        c.Line(230, 150, 230 + i * 12, 250, RGB(230, 220, 120));
    finally
      c.Free;
    end;
  finally
    lSync.flags := DMA_BUF_SYNC_END or DMA_BUF_SYNC_RW;
    FpIOCtl(DmabufFd, DMA_BUF_IOCTL_SYNC, @lSync);
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
  lParams.Add(DmabufFd, 0, 0, Stride, 0, 0);
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
