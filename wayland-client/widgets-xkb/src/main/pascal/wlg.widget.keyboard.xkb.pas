// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.widget.keyboard.xkb — keysyms and text, via libxkbcommon.

  The IwgKeyTranslator TwgWindow needs before anything can be typed. wl_keyboard
  gives a client raw evdev codes and an XKB keymap on a file descriptor, and
  that is all: which character "keycode 38 with these modifiers in this layout"
  produces is a question only the keymap can answer, and answering it properly
  means compiling the keymap. libxkbcommon is what compiles it.

  ITS OWN MODULE, like widgets-gl, so wayland-widgets stays RTL-only: a program
  that draws widgets and never takes text input does not acquire a C library
  for the privilege. Applications opt in with wgUseXkbKeyboard.

  COMPOSE is handled, because a keyboard layout that can produce e-acute from
  a dead key is not an edge case outside en_US. A key first goes to the compose
  state machine; while it is mid-sequence the key produces NOTHING (returning
  the raw keysym there is what makes dead keys type a stray accent character),
  and when the sequence completes the composed result is returned in its place.

  THE +8. XKB keycodes are evdev codes plus 8, a historical offset from the X11
  protocol that every Wayland client has to apply and that nothing in the
  wl_keyboard documentation mentions. Getting it wrong does not fail loudly —
  it silently produces the wrong letters. }
unit wlg.widget.keyboard.xkb;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, BaseUnix,
  libxkbcommon, xkb_classes,
  wlg.widget.types, wlg.widget.window;

type
  { TwgXkbTranslator }

  TwgXkbTranslator = class(TInterfacedObject, IwgKeyTranslator)
  private
    FHelper: TXKBHelper;
    FMods: TwgModifiers;
  public
    destructor Destroy; override;

    procedure SetKeymap(AFd: LongInt; ASize: Integer);
    procedure UpdateModifiers(ADepressed, ALatched, ALocked, AGroup: LongWord);
    function  Translate(AEvdevCode: LongWord; out AKeySym: LongWord;
      out AText: String): Boolean;
    function  Modifiers: TwgModifiers;
    function  Repeats(AEvdevCode: LongWord): Boolean;
  end;

// Give AWindow keysym and text translation. The usual way to opt in; after
// this a TwgTextEdit in the tree can actually be typed into.
procedure wgUseXkbKeyboard(AWindow: TwgWindow);

implementation

const
  // XKB keycode = evdev code + 8. See the unit note.
  XkbKeycodeOffset = 8;

destructor TwgXkbTranslator.Destroy;
begin
  FHelper.Free;
  inherited Destroy;
end;

procedure TwgXkbTranslator.SetKeymap(AFd: LongInt; ASize: Integer);
begin
  // The compositor may send a new keymap at any time — the user switching
  // layout — so this replaces rather than assuming it runs once.
  FreeAndNil(FHelper);
  if (AFd >= 0) and (ASize > 0) then
  begin
    try
      FHelper := TXKBHelper.Create(AFd, ASize);
      if not FHelper.HasKeymap then
        // It mmapped and compiled nothing useful; better no translator than
        // one that answers every key with garbage.
        FreeAndNil(FHelper);
    except
      FreeAndNil(FHelper);
    end;
  end;
  // Ours to close either way: the contract says the receiver owns the fd, and
  // TXKBHelper only mmaps it for the duration of the compile.
  if AFd >= 0 then
    FpClose(AFd);
end;

procedure TwgXkbTranslator.UpdateModifiers(ADepressed, ALatched, ALocked,
  AGroup: LongWord);
var
  lState: TShiftState;
begin
  if FHelper = nil then
    Exit;
  FHelper.UpdateKeyState(ADepressed, ALatched, ALocked, AGroup);
  lState := FHelper.ModState;
  FMods := [];
  if ssShift in lState then Include(FMods, mdShift);
  if ssCtrl  in lState then Include(FMods, mdCtrl);
  if ssAlt   in lState then Include(FMods, mdAlt);
  if ssSuper in lState then Include(FMods, mdSuper);
  if ssCaps  in lState then Include(FMods, mdCapsLock);
  if ssNum   in lState then Include(FMods, mdNumLock);
end;

function TwgXkbTranslator.Modifiers: TwgModifiers;
begin
  Result := FMods;
end;

function TwgXkbTranslator.Repeats(AEvdevCode: LongWord): Boolean;
begin
  // Unknown keymap: assume not, so a stuck modifier cannot machine-gun the
  // focused widget.
  Result := (FHelper <> nil) and
            FHelper.KeyRepeats(AEvdevCode + XkbKeycodeOffset);
end;

function TwgXkbTranslator.Translate(AEvdevCode: LongWord;
  out AKeySym: LongWord; out AText: String): Boolean;
var
  lSym: xkb_keysym_t;
begin
  AKeySym := 0;
  AText := '';
  Result := False;
  if FHelper = nil then
    Exit;

  lSym := FHelper.KeyGetOneSym(AEvdevCode + XkbKeycodeOffset);
  if lSym = 0 then
    Exit;

  // Offer it to compose first. Feed remembers the symbol, so the status
  // afterwards describes THIS key.
  FHelper.Feed(lSym);
  case FHelper.ComposeStatus of
    XKB_COMPOSE_COMPOSING:
      // Mid-sequence: a dead key has been pressed and the character it will
      // become is not decided yet. Emitting anything now is what makes dead
      // keys insert a stray accent.
      Exit(False);
    XKB_COMPOSE_COMPOSED:
      begin
        AKeySym := FHelper.LookupSym;
        AText := FHelper.LookupUtf8;
        FHelper.ResetCompose;
        // A composed sequence may have no single keysym of its own; the text
        // is the real result.
        Exit((AText <> '') or (AKeySym <> 0));
      end;
    XKB_COMPOSE_CANCELLED:
      begin
        // An invalid sequence. Swallow it and start again rather than emitting
        // the fragments.
        FHelper.ResetCompose;
        Exit(False);
      end;
  end;

  AKeySym := lSym;
  AText := FHelper.KeySymToUtf8(lSym);
  Result := True;
end;

procedure wgUseXkbKeyboard(AWindow: TwgWindow);
begin
  if AWindow = nil then
    Exit;
  AWindow.SetKeyTranslator(TwgXkbTranslator.Create);
end;

end.
