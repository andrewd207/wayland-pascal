# TfpgwShellSurfaceCommon

The window's shell role — title, window state, interactive move/resize,
decorations, popups. `wl_shell` and `xdg-shell` backends are selected
automatically (xdg preferred); you only ever use this common API, reached via
`Window.SurfaceShell`.

← back to [index](index.md)

## Identity and window state

```pascal
procedure SetTitle(AValue: String);
procedure SetMaximized(AValue: Boolean);
function  IsMaximized: Boolean;
procedure SetFullscreen(AValue: Boolean);
procedure SetMinimized;
function  IsActive: Boolean;   // compositor reports the surface as focused/activated
```

## Interactive operations (need a recent serial)

```pascal
procedure Move(ASerial: LongWord);
procedure Resize(ASerial: DWord; AEdges: DWord);
procedure ShowWindowMenu(ASerial: DWord; AX, AY: Integer);
```

Pass `Window.ButtonPressSerial` (the serial of the last pointer press). Example —
left-drag moves the window:

```pascal
procedure DoButton(Sender: TObject; ATime, AButton: LongWord; AState: TWlPointer.TButtonState);
begin
  if (AState = TWlPointer.TButtonState.buPressed) and (AButton = BTN_LEFT) then
    Window.SurfaceShell.Move(Window.ButtonPressSerial);
end;
```

## Roles (only one is valid per surface)

```pascal
procedure SetToplevel;
procedure SetPopup(AParent: TfpgwWindow; AX, AY: Integer; AGrab: Boolean = False; AGrabSerial: DWord = 0);
procedure SetSubSurface(AParent: TfpgwShellSurfaceCommon);
```

`TfpgwWindow.Create` already calls the right one based on its `APopupFor`/`AParent`
arguments, so you rarely call these directly.

## Decorations

```pascal
function  SetServerSideDecorations: Boolean;  // False if the compositor has no xdg-decoration support
procedure SetClientSideDecorations;           // tell it you'll draw your own
```

If `SetServerSideDecorations` returns False, draw your own frame.

## Geometry

```pascal
procedure SetWindowGeometry(AX, AY, AWidth, AHeight: Integer);
procedure SetMinSize(AWidth, AHeight: Integer);
procedure SetMaxSize(AWidth, AHeight: Integer);
procedure SetOpaqueRegion(ARegion: TRect);
procedure Commit;
```

`HasWindowMenu` / `DecorationMode` (on the xdg subclass) report the negotiated
capabilities.
