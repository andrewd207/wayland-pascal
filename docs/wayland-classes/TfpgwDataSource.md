# TfpgwDataSource

An **outgoing** payload — for the clipboard or a drag. It holds the data per mime
type and writes it to the requesting fd on demand (the abstraction hands you a
`TWaylandFdStream` internally, so you just provide the bytes up front).

← back to [index](index.md)

## Building one

```pascal
src := Display.CreateDataSource;
src.SetData('text/plain;charset=utf-8', 'hello');  // also offers the type
```

```pascal
constructor Create(ADisplay: TfpgwDisplay);
procedure SetData(const AMimeType, AData: String);          // offer + payload
procedure SetDndActions(AActions: TWlDataDeviceManager.TDndAction);
property  DndFinished: Boolean;
property  DndAction: TWlDataDeviceManager.TDndAction;
property  OnCancelled: TNotifyEvent;     // compositor dropped/superseded this source
```

## Publishing

- **Clipboard:** the common case is `Display.SetClipboardText('…')`, which builds
  a source for you. For non-text or multiple mime types, build a `TfpgwDataSource`
  and use `Display.SetClipboard(...)`.
- **Drag:** `Display.StartDrag(src, AOriginWindow, AIcon)`; set drag actions with
  `SetDndActions` and watch `DndFinished`/`DndAction`.

When another client pastes/drops, the compositor asks the source to write its
payload to a pipe fd; the abstraction does this for you from the data you set.
The source stays alive until cancelled — `OnCancelled` fires when the compositor
supersedes or drops it.

See [`TfpgwDataOffer`](TfpgwDataOffer.md) for the incoming side and the
`clipboard_test` example (note: the **core** clipboard is focus-gated — you must
hold keyboard focus to set or read it).
