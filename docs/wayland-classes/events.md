# Event reference

Every `Tfpgw*` callback type. All are `of object`. For the input events the
`Sender` is the focused window's `Owner` (the `AOwner` you passed to
`TfpgwWindow.Create`); pointer coordinates are surface-local pixels.

← back to [index](index.md)

## Pointer

```pascal
TfpgwMouseEnterEvent  = procedure(Sender: TObject; AX, AY: Integer) of object;
TfpgwMouseLeaveEvent  = procedure(Sender: TObject) of object;
TfpgwMouseMotionEvent = procedure(Sender: TObject; ATime: LongWord; AX, AY: Integer) of object;
TfpgwMouseAxisEvent   = procedure(Sender: TObject; ATime: LongWord; AAxis: TWlPointer.TAxis; AValue: LongInt) of object;
TfpgwMouseButtonEvent = procedure(Sender: TObject; ATime: LongWord; AButton: LongWord; AState: TWlPointer.TButtonState) of object;
```

`AButton` is a Linux input code — compare against `BTN_LEFT`, `BTN_RIGHT`,
`BTN_MIDDLE` (and `BTN_SIDE`/`BTN_EXTRA`/`BTN_FORWARD`/`BTN_BACK`/`BTN_TASK`),
declared in `fpg_wayland_classes`. `AState` is `buPressed` / `buReleased`.

## Keyboard

```pascal
TfpgwKeyboardKeymap     = procedure(Sender: TObject; AFormat: TWlKeyboard.TKeymapFormat; AFileDesc: LongInt; ASize: LongInt) of object;
TfpgwKeyboardEnter      = procedure(Sender: TObject; AKeys: TBytes) of object;
TfpgwKeyboardLeave      = procedure(Sender: TObject) of object;
TfpgwKeyboardKey        = procedure(Sender: TObject; ATime: LongWord; AKey: LongWord; AState: TWlKeyboard.TKeyState) of object;
TfpgwKeyboardModifiers  = procedure(Sender: TObject; AModsDepressed, AModsLatched, AModsLocked, AGroup: LongWord) of object;
TfpgwKeyboardRepeatInfo = procedure(Sender: TObject; ARate, ADelay: LongInt) of object;
```

`OnKeyboardKeymap` hands you a raw fd (`AFileDesc`) and `ASize` to `mmap` an XKB
keymap; **you own closing it**. `AKey` is a raw keycode (add 8 for an XKB
keycode).

## Drag-and-drop

```pascal
TfpgwDndEnterEvent  = procedure(Sender: TObject; AWindow: TfpgwWindow; AX, AY: Integer; AOffer: TfpgwDataOffer) of object;
TfpgwDndMotionEvent = procedure(Sender: TObject; ATime: LongWord; AX, AY: Integer) of object;
TfpgwDndLeaveEvent  = procedure(Sender: TObject) of object;
TfpgwDndDropEvent   = procedure(Sender: TObject; AOffer: TfpgwDataOffer) of object;
```

`AOffer` is a [`TfpgwDataOffer`](TfpgwDataOffer.md) — `Accept` it, then `Receive`
on drop and `Finish`.

## Window (per `TfpgwWindow`)

```pascal
property OnPaint:     TNotifyEvent;
property OnConfigure: TfpgwShellConfigureEvent;  // procedure(Sender; AEdges: LongWord; AWidth, AHeight: LongInt) of object
property OnClose:     TNotifyEvent;
```
