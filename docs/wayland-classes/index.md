# wayland-classes — the `Tfpgw*` OOP layer

> **Note:** `wayland-classes` (unit `fpg_wayland_classes`) is a convenience
> wrapper around the Wayland protocols — the raw pure-Pascal binding
> (`wayland-rt` + the protocol tiers) — with some niceties that make them
> friendlier to use. It handles the registry/handshake/buffer plumbing for you
> and adds a few conveniences on top (double-buffered windows, a cursor loader, a
> software canvas, clipboard/DnD helpers), so a toolkit — or a standalone program
> — can open a window, draw, and handle input without touching the wire protocol
> directly.

It is RTL-only and named after fpGUI's Wayland backend (the `fpgw` prefix), but
has no dependency on fpGUI and can be used on its own. The canonical standalone
example is [`wl_window_demo`](../../wayland-examples/src/main/pascal/wl_window_demo.pas);
see the other [examples](../../wayland-examples/README.md) for canvas drawing,
cursors, and clipboard.

## Classes

| Class | Role |
|---|---|
| [`TfpgwDisplay`](TfpgwDisplay.md) | The connection + event loop. Binds globals, owns the seat (pointer/keyboard), cursor, and clipboard/drag-and-drop; all input events surface here. |
| [`TfpgwWindow`](TfpgwWindow.md) | A surface with a shell role and double-buffering. You paint into its buffers and drive `OnPaint`/`OnConfigure`/`OnClose`. |
| [`TfpgwShellSurfaceCommon`](TfpgwShellSurfaceCommon.md) | The window's shell role (title, min/max, move/resize, decorations, popups). `wl_shell`/`xdg-shell` chosen automatically; used via `Window.SurfaceShell`. |
| [`TfpgwBuffer`](TfpgwBuffer.md) | One of a window's CPU-addressable pixel buffers (`Data`/`Width`/`Height`/`Stride`), backed by wl_shm or a dma-buf transparently. |
| [`TfpgwCursor`](TfpgwCursor.md) | The pointer cursor (named XCursor lookups, animation). Usually driven via `TfpgwDisplay.SetCursor`. |
| [`TfpgwDataOffer`](TfpgwDataOffer.md) | An incoming clipboard selection or drag payload — read with `ReceiveText`/`Receive`. |
| [`TfpgwDataSource`](TfpgwDataSource.md) | An outgoing clipboard/drag payload — fill with `SetData`. |

See also: the [event reference](events.md) for every `Tfpgw*` callback signature.

Drawing into a buffer is done with [`TWaylandCanvas`](../wayland-canvas.md) (unit
`wayland_canvas`, in `wayland-rt`) — a minimal software canvas over raw ARGB8888
memory, independent of `wayland-classes`.

## Quick start

```pascal
program minimal;
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads, BaseUnix,{$ENDIF}
  SysUtils, fpg_wayland_classes, wayland;

type
  TApp = class
    Display: TfpgwDisplay;
    Window: TfpgwWindow;
    Quit, Painted: Boolean;
    procedure DoPaint(Sender: TObject);
    procedure DoClose(Sender: TObject);
    procedure Run;
  end;

procedure TApp.DoPaint(Sender: TObject);
var
  lBuf: TfpgwBuffer;
  px: PDWord;
  i: Integer;
begin
  lBuf := Window.NextBuffer;          { nil if both buffers are still busy }
  if lBuf = nil then Exit;
  px := PDWord(lBuf.Data);
  for i := 0 to lBuf.Width * lBuf.Height - 1 do
    px[i] := $FF3060A0;               { opaque ARGB }
  lBuf.SetPaintRect(0, 0, lBuf.Width, lBuf.Height);
  Window.Paint(lBuf);
end;

procedure TApp.DoClose(Sender: TObject);
begin
  Quit := True;
end;

procedure TApp.Run;
begin
  {$IFDEF UNIX}FpSignal(SIGPIPE, SignalHandler(SIG_IGN));{$ENDIF}
  Display := TfpgwDisplay.Create(Self, '');
  if not Display.Connected then
  begin
    WriteLn('no Wayland compositor (is WAYLAND_DISPLAY set?)');
    Halt(1);
  end;
  Display.AfterCreate;                { call after wiring display-level events }

  Window := TfpgwWindow.Create(Self, Display, nil, 0, 0, 400, 300, nil);
  Window.OnPaint := @DoPaint;
  Window.OnClose := @DoClose;
  Window.SurfaceShell.SetTitle('minimal');
  Window.SurfaceShell.SetServerSideDecorations;

  while not Quit do
  begin
    Display.WaitEvent(50);
    if Window.Configured and not Painted then   { first paint on first configure }
    begin
      Painted := True;
      Window.Redraw;
    end;
  end;

  Window.Free;
  Display.Free;
end;

var
  app: TApp;
begin
  app := TApp.Create;
  try app.Run; finally app.Free; end;
end.
```

Two rules the abstraction relies on:

- **Paint on the first `configure`, not in the constructor.** Creating a window
  does *not* roundtrip (that would consume the initial xdg configure before your
  callbacks are wired). Wait until `Window.Configured` is true, then `Redraw`.
- **Don't attach a buffer before the window is configured** — xdg-shell forbids
  it and the surface won't map. `Window.NextBuffer`/`Paint` already respect this.
