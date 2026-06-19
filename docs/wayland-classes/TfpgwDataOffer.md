# TfpgwDataOffer

An **incoming** offer — a clipboard selection, or a drag hovering over you. It
collects the advertised mime types and reads the payload over a pipe (the
abstraction wraps the fd as a stream, so you just call `Receive`/`ReceiveText`).

← back to [index](index.md)

## Where it comes from

- Clipboard: `Display.ClipboardOffer` (nil if there is no selection).
- Drag: the `AOffer` argument of `OnDndEnter` / `OnDndDrop` (see the
  [event reference](events.md)).

## Reading the payload

```pascal
function HasMimeType(const AMimeType: String): Boolean;
function PreferredTextMimeType: String;             // 'text/plain;charset=utf-8' preferred, or ''
function Receive(const AMimeType: String): TBytes;  // raw bytes; pumps the loop
function ReceiveText: String;
property MimeTypes: TStringList;
```

`Receive`/`ReceiveText` block while pumping the event loop, so a same-process
data source can answer. Example:

```pascal
if Assigned(Display.ClipboardOffer)
   and Display.ClipboardOffer.HasMimeType('text/plain;charset=utf-8') then
  WriteLn(Display.ClipboardText);   // shortcut for ClipboardOffer.ReceiveText
```

## Drag-and-drop acknowledgement

```pascal
procedure Accept(ASerial: DWord; const AMimeType: String);
procedure SetActions(ADndActions, APreferredAction: TWlDataDeviceManager.TDndAction);
procedure Finish;
property  SourceActions: TWlDataDeviceManager.TDndAction;
property  Action: TWlDataDeviceManager.TDndAction;
```

During a drag, `Accept` the mime type you can take (using the drag-enter serial),
optionally negotiate `SetActions`, read with `Receive` on drop, then `Finish`.

See [`TfpgwDataSource`](TfpgwDataSource.md) for the outgoing side and the
`clipboard_test` example.
