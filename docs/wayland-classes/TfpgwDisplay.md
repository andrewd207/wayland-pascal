# TfpgwDisplay

The connection and the event loop. It binds the registry globals, owns the seat
(pointer + keyboard), the [cursor](TfpgwCursor.md), and the clipboard /
drag-and-drop machinery. All input events surface here.

← back to [index](index.md)

## Lifecycle

```pascal
constructor Create(AOwner: TObject; AName: String = '');
class function TryCreate(AOwner: TObject; AName: String = ''): TfpgwDisplay;
procedure AfterCreate;
destructor Destroy; override;
```

- `Create` connects immediately (the binding finds the compositor socket itself;
  `AName` is currently unused). Check `Connected` afterwards.
- `AfterCreate` — call **once**, after you've assigned the display-level event
  handlers, to finish setup.
- `AOwner` is available as the `Owner` property.

## Event loop

```pascal
procedure WaitEvent(ATimeOut: Integer);   // milliseconds
function  HasEvent(ATimeout: Integer = 0; AWillRead: Boolean = False): Boolean;
procedure Flush;
procedure Roundtrip;
procedure Wakeup;
```

- `WaitEvent` is your main-loop pump: wait up to `ATimeOut` ms for events, then
  drain and dispatch everything pending. It also advances cursor animation.
- `Wakeup` is thread-safe: unblock a `WaitEvent` running in another thread (e.g.
  after a worker posts a redraw request).

## Properties

```pascal
property Connected: Boolean;
property EventSerial: LongWord;        // most recent server serial
property ButtonPressSerial: LongWord;  // serial of the last pointer-button PRESS
property Owner: TObject;
property ActiveMouseWin: TfpgwWindow;
property SupportsServerSideDecorations: Boolean;
```

`ButtonPressSerial` is not clobbered by enter/leave/motion, so it stays valid as
the "triggering event" serial for `Move`/`Resize`/popup grabs. (Each window also
caches its own `Window.ButtonPressSerial`.)

## Input events

All are `of object`; the `Sender` is the focused window's `Owner`. Coordinates
are surface-local pixels. See the full signatures in the [event reference](events.md).

```pascal
property OnMouseEnter, OnMouseLeave, OnMouseMotion, OnMouseButton, OnMouseAxis;
property OnKeyboardEnter, OnKeyboardLeave, OnKeyboardKey, OnKeyboardModifiers;
property OnKeyboardKeymap, OnKeyBoardRepeatInfo;
```

## Cursor

```pascal
procedure SetCursorTheme(const AName: String; ASize: Integer);  // '' + <=0 = defaults (24)
procedure SetCursor(ACursors: array of String);                 // first name that resolves
```

Animated cursors animate automatically while the pointer is over your surface.
See [`TfpgwCursor`](TfpgwCursor.md).

## Clipboard

The core clipboard is **focus-gated** (only delivered to / settable by the
keyboard-focused client).

```pascal
procedure SetClipboardText(const AText: String);
procedure SetClipboard(const AMimeType, AData: String);
function  ClipboardText: String;
property  ClipboardOffer: TfpgwDataOffer;   // current incoming selection, or nil
```

See [`TfpgwDataOffer`](TfpgwDataOffer.md) / [`TfpgwDataSource`](TfpgwDataSource.md).

## Drag-and-drop

```pascal
function  CreateDataSource: TfpgwDataSource;
procedure StartDrag(ASource: TfpgwDataSource; AOrigin: TfpgwWindow; AIcon: TWlSurface = nil);
property  OnDndEnter, OnDndMotion, OnDndLeave, OnDndDrop;
```

## User data

A small typed-pointer registry for associating your objects with wl_ objects:
`AddUserData(ALookup, AData)`, `GetUserData(ALookup)`, `RemoveUserData(ALookup)`.
