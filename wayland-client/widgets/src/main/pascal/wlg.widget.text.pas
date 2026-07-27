// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.widget.text — a single-line text entry.

  TwgTextEdit is the first widget whose state is a document rather than a
  value, and almost everything awkward about it follows from that: a caret and
  a selection that have to survive every edit, a viewport that scrolls to keep
  the caret in sight, and text measurement in the middle of input handling
  rather than only at layout time.

  POSITIONS ARE BYTE OFFSETS into a UTF-8 string, 0..Length(FText). Not
  character counts — converting between the two on every keystroke is how text
  editors get quadratic — and not code point indices, because the string is the
  storage. Everything that moves a position steps whole UTF-8 sequences, so a
  caret can never land inside one and a Backspace removes a character rather
  than a byte. wgUtf8Prev/Next are the only places that know the encoding.

  THE SELECTION is the range between FAnchor and FCaret, in either order.
  Keeping the anchor rather than a normalised (start, length) pair is what lets
  shift-arrow extend in both directions and reverse through the anchor, which a
  normalised range cannot express.

  MEASUREMENT goes through the glyph source directly rather than the canvas:
  hit-testing a click and scrolling to the caret both happen during input, when
  there is no canvas in hand. TextWidthTo is deliberately the only measuring
  primitive — caret x, selection bounds and the scroll clamp are all defined in
  terms of it, so they cannot disagree about where a character starts.

  NOT A TEXT AREA. One line, no wrapping, no undo. Multi-line changes the model
  (line index, up/down that must remember a goal column, a vertical viewport)
  enough that bolting it on here would be worse than a second widget. }
unit wlg.widget.text;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Types, Math,
  wlg.surface, wlg.canvas.base,
  wlg.widget.types, wlg.widget.core, wlg.widget.input, wlg.widget.theme,
  wlg.widget.controls;

type
  { TwgTextEdit }

  TwgTextEdit = class(TwgControl)
  private
    FText: String;
    FPlaceholder: String;
    // Byte offsets into FText, 0..Length(FText). See the unit note.
    FCaret: Integer;
    FAnchor: Integer;
    // How far the text is scrolled left, in pixels. Only ever non-zero when
    // the text is wider than the inner rectangle.
    FScrollX: Integer;
    FReadOnly: Boolean;
    FMaxLength: Integer;
    FPasswordChar: Char;
    FOnChange: TNotifyEvent;
    FOnAccept: TNotifyEvent;
    // Caret blink. Phase is derived from the clock so a missed Step cannot
    // leave the caret stuck invisible.
    FBlinkOn: Boolean;
    FBlinkBase: QWord;
    FSelecting: Boolean;
    FLastClickTime: LongWord;
    FLastClickX: Integer;
    FClickCount: Integer;

    procedure SetText(const AValue: String);
    procedure SetCaretPos(AValue: Integer);
    function  GetSelStart: Integer;
    function  GetSelLength: Integer;
    function  GetSelText: String;
    // What is actually drawn: the text, or a run of password characters.
    function  DisplayText: String;
    // A byte offset in FText, expressed as a byte offset in DisplayText. The
    // two differ only when masking, where every code point becomes one byte.
    function  DisplayOffset(APos: Integer): Integer;
    function  InnerRect: TRect;
    // Pixel x of a byte offset, relative to the start of the text.
    function  XOfPos(APos: Integer): Integer;
    // The byte offset a pixel x lands on, snapped to the nearer boundary.
    function  PosOfX(AX: Integer): Integer;
    procedure EnsureVisible;
    procedure ResetBlink;
    function  Clipboard(out AIntf: IwgClipboardHost): Boolean;
    // Word boundaries around/adjacent to a position, for Ctrl+arrow and
    // double-click.
    function  WordStart(APos: Integer): Integer;
    function  WordEnd(APos: Integer): Integer;
    procedure Changed;
  protected
    procedure Paint(ACanvas: TwgCanvas); override;
    function  MeasureSize(AAvailW, AAvailH: Integer): TSize; override;
    // Toggles the caret and asks for the next half-period. Only ever pending
    // while focused, so an unfocused field costs the loop nothing.
    procedure Tick(ANowMs: QWord); override;
    // Replace the selection (or nothing, if none) with AText and put the caret
    // after it. The single funnel every edit goes through.
    procedure ReplaceSelection(const AText: String);
  public
    constructor Create(AOwner: TComponent); override;

    function  CanFocus: Boolean; override;
    procedure PointerDown(var AEvent: TwgPointerEvent); override;
    procedure PointerMove(var AEvent: TwgPointerEvent); override;
    procedure PointerUp(var AEvent: TwgPointerEvent); override;
    procedure PointerCancel(var AEvent: TwgPointerEvent); override;
    procedure KeyDown(var AEvent: TwgKeyEvent); override;
    procedure FocusIn; override;
    procedure FocusOut; override;

    procedure SelectAll;
    procedure ClearSelection;
    procedure Cut;
    procedure Copy;
    procedure Paste;
    property Text: String read FText write SetText;
    property Placeholder: String read FPlaceholder write FPlaceholder;
    property CaretPos: Integer read FCaret write SetCaretPos;
    property SelStart: Integer read GetSelStart;
    property SelLength: Integer read GetSelLength;
    property SelText: String read GetSelText;
    property ReadOnly: Boolean read FReadOnly write FReadOnly;
    // 0 = unlimited. Counted in BYTES, matching the storage.
    property MaxLength: Integer read FMaxLength write FMaxLength;
    // #0 shows the real text; anything else masks every character with it.
    property PasswordChar: Char read FPasswordChar write FPasswordChar;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    // Enter pressed.
    property OnAccept: TNotifyEvent read FOnAccept write FOnAccept;
  end;

{ --- UTF-8 navigation ---

  Offsets are 0-based byte counts. Both clamp to the string, so walking off
  either end is a no-op rather than an error. }
function wgUtf8Next(const AText: String; APos: Integer): Integer;
function wgUtf8Prev(const AText: String; APos: Integer): Integer;
// Width of the first ACount bytes of AText in AFont, including kerning.
function wgTextWidthTo(AFont: IwgGlyphSource; const AText: String;
  ACount: Integer): Single;

implementation

const
  // Half-period of the caret blink.
  BlinkMs = 530;

{ --- UTF-8 --- }

// A continuation byte is 10xxxxxx; every other byte starts a sequence.
function IsCont(AByte: Byte): Boolean; inline;
begin
  Result := (AByte and $C0) = $80;
end;

function wgUtf8Next(const AText: String; APos: Integer): Integer;
begin
  Result := APos;
  if Result >= Length(AText) then
    Exit(Length(AText));
  Inc(Result);
  // Skip to the next lead byte; a malformed tail cannot loop forever because
  // the bound is the string length.
  while (Result < Length(AText)) and IsCont(Byte(AText[Result + 1])) do
    Inc(Result);
end;

function wgUtf8Prev(const AText: String; APos: Integer): Integer;
begin
  Result := APos;
  if Result <= 0 then
    Exit(0);
  Dec(Result);
  while (Result > 0) and IsCont(Byte(AText[Result + 1])) do
    Dec(Result);
end;

// Decode one code point at a 0-based byte offset.
function CodePointAt(const AText: String; APos: Integer; out ALen: Integer): LongWord;
var
  b: Byte;
  i, n: Integer;
begin
  ALen := 1;
  if (APos < 0) or (APos >= Length(AText)) then
    Exit(0);
  b := Byte(AText[APos + 1]);
  if b < $80 then
    Exit(b);
  if (b and $E0) = $C0 then begin Result := b and $1F; n := 1; end
  else if (b and $F0) = $E0 then begin Result := b and $0F; n := 2; end
  else if (b and $F8) = $F0 then begin Result := b and $07; n := 3; end
  else Exit(b);   // stray continuation byte: pass it through rather than fail
  for i := 1 to n do
  begin
    if APos + i >= Length(AText) then
      Break;
    Result := (Result shl 6) or (Byte(AText[APos + i + 1]) and $3F);
    Inc(ALen);
  end;
end;

function wgTextWidthTo(AFont: IwgGlyphSource; const AText: String;
  ACount: Integer): Single;
var
  i, lLen: Integer;
  lCP, lGlyph, lPrev: LongWord;
  lInfo: TwgGlyphInfo;
begin
  Result := 0;
  if (AFont = nil) or (AText = '') then
    Exit;
  ACount := Min(ACount, Length(AText));
  i := 0;
  lPrev := 0;
  while i < ACount do
  begin
    lCP := CodePointAt(AText, i, lLen);
    lGlyph := AFont.GetGlyphIndex(lCP);
    if lPrev <> 0 then
      Result := Result + AFont.GetKerning(lPrev, lGlyph);
    if AFont.GetGlyph(lGlyph, lInfo) then
      Result := Result + lInfo.Advance;
    lPrev := lGlyph;
    Inc(i, lLen);
  end;
end;

{ TwgTextEdit }

constructor TwgTextEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCaret := 0;
  FAnchor := 0;
  FPasswordChar := #0;
  FBlinkOn := True;
  FBlinkBase := GetTickCount64;
  // The text must not spill out of the well when it is longer than the field.
  ClipChildren := True;
end;

function TwgTextEdit.CanFocus: Boolean;
begin
  Result := Enabled and Visible;
end;

function TwgTextEdit.DisplayText: String;
var
  i: Integer;
  lCount: Integer;
begin
  if FPasswordChar = #0 then
    Exit(FText);
  // One mask character per CODE POINT, not per byte, or a non-ASCII password
  // would show its own length.
  lCount := 0;
  i := 0;
  while i < Length(FText) do
  begin
    Inc(lCount);
    i := wgUtf8Next(FText, i);
  end;
  Result := StringOfChar(FPasswordChar, lCount);
end;

function TwgTextEdit.InnerRect: TRect;
var
  lTheme: TwgTheme;
  lPad: Integer;
begin
  lTheme := Theme;
  if lTheme <> nil then
    lPad := lTheme.Metrics.Padding
  else
    lPad := 6;
  Result := Rect(lPad, 0, Width - lPad, Height);
end;

function TwgTextEdit.DisplayOffset(APos: Integer): Integer;
var
  i: Integer;
begin
  if FPasswordChar = #0 then
    Exit(Max(0, Min(APos, Length(FText))));
  // Masked: count code points before APos; each is one byte of the mask.
  Result := 0;
  i := 0;
  while i < APos do
  begin
    i := wgUtf8Next(FText, i);
    Inc(Result);
  end;
end;

function TwgTextEdit.XOfPos(APos: Integer): Integer;
begin
  Result := Round(wgTextWidthTo(EffectiveFont, DisplayText, DisplayOffset(APos)));
end;

function TwgTextEdit.PosOfX(AX: Integer): Integer;
var
  lFont: IwgGlyphSource;
  lDisplay: String;
  i, lNext: Integer;
  lThis, lAfter: Single;
begin
  Result := 0;
  lFont := EffectiveFont;
  lDisplay := DisplayText;
  if (lFont = nil) or (lDisplay = '') then
    Exit;
  i := 0;
  while i < Length(FText) do
  begin
    lNext := wgUtf8Next(FText, i);
    lThis := wgTextWidthTo(lFont, lDisplay, DisplayOffset(i));
    lAfter := wgTextWidthTo(lFont, lDisplay, DisplayOffset(lNext));
    // Snap to whichever boundary is nearer, so clicking the right half of a
    // character puts the caret after it — what every other editor does.
    if AX < (lThis + lAfter) / 2 then
      Exit(i);
    i := lNext;
  end;
  Result := Length(FText);
end;

procedure TwgTextEdit.ResetBlink;
begin
  FBlinkOn := True;
  FBlinkBase := GetTickCount64;
  // Restart the phase from now, so the caret is solid while typing rather
  // than blinking out mid-keystroke.
  if wsFocused in States then
    RequestTick(BlinkMs);
end;

procedure TwgTextEdit.Tick(ANowMs: QWord);
begin
  if not (wsFocused in States) then
  begin
    // Focus left; stop by simply not asking again.
    if FBlinkOn then
    begin
      FBlinkOn := False;
      Invalidate;
    end;
    Exit;
  end;
  FBlinkOn := not FBlinkOn;
  // Only the caret changed, so damage only the caret. This is what keeps a
  // blinking cursor from repainting the whole field twice a second.
  InvalidateRect(Rect(XOfPos(FCaret) + InnerRect.Left - FScrollX - 1, 0,
                      XOfPos(FCaret) + InnerRect.Left - FScrollX + 3, Height));
  RequestTick(BlinkMs);
end;

function TwgTextEdit.MeasureSize(AAvailW, AAvailH: Integer): TSize;
var
  lTheme: TwgTheme;
begin
  lTheme := Theme;
  // A field's width is what it is given, not what it holds — measuring to the
  // content would make the box grow as you type. Report a usable minimum.
  Result.cx := 140;
  if lTheme <> nil then
    Result.cy := Math.Max(lTheme.Metrics.ControlHeight,
                          lTheme.Metrics.MinTouchTarget)
  else
    Result.cy := 32;
end;

{ --- selection --- }

function TwgTextEdit.GetSelStart: Integer;
begin
  Result := Min(FCaret, FAnchor);
end;

function TwgTextEdit.GetSelLength: Integer;
begin
  Result := Abs(FCaret - FAnchor);
end;

function TwgTextEdit.GetSelText: String;
begin
  Result := System.Copy(FText, GetSelStart + 1, GetSelLength);
end;

procedure TwgTextEdit.SelectAll;
begin
  FAnchor := 0;
  FCaret := Length(FText);
  EnsureVisible;
  ResetBlink;
  Invalidate;
end;

procedure TwgTextEdit.ClearSelection;
begin
  FAnchor := FCaret;
  Invalidate;
end;

procedure TwgTextEdit.SetCaretPos(AValue: Integer);
begin
  AValue := Max(0, Min(AValue, Length(FText)));
  FCaret := AValue;
  FAnchor := AValue;
  EnsureVisible;
  ResetBlink;
  Invalidate;
end;

procedure TwgTextEdit.SetText(const AValue: String);
begin
  if FText = AValue then
    Exit;
  FText := AValue;
  FCaret := Min(FCaret, Length(FText));
  FAnchor := FCaret;
  FScrollX := 0;
  EnsureVisible;
  Invalidate;
  Changed;
end;

procedure TwgTextEdit.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TwgTextEdit.ReplaceSelection(const AText: String);
var
  lStart, lLen: Integer;
  lInsert: String;
begin
  if FReadOnly then
    Exit;
  lStart := GetSelStart;
  lLen := GetSelLength;
  lInsert := AText;
  if FMaxLength > 0 then
  begin
    // The limit applies to what would remain, so replacing a selection with
    // something the same size is always allowed even at the limit.
    if Length(FText) - lLen + Length(lInsert) > FMaxLength then
      SetLength(lInsert, Max(0, FMaxLength - (Length(FText) - lLen)));
    // Never truncate mid-sequence.
    while (Length(lInsert) > 0) and IsCont(Byte(lInsert[Length(lInsert)])) do
      SetLength(lInsert, Length(lInsert) - 1);
  end;
  if (lLen = 0) and (lInsert = '') then
    Exit;
  System.Delete(FText, lStart + 1, lLen);
  System.Insert(lInsert, FText, lStart + 1);
  FCaret := lStart + Length(lInsert);
  FAnchor := FCaret;
  EnsureVisible;
  ResetBlink;
  Invalidate;
  Changed;
end;

{ --- clipboard --- }

function TwgTextEdit.Clipboard(out AIntf: IwgClipboardHost): Boolean;
var
  lHost: IwgWidgetHost;
begin
  AIntf := nil;
  lHost := Host;
  Result := (lHost <> nil) and
            Supports(lHost, IwgClipboardHost, AIntf);
end;

procedure TwgTextEdit.Copy;
var
  lClip: IwgClipboardHost;
begin
  // Never put a masked field's contents on the clipboard.
  if (GetSelLength = 0) or (FPasswordChar <> #0) then
    Exit;
  if Clipboard(lClip) then
    lClip.HostSetClipboardText(GetSelText);
end;

procedure TwgTextEdit.Cut;
begin
  if FReadOnly or (GetSelLength = 0) then
    Exit;
  Copy;
  ReplaceSelection('');
end;

procedure TwgTextEdit.Paste;
var
  lClip: IwgClipboardHost;
  lText: String;
  i: Integer;
begin
  if FReadOnly or (not Clipboard(lClip)) then
    Exit;
  lText := lClip.HostClipboardText;
  // A single-line field must not swallow newlines: stop at the first one
  // rather than storing a character it can never display.
  for i := 1 to Length(lText) do
    if lText[i] in [#10, #13] then
    begin
      SetLength(lText, i - 1);
      Break;
    end;
  if lText <> '' then
    ReplaceSelection(lText);
end;

{ --- words --- }

// Word characters are everything that is not a space or punctuation we care
// about. Deliberately crude: matching a real word-break algorithm here would
// mean carrying Unicode tables the toolkit does not otherwise need.
function IsWordByte(AByte: Byte): Boolean; inline;
begin
  Result := not (AByte in [Ord(' '), Ord(#9), Ord('.'), Ord(','), Ord(';'),
    Ord(':'), Ord('!'), Ord('?'), Ord('/'), Ord('\'), Ord('('), Ord(')'),
    Ord('['), Ord(']'), Ord('{'), Ord('}'), Ord('"'), Ord('''')]);
end;

function TwgTextEdit.WordStart(APos: Integer): Integer;
begin
  Result := APos;
  while (Result > 0) and (not IsWordByte(Byte(FText[Result]))) do
    Result := wgUtf8Prev(FText, Result);
  while (Result > 0) and IsWordByte(Byte(FText[Result])) do
    Result := wgUtf8Prev(FText, Result);
end;

function TwgTextEdit.WordEnd(APos: Integer): Integer;
begin
  Result := APos;
  while (Result < Length(FText)) and (not IsWordByte(Byte(FText[Result + 1]))) do
    Result := wgUtf8Next(FText, Result);
  while (Result < Length(FText)) and IsWordByte(Byte(FText[Result + 1])) do
    Result := wgUtf8Next(FText, Result);
end;

{ --- scrolling --- }

procedure TwgTextEdit.EnsureVisible;
var
  lInner: TRect;
  lCaretX, lWidth, lTextW: Integer;
begin
  lInner := InnerRect;
  lWidth := lInner.Right - lInner.Left;
  if lWidth <= 0 then
    Exit;
  lCaretX := XOfPos(FCaret);
  if lCaretX - FScrollX < 0 then
    FScrollX := lCaretX
  else if lCaretX - FScrollX > lWidth then
    FScrollX := lCaretX - lWidth;
  // Never leave blank space on the right while text is scrolled off the left.
  lTextW := Round(wgTextWidthTo(EffectiveFont, DisplayText, MaxInt));
  FScrollX := Max(0, Min(FScrollX, Max(0, lTextW - lWidth)));
end;

{ --- input --- }

procedure TwgTextEdit.FocusIn;
begin
  ResetBlink;      // also starts the blink ticking
  Invalidate;
end;

procedure TwgTextEdit.FocusOut;
begin
  FSelecting := False;
  FBlinkOn := False;
  // Nothing further is scheduled: the blink stops costing anything the moment
  // the field is not focused.
  CancelTick;
  Invalidate;
end;

procedure TwgTextEdit.PointerDown(var AEvent: TwgPointerEvent);
var
  lPos: Integer;
begin
  AEvent.Handled := True;
  if not Enabled then
    Exit;
  lPos := PosOfX(AEvent.X - InnerRect.Left + FScrollX);

  // Double click selects a word. The router gives every event a time, so no
  // separate clock is needed.
  if (AEvent.Time - FLastClickTime < 400) and (Abs(AEvent.X - FLastClickX) < 4) then
    Inc(FClickCount)
  else
    FClickCount := 1;
  FLastClickTime := AEvent.Time;
  FLastClickX := AEvent.X;

  case FClickCount of
    2:
      begin
        FAnchor := WordStart(lPos);
        FCaret := WordEnd(lPos);
      end;
    3:
      SelectAll;
    else
      begin
        FCaret := lPos;
        // Shift-click extends the existing selection instead of starting one.
        if not (mdShift in AEvent.Modifiers) then
          FAnchor := lPos;
        FSelecting := True;
      end;
  end;
  EnsureVisible;
  ResetBlink;
  Invalidate;
end;

procedure TwgTextEdit.PointerMove(var AEvent: TwgPointerEvent);
begin
  if not FSelecting then
    Exit;
  // Travelling any distance ends the multi-click run: a press that follows a
  // drag is a new click, not the second of a pair, even when it lands back
  // where the drag started within the double-click time.
  if Abs(AEvent.X - FLastClickX) > 4 then
    FClickCount := 0;
  // The router holds the grab, so AEvent.X may be well outside the field —
  // which is what makes dragging past the edge keep extending the selection.
  FCaret := PosOfX(AEvent.X - InnerRect.Left + FScrollX);
  EnsureVisible;
  Invalidate;
  AEvent.Handled := True;
end;

procedure TwgTextEdit.PointerUp(var AEvent: TwgPointerEvent);
begin
  FSelecting := False;
  AEvent.Handled := True;
end;

procedure TwgTextEdit.PointerCancel(var AEvent: TwgPointerEvent);
begin
  // A gesture took the sequence; the drag-select must not stay armed.
  FSelecting := False;
  Invalidate;
end;

procedure TwgTextEdit.KeyDown(var AEvent: TwgKeyEvent);
var
  lShift, lCtrl: Boolean;
  lNew: Integer;

  // Every caret move shares this: extend the selection when shift is held,
  // collapse it otherwise.
  procedure MoveTo(APos: Integer);
  begin
    FCaret := Max(0, Min(APos, Length(FText)));
    if not lShift then
      FAnchor := FCaret;
    EnsureVisible;
    ResetBlink;
    Invalidate;
  end;

begin
  if not Enabled then
    Exit;
  lShift := mdShift in AEvent.Modifiers;
  lCtrl := mdCtrl in AEvent.Modifiers;

  case AEvent.KeySym of
    wgKeyLeft:
      begin
        if lCtrl then MoveTo(WordStart(FCaret))
        else if (not lShift) and (GetSelLength > 0) then MoveTo(GetSelStart)
        else MoveTo(wgUtf8Prev(FText, FCaret));
        AEvent.Handled := True;
      end;
    wgKeyRight:
      begin
        if lCtrl then MoveTo(WordEnd(FCaret))
        else if (not lShift) and (GetSelLength > 0) then
          MoveTo(GetSelStart + GetSelLength)
        else MoveTo(wgUtf8Next(FText, FCaret));
        AEvent.Handled := True;
      end;
    wgKeyHome:
      begin MoveTo(0); AEvent.Handled := True; end;
    wgKeyEnd:
      begin MoveTo(Length(FText)); AEvent.Handled := True; end;

    wgKeyBackSpace:
      begin
        if GetSelLength > 0 then
          ReplaceSelection('')
        else if FCaret > 0 then
        begin
          lNew := wgUtf8Prev(FText, FCaret);
          FAnchor := lNew;   // make it a selection, then delete it
          ReplaceSelection('');
        end;
        AEvent.Handled := True;
      end;
    wgKeyDelete:
      begin
        if GetSelLength > 0 then
          ReplaceSelection('')
        else if FCaret < Length(FText) then
        begin
          FAnchor := wgUtf8Next(FText, FCaret);
          ReplaceSelection('');
        end;
        AEvent.Handled := True;
      end;

    wgKeyReturn:
      begin
        if Assigned(FOnAccept) then
          FOnAccept(Self);
        AEvent.Handled := True;
      end;
    wgKeyEscape:
      begin
        ClearSelection;
        AEvent.Handled := True;
      end;
  end;

  if AEvent.Handled then
    Exit;

  if lCtrl then
  begin
    // Compare the keysym directly: with Ctrl held the translator produces a
    // control character rather than a letter, so Text is no use here.
    case AEvent.KeySym of
      Ord('a'), Ord('A'): begin SelectAll; AEvent.Handled := True; end;
      Ord('c'), Ord('C'): begin Copy; AEvent.Handled := True; end;
      Ord('x'), Ord('X'): begin Cut; AEvent.Handled := True; end;
      Ord('v'), Ord('V'): begin Paste; AEvent.Handled := True; end;
    end;
    // Any other Ctrl combination is a shortcut for someone else; never insert
    // its text.
    Exit;
  end;

  // Ordinary typing. Control characters (Tab, Escape, Backspace) arrive here
  // as text too and must not be inserted.
  if (AEvent.Text <> '') and (Byte(AEvent.Text[1]) >= 32) and
     (Byte(AEvent.Text[1]) <> 127) then
  begin
    ReplaceSelection(AEvent.Text);
    AEvent.Handled := True;
  end;
end;

{ --- painting --- }

procedure TwgTextEdit.Paint(ACanvas: TwgCanvas);
var
  lTheme: TwgTheme;
  lInner: TRect;
  lFont: IwgGlyphSource;
  lDisplay: String;
  lBaseline, lSelX0, lSelX1, lCaretX: Integer;
  lStates: TwgWidgetStates;
begin
  lTheme := Theme;
  if lTheme = nil then
    Exit;
  lStates := States;
  lInner := InnerRect;
  lFont := EffectiveFont;

  lTheme.DrawWell(ACanvas, Rect(0, 0, Width, Height), lStates);

  ACanvas.Save;
  try
    // Clip before translating: everything below draws in text coordinates and
    // must not escape the well.
    ACanvas.ClipRect(lInner.Left, lInner.Top,
      lInner.Right - lInner.Left, lInner.Bottom - lInner.Top);
    ACanvas.Translate(lInner.Left - FScrollX, 0);

    lDisplay := DisplayText;
    if lFont <> nil then
      lBaseline := Round((Height + lFont.GetAscent - lFont.GetDescent) / 2)
    else
      lBaseline := Height div 2;

    if (lDisplay = '') and (FPlaceholder <> '') and (not (wsFocused in lStates)) then
    begin
      ACanvas.Font := lFont;
      ACanvas.DrawText(FPlaceholder, 0, lBaseline, lTheme.Palette.TextDim);
    end
    else
    begin
      // Selection goes under the text, and only when focused — a field that
      // has lost focus showing a highlight looks active when it is not.
      if (GetSelLength > 0) and (wsFocused in lStates) then
      begin
        lSelX0 := XOfPos(GetSelStart);
        lSelX1 := XOfPos(GetSelStart + GetSelLength);
        ACanvas.FillRect(lSelX0, 2, lSelX1 - lSelX0, Height - 4,
          lTheme.Palette.Accent);
      end;
      ACanvas.Font := lFont;
      if lDisplay <> '' then
        ACanvas.DrawText(lDisplay, 0, lBaseline, lTheme.TextFor(lStates));
    end;

    if FBlinkOn and (wsFocused in lStates) and (not FReadOnly) then
    begin
      lCaretX := XOfPos(FCaret);
      ACanvas.FillRect(lCaretX, 3, Max(1, Round(lTheme.Metrics.BorderWidth)),
        Height - 6, lTheme.Palette.Text);
    end;
  finally
    ACanvas.Restore;
  end;

  if wsFocused in lStates then
    lTheme.DrawFocusRing(ACanvas, Rect(0, 0, Width, Height));
end;

end.
