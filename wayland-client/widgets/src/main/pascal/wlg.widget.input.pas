// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.widget.input — turning seat events into widget events.

  TwgInputRouter takes the flat stream a TfpgwDisplay produces — a pointer, a
  keyboard, and any number of simultaneous touch contacts — and decides which
  widget each event belongs to.

  MULTI-POINTER THROUGHOUT. Everything here is keyed on a sequence id: the
  mouse is one fixed sequence, and each touch contact is its own for as long as
  it is down. That is why capture is a per-sequence map rather than a single
  field. A single global capture is the specific thing that breaks multi-touch —
  two fingers dragging two different sliders must each keep their own grab, and
  with one shared slot the second press steals the first one's.

  CAPTURE. A press grabs the widget it landed on and holds it until release,
  even as the pointer leaves. Without that, dragging a slider stops working the
  moment you slip off it, which makes sliders and scrollbars unusable. Capture
  also decides where the release goes, and a click is only synthesised when
  press and release agree.

  ENTER/LEAVE is computed over the ancestor CHAIN, not just the leaf. Moving
  from a button into a label inside the same panel must not tell the panel it
  was left; only the parts of the chain that actually changed get told. Touch
  never generates hover: a finger has no position until it touches, and
  synthesising hover from it produces controls that light up under a tap and
  stay lit.

  FOCUS is per window, moved by clicking a focusable widget or by Tab, and key
  events go to the focused widget and bubble to its ancestors. }
unit wlg.widget.input;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Types, Math,
  wlg.widget.types, wlg.widget.core;

type
  { What a widget overrides to receive input. Separate from TwgWidget so the
    core stays about structure and painting; TwgInputRouter checks for it. }
  IwgInputTarget = interface
    ['{7C31A9E5-4D08-4B72-9E16-58F0B3D7A2C9}']
    procedure PointerDown(var AEvent: TwgPointerEvent);
    procedure PointerUp(var AEvent: TwgPointerEvent);
    procedure PointerMove(var AEvent: TwgPointerEvent);
    procedure PointerEnter(var AEvent: TwgPointerEvent);
    procedure PointerLeave(var AEvent: TwgPointerEvent);
    // Press and release on the same widget.
    procedure Click(var AEvent: TwgPointerEvent);
    // Capture was taken away — a gesture claimed the sequence, or the
    // compositor cancelled the touch. Undo any in-progress interaction; this
    // is NOT a release and must not act like one.
    procedure PointerCancel(var AEvent: TwgPointerEvent);
    procedure Scroll(var AEvent: TwgScrollEvent);
    procedure KeyDown(var AEvent: TwgKeyEvent);
    procedure KeyUp(var AEvent: TwgKeyEvent);
    procedure FocusIn;
    procedure FocusOut;
    function  CanFocus: Boolean;
  end;

  { TwgInputRouter }

  TwgInputRouter = class
  private
    type
      TSequence = record
        Id: TwgSequenceId;
        Capture: TwgWidget;       // grabbed on press, held until release
        Pressed: TwgWidget;       // where the press landed, for click synthesis
        Source: TwgInputSource;
        LastX, LastY: Integer;    // root coordinates
        Active: Boolean;
      end;
  private
    FRoot: TwgWidget;
    FSequences: array of TSequence;
    // Ancestor chain currently hovered, innermost last. Only the mouse has one.
    FHoverChain: array of TwgWidget;
    FFocused: TwgWidget;
    FModifiers: TwgModifiers;

    function  IndexOfSeq(AId: TwgSequenceId): Integer;
    function  Seq(AId: TwgSequenceId; ASource: TwgInputSource): Integer;
    procedure DropSeq(AId: TwgSequenceId);

    function  Target(AWidget: TwgWidget; out AIntf: IwgInputTarget): Boolean;
    // Deliver to AWidget and bubble to ancestors until Handled.
    procedure Dispatch(AWidget: TwgWidget; var AEvent: TwgPointerEvent;
      AKind: Integer);
    procedure DispatchScroll(AWidget: TwgWidget; var AEvent: TwgScrollEvent);
    procedure UpdateHover(AHit: TwgWidget; AX, AY: Integer; ATime: LongWord);
    procedure ChainOf(AWidget: TwgWidget; out AChain: array of TwgWidget;
      out ACount: Integer);
    function  MakeEvent(AWidget: TwgWidget; ARootX, ARootY: Integer;
      ASource: TwgInputSource; ASeq: TwgSequenceId; AButton: LongWord;
      ATime: LongWord): TwgPointerEvent;
  public
    constructor Create(ARoot: TwgWidget);
    destructor Destroy; override;

    { --- pointer (mouse) --- }
    procedure MouseMove(AX, AY: Integer; ATime: LongWord);
    procedure MouseDown(AX, AY: Integer; AButton: LongWord; ATime: LongWord);
    procedure MouseUp(AX, AY: Integer; AButton: LongWord; ATime: LongWord);
    procedure MouseLeaveSurface;
    procedure MouseScroll(AX, AY: Integer; ADX, ADY: Single; ATime: LongWord);

    { --- touch --- }
    procedure TouchDown(AId: Integer; AX, AY: Integer; ATime: LongWord);
    procedure TouchMove(AId: Integer; AX, AY: Integer; ATime: LongWord);
    procedure TouchUp(AId: Integer; ATime: LongWord);
    // The compositor claimed the gesture: every contact is void.
    procedure TouchCancel;

    { --- keyboard --- }
    procedure KeyDown(AKeySym, AScanCode: LongWord; const AText: String;
      ARepeated: Boolean; ATime: LongWord);
    procedure KeyUp(AKeySym, AScanCode: LongWord; ATime: LongWord);
    procedure SetModifiers(AMods: TwgModifiers);

    { --- focus --- }
    procedure SetFocus(AWidget: TwgWidget);
    function  FocusNext(ABackwards: Boolean = False): Boolean;
    // Called when a widget is going away, so no stale grab or focus survives.
    procedure WidgetDestroyed(AWidget: TwgWidget);
    // Take the sequence away from whoever holds it (a gesture recogniser won).
    procedure CancelSequence(AId: TwgSequenceId);

    property Root: TwgWidget read FRoot write FRoot;
    property Focused: TwgWidget read FFocused;
    property Modifiers: TwgModifiers read FModifiers;
  end;

const
  // Dispatch kinds for the shared bubbling helper.
  wgEvDown   = 0;
  wgEvUp     = 1;
  wgEvMove   = 2;
  wgEvEnter  = 3;
  wgEvLeave  = 4;
  wgEvClick  = 5;
  wgEvCancel = 6;

  MaxChainDepth = 128;

implementation

{ TwgInputRouter }

constructor TwgInputRouter.Create(ARoot: TwgWidget);
begin
  inherited Create;
  FRoot := ARoot;
end;

destructor TwgInputRouter.Destroy;
begin
  SetLength(FSequences, 0);
  SetLength(FHoverChain, 0);
  inherited Destroy;
end;

function TwgInputRouter.IndexOfSeq(AId: TwgSequenceId): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FSequences) do
    if FSequences[i].Active and (FSequences[i].Id = AId) then
      Exit(i);
  Result := -1;
end;

function TwgInputRouter.Seq(AId: TwgSequenceId; ASource: TwgInputSource): Integer;
var
  i: Integer;
begin
  Result := IndexOfSeq(AId);
  if Result >= 0 then
    Exit;
  // Reuse a dead slot before growing; touch ids churn constantly.
  for i := 0 to High(FSequences) do
    if not FSequences[i].Active then
    begin
      FSequences[i] := Default(TSequence);
      FSequences[i].Id := AId;
      FSequences[i].Source := ASource;
      FSequences[i].Active := True;
      Exit(i);
    end;
  SetLength(FSequences, Length(FSequences) + 1);
  Result := High(FSequences);
  FSequences[Result] := Default(TSequence);
  FSequences[Result].Id := AId;
  FSequences[Result].Source := ASource;
  FSequences[Result].Active := True;
end;

procedure TwgInputRouter.DropSeq(AId: TwgSequenceId);
var
  i: Integer;
begin
  i := IndexOfSeq(AId);
  if i >= 0 then
    FSequences[i] := Default(TSequence);   // Active := False
end;

function TwgInputRouter.Target(AWidget: TwgWidget; out AIntf: IwgInputTarget): Boolean;
begin
  AIntf := nil;
  Result := (AWidget <> nil) and AWidget.GetInterface(IwgInputTarget, AIntf);
end;

function TwgInputRouter.MakeEvent(AWidget: TwgWidget; ARootX, ARootY: Integer;
  ASource: TwgInputSource; ASeq: TwgSequenceId; AButton: LongWord;
  ATime: LongWord): TwgPointerEvent;
var
  p: TPoint;
begin
  Result := Default(TwgPointerEvent);
  if AWidget <> nil then
  begin
    p := AWidget.RootToLocal(ARootX, ARootY);
    Result.X := p.X;
    Result.Y := p.Y;
  end;
  Result.Source := ASource;
  Result.Sequence := ASeq;
  Result.Button := AButton;
  Result.Modifiers := FModifiers;
  Result.Time := ATime;
end;

procedure TwgInputRouter.Dispatch(AWidget: TwgWidget; var AEvent: TwgPointerEvent;
  AKind: Integer);
var
  w: TwgWidget;
  lIntf: IwgInputTarget;
  lRootX, lRootY: Integer;
  p: TPoint;
begin
  if AWidget = nil then
    Exit;
  // Remember where it happened in root terms; each ancestor needs the point
  // in ITS coordinates, not the leaf's.
  p := AWidget.LocalToRoot(AEvent.X, AEvent.Y);
  lRootX := p.X;
  lRootY := p.Y;

  w := AWidget;
  while w <> nil do
  begin
    if Target(w, lIntf) then
    begin
      p := w.RootToLocal(lRootX, lRootY);
      AEvent.X := p.X;
      AEvent.Y := p.Y;
      case AKind of
        wgEvDown:   lIntf.PointerDown(AEvent);
        wgEvUp:     lIntf.PointerUp(AEvent);
        wgEvMove:   lIntf.PointerMove(AEvent);
        wgEvEnter:  lIntf.PointerEnter(AEvent);
        wgEvLeave:  lIntf.PointerLeave(AEvent);
        wgEvClick:  lIntf.Click(AEvent);
        wgEvCancel: lIntf.PointerCancel(AEvent);
      end;
      if AEvent.Handled then
        Exit;
    end;
    // Enter and leave describe one widget; they do not bubble.
    if AKind in [wgEvEnter, wgEvLeave] then
      Exit;
    w := w.Parent;
  end;
end;

procedure TwgInputRouter.DispatchScroll(AWidget: TwgWidget;
  var AEvent: TwgScrollEvent);
var
  w: TwgWidget;
  lIntf: IwgInputTarget;
  lRootX, lRootY: Integer;
  p: TPoint;
begin
  if AWidget = nil then
    Exit;
  p := AWidget.LocalToRoot(AEvent.X, AEvent.Y);
  lRootX := p.X;
  lRootY := p.Y;
  w := AWidget;
  while w <> nil do
  begin
    if Target(w, lIntf) then
    begin
      p := w.RootToLocal(lRootX, lRootY);
      AEvent.X := p.X;
      AEvent.Y := p.Y;
      lIntf.Scroll(AEvent);
      if AEvent.Handled then
        Exit;
    end;
    w := w.Parent;
  end;
end;

procedure TwgInputRouter.ChainOf(AWidget: TwgWidget; out AChain: array of TwgWidget;
  out ACount: Integer);
var
  w: TwgWidget;
  i, n: Integer;
begin
  // Build root-first so two chains can be compared by common prefix.
  n := 0;
  w := AWidget;
  while (w <> nil) and (n < MaxChainDepth) do
  begin
    Inc(n);
    w := w.Parent;
  end;
  ACount := n;
  w := AWidget;
  for i := n - 1 downto 0 do
  begin
    AChain[i] := w;
    w := w.Parent;
  end;
end;

procedure TwgInputRouter.UpdateHover(AHit: TwgWidget; AX, AY: Integer;
  ATime: LongWord);
var
  lNew: array[0..MaxChainDepth - 1] of TwgWidget;
  lCount, i, lCommon: Integer;
  lEvent: TwgPointerEvent;
begin
  ChainOf(AHit, lNew, lCount);

  // How much of the old chain survives. Everything below the common prefix
  // is genuinely left, everything above genuinely entered; the shared part is
  // untouched, which is what stops a panel seeing leave/enter when the pointer
  // merely moves between two of its children.
  lCommon := 0;
  while (lCommon < lCount) and (lCommon < Length(FHoverChain)) and
        (lNew[lCommon] = FHoverChain[lCommon]) do
    Inc(lCommon);

  // Leave, innermost first.
  for i := High(FHoverChain) downto lCommon do
    if FHoverChain[i] <> nil then
    begin
      FHoverChain[i].SetState(wsHovered, False);
      lEvent := MakeEvent(FHoverChain[i], AX, AY, isMouse, wgMouseSequence, 0, ATime);
      Dispatch(FHoverChain[i], lEvent, wgEvLeave);
    end;

  // Enter, outermost first.
  for i := lCommon to lCount - 1 do
  begin
    lNew[i].SetState(wsHovered, True);
    lEvent := MakeEvent(lNew[i], AX, AY, isMouse, wgMouseSequence, 0, ATime);
    Dispatch(lNew[i], lEvent, wgEvEnter);
  end;

  SetLength(FHoverChain, lCount);
  for i := 0 to lCount - 1 do
    FHoverChain[i] := lNew[i];
end;

{ --- mouse --- }

procedure TwgInputRouter.MouseMove(AX, AY: Integer; ATime: LongWord);
var
  i: Integer;
  lHit: TwgWidget;
  lEvent: TwgPointerEvent;
begin
  if FRoot = nil then
    Exit;
  i := IndexOfSeq(wgMouseSequence);

  // While captured, the grab holder gets the motion wherever the pointer is —
  // that is the whole point of a grab — but hover still tracks the real
  // widget under the cursor.
  if (i >= 0) and (FSequences[i].Capture <> nil) then
  begin
    FSequences[i].LastX := AX;
    FSequences[i].LastY := AY;
    lEvent := MakeEvent(FSequences[i].Capture, AX, AY, isMouse, wgMouseSequence, 0, ATime);
    Dispatch(FSequences[i].Capture, lEvent, wgEvMove);
    Exit;
  end;

  lHit := FRoot.HitTest(AX, AY);
  UpdateHover(lHit, AX, AY, ATime);
  if lHit <> nil then
  begin
    lEvent := MakeEvent(lHit, AX, AY, isMouse, wgMouseSequence, 0, ATime);
    Dispatch(lHit, lEvent, wgEvMove);
  end;
end;

procedure TwgInputRouter.MouseDown(AX, AY: Integer; AButton: LongWord;
  ATime: LongWord);
var
  i: Integer;
  lHit: TwgWidget;
  lEvent: TwgPointerEvent;
  lIntf: IwgInputTarget;
begin
  if FRoot = nil then
    Exit;
  lHit := FRoot.HitTest(AX, AY);
  if lHit = nil then
    Exit;

  i := Seq(wgMouseSequence, isMouse);
  FSequences[i].Capture := lHit;
  FSequences[i].Pressed := lHit;
  FSequences[i].LastX := AX;
  FSequences[i].LastY := AY;

  // Focus follows a press on anything that wants it, walking up so clicking a
  // label inside a focusable panel still focuses the panel.
  lHit.SetState(wsPressed, True);
  if Target(lHit, lIntf) and lIntf.CanFocus then
    SetFocus(lHit);

  lEvent := MakeEvent(lHit, AX, AY, isMouse, wgMouseSequence, AButton, ATime);
  Dispatch(lHit, lEvent, wgEvDown);
end;

procedure TwgInputRouter.MouseUp(AX, AY: Integer; AButton: LongWord;
  ATime: LongWord);
var
  i: Integer;
  lCapture, lHit: TwgWidget;
  lEvent: TwgPointerEvent;
begin
  if FRoot = nil then
    Exit;
  i := IndexOfSeq(wgMouseSequence);
  if i < 0 then
    Exit;
  lCapture := FSequences[i].Capture;
  if lCapture = nil then
    Exit;
  lCapture.SetState(wsPressed, False);

  lEvent := MakeEvent(lCapture, AX, AY, isMouse, wgMouseSequence, AButton, ATime);
  Dispatch(lCapture, lEvent, wgEvUp);

  // A click only happens if the release is still over the widget that was
  // pressed — dragging off and letting go must not activate it.
  lHit := FRoot.HitTest(AX, AY);
  if (lHit = FSequences[i].Pressed) and (lHit <> nil) then
  begin
    lEvent := MakeEvent(lHit, AX, AY, isMouse, wgMouseSequence, AButton, ATime);
    lEvent.Handled := False;
    Dispatch(lHit, lEvent, wgEvClick);
  end;

  DropSeq(wgMouseSequence);
  // Hover may have changed while captured.
  MouseMove(AX, AY, ATime);
end;

procedure TwgInputRouter.MouseLeaveSurface;
var
  lEvent: TwgPointerEvent;
  i: Integer;
begin
  for i := High(FHoverChain) downto 0 do
    if FHoverChain[i] <> nil then
    begin
      FHoverChain[i].SetState(wsHovered, False);
      lEvent := MakeEvent(FHoverChain[i], 0, 0, isMouse, wgMouseSequence, 0, 0);
      Dispatch(FHoverChain[i], lEvent, wgEvLeave);
    end;
  SetLength(FHoverChain, 0);
end;

procedure TwgInputRouter.MouseScroll(AX, AY: Integer; ADX, ADY: Single;
  ATime: LongWord);
var
  lHit: TwgWidget;
  lEvent: TwgScrollEvent;
  p: TPoint;
begin
  if FRoot = nil then
    Exit;
  lHit := FRoot.HitTest(AX, AY);
  if lHit = nil then
    Exit;
  lEvent := Default(TwgScrollEvent);
  p := lHit.RootToLocal(AX, AY);
  lEvent.X := p.X;
  lEvent.Y := p.Y;
  lEvent.DX := ADX;
  lEvent.DY := ADY;
  lEvent.Source := isMouse;
  lEvent.Modifiers := FModifiers;
  lEvent.Time := ATime;
  DispatchScroll(lHit, lEvent);
end;

{ --- touch --- }

procedure TwgInputRouter.TouchDown(AId: Integer; AX, AY: Integer; ATime: LongWord);
var
  i: Integer;
  lHit: TwgWidget;
  lEvent: TwgPointerEvent;
  lSeq: TwgSequenceId;
  lIntf: IwgInputTarget;
begin
  if FRoot = nil then
    Exit;
  lHit := FRoot.HitTest(AX, AY);
  if lHit = nil then
    Exit;
  lSeq := wgFirstTouchSequence + AId;

  i := Seq(lSeq, isTouch);
  FSequences[i].Capture := lHit;
  FSequences[i].Pressed := lHit;
  FSequences[i].LastX := AX;
  FSequences[i].LastY := AY;

  // Pressed, but deliberately NOT hovered: a finger has no hover, and faking
  // it leaves controls lit up after the tap.
  lHit.SetState(wsPressed, True);
  if Target(lHit, lIntf) and lIntf.CanFocus then
    SetFocus(lHit);

  lEvent := MakeEvent(lHit, AX, AY, isTouch, lSeq, 0, ATime);
  Dispatch(lHit, lEvent, wgEvDown);
end;

procedure TwgInputRouter.TouchMove(AId: Integer; AX, AY: Integer; ATime: LongWord);
var
  i: Integer;
  lEvent: TwgPointerEvent;
  lSeq: TwgSequenceId;
begin
  lSeq := wgFirstTouchSequence + AId;
  i := IndexOfSeq(lSeq);
  if (i < 0) or (FSequences[i].Capture = nil) then
    Exit;
  FSequences[i].LastX := AX;
  FSequences[i].LastY := AY;
  lEvent := MakeEvent(FSequences[i].Capture, AX, AY, isTouch, lSeq, 0, ATime);
  Dispatch(FSequences[i].Capture, lEvent, wgEvMove);
end;

procedure TwgInputRouter.TouchUp(AId: Integer; ATime: LongWord);
var
  i: Integer;
  lCapture, lHit: TwgWidget;
  lEvent: TwgPointerEvent;
  lSeq: TwgSequenceId;
  lX, lY: Integer;
begin
  lSeq := wgFirstTouchSequence + AId;
  i := IndexOfSeq(lSeq);
  if i < 0 then
    Exit;
  lCapture := FSequences[i].Capture;
  // wl_touch.up carries no coordinates, so the last motion is where it ended.
  lX := FSequences[i].LastX;
  lY := FSequences[i].LastY;
  if lCapture <> nil then
  begin
    lCapture.SetState(wsPressed, False);
    lEvent := MakeEvent(lCapture, lX, lY, isTouch, lSeq, 0, ATime);
    Dispatch(lCapture, lEvent, wgEvUp);

    if FRoot <> nil then
    begin
      lHit := FRoot.HitTest(lX, lY);
      if (lHit <> nil) and (lHit = FSequences[i].Pressed) then
      begin
        lEvent := MakeEvent(lHit, lX, lY, isTouch, lSeq, 0, ATime);
        lEvent.Handled := False;
        Dispatch(lHit, lEvent, wgEvClick);
      end;
    end;
  end;
  DropSeq(lSeq);
end;

procedure TwgInputRouter.TouchCancel;
var
  i: Integer;
  lEvent: TwgPointerEvent;
begin
  // Every contact is void — not a tap, not a release. Tell each holder to
  // unwind rather than act.
  for i := 0 to High(FSequences) do
    if FSequences[i].Active and (FSequences[i].Source = isTouch) then
    begin
      if FSequences[i].Capture <> nil then
      begin
        FSequences[i].Capture.SetState(wsPressed, False);
        lEvent := MakeEvent(FSequences[i].Capture, FSequences[i].LastX,
          FSequences[i].LastY, isTouch, FSequences[i].Id, 0, 0);
        Dispatch(FSequences[i].Capture, lEvent, wgEvCancel);
      end;
      FSequences[i] := Default(TSequence);
    end;
end;

procedure TwgInputRouter.CancelSequence(AId: TwgSequenceId);
var
  i: Integer;
  lEvent: TwgPointerEvent;
begin
  i := IndexOfSeq(AId);
  if i < 0 then
    Exit;
  if FSequences[i].Capture <> nil then
  begin
    FSequences[i].Capture.SetState(wsPressed, False);
    lEvent := MakeEvent(FSequences[i].Capture, FSequences[i].LastX,
      FSequences[i].LastY, FSequences[i].Source, AId, 0, 0);
    Dispatch(FSequences[i].Capture, lEvent, wgEvCancel);
  end;
  FSequences[i] := Default(TSequence);
end;

{ --- keyboard --- }

procedure TwgInputRouter.SetModifiers(AMods: TwgModifiers);
begin
  FModifiers := AMods;
end;

procedure TwgInputRouter.KeyDown(AKeySym, AScanCode: LongWord;
  const AText: String; ARepeated: Boolean; ATime: LongWord);
var
  w: TwgWidget;
  lIntf: IwgInputTarget;
  lEvent: TwgKeyEvent;
begin
  lEvent := Default(TwgKeyEvent);
  lEvent.KeySym := AKeySym;
  lEvent.ScanCode := AScanCode;
  lEvent.Text := AText;
  lEvent.Modifiers := FModifiers;
  lEvent.Repeated := ARepeated;
  lEvent.Time := ATime;

  w := FFocused;
  while w <> nil do
  begin
    if Target(w, lIntf) then
    begin
      lIntf.KeyDown(lEvent);
      if lEvent.Handled then
        Exit;
    end;
    w := w.Parent;
  end;

  // Nobody wanted it: Tab moves focus. Done last so a text field can consume
  // Tab for itself.
  if AKeySym = wgKeyTab then
    FocusNext(mdShift in FModifiers);
end;

procedure TwgInputRouter.KeyUp(AKeySym, AScanCode: LongWord; ATime: LongWord);
var
  w: TwgWidget;
  lIntf: IwgInputTarget;
  lEvent: TwgKeyEvent;
begin
  lEvent := Default(TwgKeyEvent);
  lEvent.KeySym := AKeySym;
  lEvent.ScanCode := AScanCode;
  lEvent.Modifiers := FModifiers;
  lEvent.Time := ATime;
  w := FFocused;
  while w <> nil do
  begin
    if Target(w, lIntf) then
    begin
      lIntf.KeyUp(lEvent);
      if lEvent.Handled then
        Exit;
    end;
    w := w.Parent;
  end;
end;

{ --- focus --- }

procedure TwgInputRouter.SetFocus(AWidget: TwgWidget);
var
  lIntf: IwgInputTarget;
  lOld: TwgWidget;
begin
  if AWidget = FFocused then
    Exit;
  lOld := FFocused;
  FFocused := AWidget;   // set first, so a handler sees the new state
  if lOld <> nil then
  begin
    lOld.SetState(wsFocused, False);
    if Target(lOld, lIntf) then
      lIntf.FocusOut;
  end;
  if AWidget <> nil then
  begin
    AWidget.SetState(wsFocused, True);
    if Target(AWidget, lIntf) then
      lIntf.FocusIn;
  end;
end;

function TwgInputRouter.FocusNext(ABackwards: Boolean): Boolean;
var
  lOrder: array of TwgWidget;
  lCount, i, lStart: Integer;

  procedure Collect(AWidget: TwgWidget);
  var
    j: Integer;
    lIntf: IwgInputTarget;
  begin
    if (AWidget = nil) or (not AWidget.Visible) or (not AWidget.Enabled) then
      Exit;
    if AWidget.GetInterface(IwgInputTarget, lIntf) and lIntf.CanFocus then
    begin
      if lCount = Length(lOrder) then
        SetLength(lOrder, lCount * 2 + 8);
      lOrder[lCount] := AWidget;
      Inc(lCount);
    end;
    for j := 0 to AWidget.ChildCount - 1 do
      Collect(AWidget.Children[j]);
  end;

begin
  Result := False;
  if FRoot = nil then
    Exit;
  lCount := 0;
  Collect(FRoot);
  if lCount = 0 then
    Exit;

  lStart := -1;
  for i := 0 to lCount - 1 do
    if lOrder[i] = FFocused then
    begin
      lStart := i;
      Break;
    end;

  if ABackwards then
  begin
    if lStart <= 0 then
      i := lCount - 1
    else
      i := lStart - 1;
  end
  else
  begin
    if (lStart < 0) or (lStart >= lCount - 1) then
      i := 0
    else
      i := lStart + 1;
  end;
  SetFocus(lOrder[i]);
  Result := True;
end;

procedure TwgInputRouter.WidgetDestroyed(AWidget: TwgWidget);
var
  i: Integer;
begin
  // Any surviving reference here would be dangling.
  for i := 0 to High(FSequences) do
  begin
    if FSequences[i].Capture = AWidget then
      FSequences[i].Capture := nil;
    if FSequences[i].Pressed = AWidget then
      FSequences[i].Pressed := nil;
  end;
  for i := 0 to High(FHoverChain) do
    if FHoverChain[i] = AWidget then
      FHoverChain[i] := nil;
  if FFocused = AWidget then
    FFocused := nil;
end;

end.
