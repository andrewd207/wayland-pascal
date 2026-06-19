# TfpgwWindow

A surface plus a shell role and two CPU-addressable buffers. You paint into a
buffer and drive the window's `OnPaint`/`OnConfigure`/`OnClose`.

← back to [index](index.md)

## Construction

```pascal
constructor Create(AOwner: TObject; ADisplay: TfpgwDisplay; AParent: TfpgwWindow;
  ALeft, ATop, AWidth, AHeight: Integer; APopupFor: TfpgwWindow;
  APopupGrab: Boolean = False; AGrabSerial: DWord = 0);
```

- **Toplevel:** `AParent = nil`, `APopupFor = nil` (the constructor calls
  `SetToplevel` for you).
- **Popup:** pass `APopupFor` (optionally `APopupGrab` + `AGrabSerial`).
- **Sub-surface:** pass `AParent`.
- `AOwner` becomes the `Sender` of this window's input events.

The constructor does **not** roundtrip — paint on the first configure (see below).

## Painting

```pascal
function  NextBuffer: TfpgwBuffer;   // free buffer sized to the window; nil if both busy
procedure Paint(Buffer: TfpgwBuffer); // attach + damage (PaintArea) + commit
procedure Redraw;                     // request a frame (re-invokes OnPaint)
property  Configured: Boolean;        // true once the initial configure is acked
```

Typical loop body:

```pascal
Display.WaitEvent(50);
if Window.Configured and not Painted then
begin
  Painted := True;
  Window.Redraw;     // first paint
end;
```

Inside `OnPaint`: get `NextBuffer`, write pixels into `Buffer.Data` (respecting
`Buffer.Stride`), call `Buffer.SetPaintRect(...)`, then `Window.Paint(Buffer)`.
See [`TfpgwBuffer`](TfpgwBuffer.md).

## Events

```pascal
property OnPaint: TNotifyEvent;
property OnConfigure: TfpgwShellConfigureEvent;  // (Sender; AEdges: LongWord; AWidth, AHeight: LongInt)
property OnClose: TNotifyEvent;
```

## Other members

```pascal
property SurfaceShell: TfpgwShellSurfaceCommon;  // role API: title, move, decorations…
property Display: TfpgwDisplay;
property ClientWidth, ClientHeight: Integer;
function GetWidth: Integer;
function GetHeight: Integer;
property ButtonPressSerial: DWord;   // serial of the last pointer PRESS over this window
property ContentOffsetX, ContentOffsetY: Integer;  // content origin vs surface (client-side decorations)
```

Use `SurfaceShell` for everything role-related — see
[`TfpgwShellSurfaceCommon`](TfpgwShellSurfaceCommon.md). For interactive
move/resize pass `ButtonPressSerial`:

```pascal
Window.SurfaceShell.Move(Window.ButtonPressSerial);
```
