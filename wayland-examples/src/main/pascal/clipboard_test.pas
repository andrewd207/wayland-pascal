// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ clipboard_test — exercises the wl_data_device (clipboard) path of the
  wayland-classes abstraction, which is where the out-of-band fd handling lives.

  The Wayland core clipboard is focus-gated: wl_data_device.selection is only
  delivered to (and set_selection only honoured for) the client holding keyboard
  focus. So this opens a real toplevel and waits for keyboard focus before doing
  the clipboard op — a focusless client gets nothing (that is what the
  wlr/ext-data-control protocols, used by wl-clipboard, exist to work around).

    serve <text>   publish <text> as the selection and serve paste requests.
                   When another client pastes, the compositor delivers
                   wl_data_source.send with a write fd (a TWaylandFdStream) and
                   we write <text> into it. Verify with `wl-paste`.

    get            read the current selection and print it as CLIP:<text>. Sends
                   wl_data_offer.receive (handing the compositor a pipe fd) and
                   reads the payload back. Set it first with `wl-copy`.

  Requires a running Wayland compositor that focuses new toplevels. }
program clipboard_test;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, BaseUnix,{$ENDIF}
  SysUtils, fpg_wayland_classes, wayland;

type
  TApp = class
    Display: TfpgwDisplay;
    Window: TfpgwWindow;
    Focused: Boolean;
    Painted: Boolean;
    procedure DoPaint(Sender: TObject);
    procedure DoKeyboardEnter(Sender: TObject; AKeys: TBytes);
    procedure DoError(Sender: TWlDisplay; aObjectId: Cardinal; aCode: DWord; aMessage: String);
  end;

procedure TApp.DoPaint(Sender: TObject);
var
  lBuf: TfpgwBuffer;
  lPx: PDWord;
  i: Integer;
begin
  lBuf := Window.NextBuffer;
  if lBuf = nil then Exit;
  lPx := PDWord(lBuf.Data);
  for i := 0 to lBuf.Width * lBuf.Height - 1 do
    lPx[i] := $FF206040;
  lBuf.SetPaintRect(0, 0, lBuf.Width, lBuf.Height);
  Window.Paint(lBuf);
end;

procedure TApp.DoKeyboardEnter(Sender: TObject; AKeys: TBytes);
begin
  Focused := True; { keyboard focus -> selection events arrive, serial is usable }
end;

procedure TApp.DoError(Sender: TWlDisplay; aObjectId: Cardinal; aCode: DWord; aMessage: String);
begin
  WriteLn(Format('PROTOCOL ERROR: object %d code %d: %s', [aObjectId, aCode, aMessage]));
  Flush(Output);
  Halt(2);
end;

{ Pump the event loop until we hold keyboard focus (EventSerial becomes non-zero)
  or a timeout. The core clipboard is focus-gated, so this must succeed before
  either reading or setting the selection. Paints on first configure so the
  window actually maps (and can therefore be focused). }
function WaitForFocus(AApp: TApp; ATimeoutMs: Integer): Boolean;
var
  lWaited: Integer;
begin
  lWaited := 0;
  while (AApp.Display.EventSerial = 0) and (lWaited < ATimeoutMs) do
  begin
    AApp.Display.WaitEvent(50);
    if AApp.Window.Configured and not AApp.Painted then
    begin
      AApp.Painted := True;
      AApp.Window.Redraw;
    end;
    Inc(lWaited, 50);
  end;
  { Give the selection event a moment to follow the focus enter. }
  AApp.Display.WaitEvent(100);
  Result := AApp.Display.EventSerial <> 0;
end;

var
  lApp: TApp;
  lMode, lText: String;
  i: Integer;
begin
  {$IFDEF UNIX}
  FpSignal(SIGPIPE, SignalHandler(SIG_IGN));
  {$ENDIF}
  if ParamCount < 1 then
  begin
    WriteLn('usage: clipboard_test serve <text> | get');
    Halt(1);
  end;
  lMode := ParamStr(1);

  lApp := TApp.Create;
  lApp.Display := TfpgwDisplay.Create(nil, '');
  if not lApp.Display.Connected then
  begin
    WriteLn('could not connect to a Wayland compositor (is WAYLAND_DISPLAY set?)');
    Halt(1);
  end;
  lApp.Display.Display.OnError := @lApp.DoError;
  lApp.Display.OnKeyboardEnter := @lApp.DoKeyboardEnter;
  lApp.Display.AfterCreate;

  lApp.Window := TfpgwWindow.Create(lApp, lApp.Display, nil, 0, 0, 320, 200, nil);
  lApp.Window.OnPaint := @lApp.DoPaint;
  lApp.Window.SurfaceShell.SetTitle('clipboard_test');

  if not WaitForFocus(lApp, 5000) then
    WriteLn('WARNING: never got keyboard focus; the core clipboard needs it');

  if lMode = 'serve' then
  begin
    lText := ParamStr(2);
    lApp.Display.SetClipboardText(lText);
    WriteLn('serving clipboard: ', lText);
    Flush(Output);
    for i := 1 to 600 do
      lApp.Display.WaitEvent(50);   { ~30s serving paste requests }
  end
  else if lMode = 'get' then
  begin
    if Assigned(lApp.Display.ClipboardOffer) then
      WriteLn('offer mimes: ', lApp.Display.ClipboardOffer.MimeTypes.CommaText)
    else
      WriteLn('offer mimes: <no selection offer>');
    Flush(Output);
    WriteLn('CLIP:', lApp.Display.ClipboardText);
    Flush(Output);
  end
  else
  begin
    WriteLn('unknown mode: ', lMode);
    Halt(1);
  end;

  lApp.Window.Free;
  lApp.Display.Free;
  lApp.Free;
end.
