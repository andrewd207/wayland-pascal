// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.widget.types — the vocabulary shared by the widget layer.

  Event records, layout hints and the enums the core, the input router and the
  controls all need. Kept in one small unit so none of them has to depend on
  another just to name a type.

  The pointer event is deliberately MULTI-POINTER from the start. Touch is a
  first-class target here, and a single-pointer event record is the thing that
  makes touch support a rewrite rather than an addition: every routing path,
  every capture, every hover assumption has to change. So an event carries a
  Source (mouse, touch, pen) and a Sequence — the mouse is one fixed sequence,
  and each finger on a touch screen gets its own for as long as it is down. }
unit wlg.widget.types;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Types;

type
  EwgWidget = class(Exception);

  { --- input --- }

  TwgInputSource = (
    isMouse,      // a real pointer; has hover, has buttons
    isTouch,      // a finger; no hover, no buttons, several at once
    isPen         // stylus; has hover when in proximity, has pressure
  );

  { Identifies one continuous stream of pointer input.

    The mouse is always wgMouseSequence. Each touch point gets the id the
    compositor assigned, offset so it cannot collide with the mouse. Capture is
    keyed on this — see the note in TwgWidget. }
  TwgSequenceId = type Integer;

  TwgModifier = (mdShift, mdCtrl, mdAlt, mdSuper, mdCapsLock, mdNumLock);
  TwgModifiers = set of TwgModifier;

  TwgPointerEvent = record
    X, Y: Integer;             // widget-local, in logical pixels
    Source: TwgInputSource;
    Sequence: TwgSequenceId;
    Button: LongWord;          // BTN_LEFT etc; meaningless for touch
    Modifiers: TwgModifiers;
    Time: LongWord;
    // Set by a handler to stop the event bubbling to ancestors.
    Handled: Boolean;
  end;

  TwgScrollEvent = record
    X, Y: Integer;
    DX, DY: Single;            // logical pixels; positive DY scrolls content up
    Source: TwgInputSource;
    Modifiers: TwgModifiers;
    Time: LongWord;
    Handled: Boolean;
  end;

  TwgKeyEvent = record
    KeySym: LongWord;          // xkb keysym
    ScanCode: LongWord;        // raw evdev code
    Text: String;              // UTF-8 for a printable key, else empty
    Modifiers: TwgModifiers;
    Repeated: Boolean;
    Time: LongWord;
    Handled: Boolean;
  end;

  { --- gestures --- }

  TwgGestureKind = (
    gkTap, gkDoubleTap, gkLongPress,
    gkPan, gkPinch, gkRotate, gkSwipe
  );

  { A recogniser moves through these. The claim in grRecognised is the
    important transition: it cancels the ordinary press/click handling of
    whichever widget was about to act, which is exactly how a scrolling list
    steals a drag that began as a press on a button inside it. Without that
    handshake, scrollable containers holding buttons cannot work. }
  TwgGestureState = (
    grPossible,     // still watching
    grRecognised,   // claims the sequence; others get a cancel
    grChanged,      // ongoing (pan/pinch updates)
    grEnded,
    grFailed        // not this gesture; stop watching
  );

  TwgGestureEvent = record
    Kind: TwgGestureKind;
    State: TwgGestureState;
    X, Y: Integer;             // widget-local focal point
    DX, DY: Single;            // pan delta since the last event
    VX, VY: Single;            // velocity, logical px/s — for kinetic scrolling
    Scale: Single;             // pinch, 1.0 = unchanged
    Rotation: Single;          // radians, clockwise
    FingerCount: Integer;
    Time: LongWord;
    Handled: Boolean;
  end;

  { --- widget state --- }

  TwgWidgetState = (
    wsNormal, wsHovered, wsPressed, wsDisabled, wsFocused
  );
  TwgWidgetStates = set of TwgWidgetState;

  { --- layout --- }

  TwgAlign = (alNone, alLeft, alTop, alRight, alBottom, alClient);
  TwgAnchor = (akLeft, akTop, akRight, akBottom);
  TwgAnchors = set of TwgAnchor;

  TwgMargin = record
    Left, Top, Right, Bottom: Integer;
  end;

  { Per-child layout hints. They live on the child because that is where a
    caller expects to set them, even though the parent's layout reads them. }
  TwgLayoutHints = record
    Margin: TwgMargin;
    Align: TwgAlign;
    Anchors: TwgAnchors;
    // Share of leftover space in a box layout; 0 means "natural size only".
    Weight: Single;
    // Clamps applied after the layout has had its say. 0 = unconstrained.
    MinWidth, MinHeight: Integer;
    MaxWidth, MaxHeight: Integer;
  end;

  TwgSizeConstraint = record
    Min, Preferred, Max: Integer;
  end;

const
  { Common xkb keysyms, so the widget layer does not have to depend on the xkb
    binding just to recognise Tab or Escape. Values are from keysymdef.h. }
  wgKeyBackSpace = $FF08;
  wgKeyTab       = $FF09;
  wgKeyReturn    = $FF0D;
  wgKeyEscape    = $FF1B;
  wgKeyHome      = $FF50;
  wgKeyLeft      = $FF51;
  wgKeyUp        = $FF52;
  wgKeyRight     = $FF53;
  wgKeyDown      = $FF54;
  wgKeyPageUp    = $FF55;
  wgKeyPageDown  = $FF56;
  wgKeyEnd       = $FF57;
  wgKeyInsert    = $FF63;
  wgKeyDelete    = $FFFF;
  wgKeySpace     = $0020;

  wgMouseSequence: TwgSequenceId = 0;
  // Touch ids start above the mouse so the two can never collide.
  wgFirstTouchSequence: TwgSequenceId = 1;

  wgDefaultAnchors: TwgAnchors = [akLeft, akTop];

function wgMargin(AAll: Integer): TwgMargin; overload;
function wgMargin(ALeft, ATop, ARight, ABottom: Integer): TwgMargin; overload;
function wgDefaultHints: TwgLayoutHints;

// Union of two rectangles, treating an empty rectangle as "nothing" rather
// than as a degenerate rectangle at the origin — which is what makes damage
// accumulation start cleanly from an empty region.
function wgUnionRect(const A, B: TRect): TRect;
function wgRectEmpty(const R: TRect): Boolean; inline;
function wgIntersectRect(const A, B: TRect): TRect;
function wgRectContains(const R: TRect; X, Y: Integer): Boolean; inline;
function wgOffsetRect(const R: TRect; DX, DY: Integer): TRect; inline;

implementation

function wgMargin(AAll: Integer): TwgMargin;
begin
  Result.Left := AAll;
  Result.Top := AAll;
  Result.Right := AAll;
  Result.Bottom := AAll;
end;

function wgMargin(ALeft, ATop, ARight, ABottom: Integer): TwgMargin;
begin
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Right := ARight;
  Result.Bottom := ABottom;
end;

function wgDefaultHints: TwgLayoutHints;
begin
  Result := Default(TwgLayoutHints);
  Result.Anchors := [akLeft, akTop];
  Result.Align := alNone;
  Result.Weight := 0;
end;

function wgRectEmpty(const R: TRect): Boolean;
begin
  Result := (R.Right <= R.Left) or (R.Bottom <= R.Top);
end;

function wgUnionRect(const A, B: TRect): TRect;
begin
  if wgRectEmpty(A) then
    Exit(B);
  if wgRectEmpty(B) then
    Exit(A);
  Result.Left := A.Left;
  if B.Left < Result.Left then Result.Left := B.Left;
  Result.Top := A.Top;
  if B.Top < Result.Top then Result.Top := B.Top;
  Result.Right := A.Right;
  if B.Right > Result.Right then Result.Right := B.Right;
  Result.Bottom := A.Bottom;
  if B.Bottom > Result.Bottom then Result.Bottom := B.Bottom;
end;

function wgIntersectRect(const A, B: TRect): TRect;
begin
  Result.Left := A.Left;
  if B.Left > Result.Left then Result.Left := B.Left;
  Result.Top := A.Top;
  if B.Top > Result.Top then Result.Top := B.Top;
  Result.Right := A.Right;
  if B.Right < Result.Right then Result.Right := B.Right;
  Result.Bottom := A.Bottom;
  if B.Bottom < Result.Bottom then Result.Bottom := B.Bottom;
  if Result.Right < Result.Left then Result.Right := Result.Left;
  if Result.Bottom < Result.Top then Result.Bottom := Result.Top;
end;

function wgRectContains(const R: TRect; X, Y: Integer): Boolean;
begin
  Result := (X >= R.Left) and (X < R.Right) and (Y >= R.Top) and (Y < R.Bottom);
end;

function wgOffsetRect(const R: TRect; DX, DY: Integer): TRect;
begin
  Result.Left := R.Left + DX;
  Result.Top := R.Top + DY;
  Result.Right := R.Right + DX;
  Result.Bottom := R.Bottom + DY;
end;

end.
