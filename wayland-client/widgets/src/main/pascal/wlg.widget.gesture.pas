// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.widget.gesture — recognisers that can take a sequence away from a widget.

  A recogniser is attached to a widget and watches the raw pointer stream for
  any sequence that starts on it or on one of its descendants, BEFORE ordinary
  routing gets to act on it. While it is still deciding it stays grPossible and
  the widget underneath behaves normally. The moment it decides, it returns
  grRecognised and CLAIMS the sequence: the router cancels whoever held the
  capture and hands every further event to the recogniser instead.

  That handshake is the whole reason this exists. A scrolling list full of
  buttons cannot work without it — the press lands on a button, which is right,
  and only once the finger has moved far enough does it become a scroll, at
  which point the button must be told to unwind rather than fire. PointerCancel
  is that telling, and it is why the interface distinguishes it from PointerUp.

  A recogniser must be conservative while undecided: claiming too eagerly makes
  the widgets inside unclickable, and claiming too late makes scrolling feel
  stuck. The threshold below is the usual answer — a few pixels of travel, with
  direction taken into account. }
unit wlg.widget.gesture;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Types, Math,
  wlg.widget.types, wlg.widget.core;

type
  TwgGestureRecogniser = class;

  TwgGestureNotify = procedure(Sender: TwgGestureRecogniser;
    const AEvent: TwgGestureEvent) of object;

  { Which part of the stream a Feed call represents. }
  TwgGesturePhase = (gpDown, gpMove, gpUp, gpCancel);

  { TwgGestureRecogniser }

  TwgGestureRecogniser = class
  private
    FHost: TwgWidget;
    FState: TwgGestureState;
    FOnGesture: TwgGestureNotify;
  protected
    FStartX, FStartY: Integer;      // where the sequence began, root coords
    FLastX, FLastY: Integer;
    FStartTime, FLastTime: LongWord;
    FSequence: TwgSequenceId;
    procedure Emit(AKind: TwgGestureKind; AState: TwgGestureState;
      ADX, ADY, AVX, AVY: Single);
    procedure Reset; virtual;
  public
    constructor Create(AHost: TwgWidget);
    // Watch one event. Returning grRecognised claims the sequence; the router
    // then cancels the current capture holder and routes here instead.
    function Feed(const AEvent: TwgPointerEvent; APhase: TwgGesturePhase):
      TwgGestureState; virtual; abstract;

    property Host: TwgWidget read FHost;
    property State: TwgGestureState read FState;
    property Sequence: TwgSequenceId read FSequence;
    property OnGesture: TwgGestureNotify read FOnGesture write FOnGesture;
  end;

  TwgPanAxis = (paBoth, paHorizontal, paVertical);

  { TwgPanRecogniser — drag to scroll, with a flick velocity at the end.

    Claims once the travel passes Threshold along an axis it cares about. A pan
    constrained to one axis deliberately does NOT claim on movement across it,
    so a vertical list still lets a horizontal drag inside it through. }

  TwgPanRecogniser = class(TwgGestureRecogniser)
  private
    FThreshold: Integer;
    FAxis: TwgPanAxis;
    // Velocity is smoothed: a flick's last sample is often near zero because
    // the finger decelerates on lift, so the raw final delta is a bad estimate.
    FVX, FVY: Single;
  protected
    procedure Reset; override;
  public
    constructor Create(AHost: TwgWidget; AAxis: TwgPanAxis = paVertical);
    function Feed(const AEvent: TwgPointerEvent; APhase: TwgGesturePhase):
      TwgGestureState; override;
    property Threshold: Integer read FThreshold write FThreshold;
    property Axis: TwgPanAxis read FAxis write FAxis;
    property VelocityX: Single read FVX;
    property VelocityY: Single read FVY;
  end;

  { TwgLongPressRecogniser — claims after the pointer has been held still.

    Needs a clock the pointer stream does not provide, so Poll must be called
    from the frame loop; a press that never moves generates no events at all,
    and waiting for one would mean the gesture never fires. }

  TwgLongPressRecogniser = class(TwgGestureRecogniser)
  private
    FDelayMs: LongWord;
    FMoveTolerance: Integer;
    FArmed: Boolean;
    FFired: Boolean;
  protected
    procedure Reset; override;
  public
    constructor Create(AHost: TwgWidget);
    function Feed(const AEvent: TwgPointerEvent; APhase: TwgGesturePhase):
      TwgGestureState; override;
    // Call each frame with the current time. Returns True the moment the press
    // has been held long enough, at which point the router should claim.
    function Poll(ANowMs: LongWord): Boolean;
    property DelayMs: LongWord read FDelayMs write FDelayMs;
    property MoveTolerance: Integer read FMoveTolerance write FMoveTolerance;
  end;

implementation

{ TwgGestureRecogniser }

constructor TwgGestureRecogniser.Create(AHost: TwgWidget);
begin
  inherited Create;
  FHost := AHost;
  FState := grPossible;
end;

procedure TwgGestureRecogniser.Reset;
begin
  FState := grPossible;
  FSequence := 0;
end;

procedure TwgGestureRecogniser.Emit(AKind: TwgGestureKind;
  AState: TwgGestureState; ADX, ADY, AVX, AVY: Single);
var
  lEvent: TwgGestureEvent;
  p: TPoint;
begin
  if not Assigned(FOnGesture) then
    Exit;
  lEvent := Default(TwgGestureEvent);
  lEvent.Kind := AKind;
  lEvent.State := AState;
  if FHost <> nil then
  begin
    p := FHost.RootToLocal(FLastX, FLastY);
    lEvent.X := p.X;
    lEvent.Y := p.Y;
  end;
  lEvent.DX := ADX;
  lEvent.DY := ADY;
  lEvent.VX := AVX;
  lEvent.VY := AVY;
  lEvent.Scale := 1;
  lEvent.FingerCount := 1;
  lEvent.Time := FLastTime;
  FOnGesture(Self, lEvent);
end;

{ TwgPanRecogniser }

constructor TwgPanRecogniser.Create(AHost: TwgWidget; AAxis: TwgPanAxis);
begin
  inherited Create(AHost);
  FAxis := AAxis;
  // Small enough that scrolling feels immediate, large enough that a click
  // with a shaky hand still reaches the button underneath.
  FThreshold := 8;
end;

procedure TwgPanRecogniser.Reset;
begin
  inherited Reset;
  FVX := 0;
  FVY := 0;
end;

function TwgPanRecogniser.Feed(const AEvent: TwgPointerEvent;
  APhase: TwgGesturePhase): TwgGestureState;
var
  lDX, lDY, lTravel: Integer;
  lDT: LongWord;
  lInstVX, lInstVY, lAlpha: Single;
  p: TPoint;
begin
  // Events arrive in the HOST's coordinates; convert to root so a pan is
  // measured against a fixed frame even as the host scrolls under it.
  p := FHost.LocalToRoot(AEvent.X, AEvent.Y);

  case APhase of
    gpDown:
      begin
        Reset;
        FSequence := AEvent.Sequence;
        FStartX := p.X; FStartY := p.Y;
        FLastX := p.X;  FLastY := p.Y;
        FStartTime := AEvent.Time;
        FLastTime := AEvent.Time;
        FState := grPossible;
      end;

    gpMove:
      begin
        lDX := p.X - FLastX;
        lDY := p.Y - FLastY;
        lDT := AEvent.Time - FLastTime;

        if lDT > 0 then
        begin
          lInstVX := lDX * 1000.0 / lDT;
          lInstVY := lDY * 1000.0 / lDT;
          // Exponential smoothing: the last sample before a lift is usually a
          // decelerating one, so a raw reading throws flicks away.
          lAlpha := 0.35;
          FVX := FVX * (1 - lAlpha) + lInstVX * lAlpha;
          FVY := FVY * (1 - lAlpha) + lInstVY * lAlpha;
        end;

        FLastX := p.X;
        FLastY := p.Y;
        FLastTime := AEvent.Time;

        if FState = grPossible then
        begin
          case FAxis of
            paHorizontal: lTravel := Abs(p.X - FStartX);
            paVertical:   lTravel := Abs(p.Y - FStartY);
            else          lTravel := Max(Abs(p.X - FStartX), Abs(p.Y - FStartY));
          end;
          if lTravel >= FThreshold then
          begin
            FState := grRecognised;
            // Report the whole travel since the press, not just this step, or
            // the content lags the finger by the threshold distance forever.
            Emit(gkPan, grRecognised, p.X - FStartX, p.Y - FStartY, FVX, FVY);
          end;
        end
        else if FState in [grRecognised, grChanged] then
        begin
          FState := grChanged;
          Emit(gkPan, grChanged, lDX, lDY, FVX, FVY);
        end;
      end;

    gpUp:
      begin
        if FState in [grRecognised, grChanged] then
        begin
          FState := grEnded;
          // The velocity here is what a kinetic scroller coasts on.
          Emit(gkPan, grEnded, 0, 0, FVX, FVY);
        end
        else
          FState := grFailed;   // never travelled far enough; it was a tap
      end;

    gpCancel:
      begin
        if FState in [grRecognised, grChanged] then
          Emit(gkPan, grFailed, 0, 0, 0, 0);
        FState := grFailed;
      end;
  end;
  Result := FState;
end;

{ TwgLongPressRecogniser }

constructor TwgLongPressRecogniser.Create(AHost: TwgWidget);
begin
  inherited Create(AHost);
  FDelayMs := 500;
  FMoveTolerance := 10;
end;

procedure TwgLongPressRecogniser.Reset;
begin
  inherited Reset;
  FArmed := False;
  FFired := False;
end;

function TwgLongPressRecogniser.Feed(const AEvent: TwgPointerEvent;
  APhase: TwgGesturePhase): TwgGestureState;
var
  p: TPoint;
begin
  p := FHost.LocalToRoot(AEvent.X, AEvent.Y);
  case APhase of
    gpDown:
      begin
        Reset;
        FSequence := AEvent.Sequence;
        FStartX := p.X; FStartY := p.Y;
        FLastX := p.X;  FLastY := p.Y;
        FStartTime := AEvent.Time;
        FLastTime := AEvent.Time;
        FArmed := True;
        FState := grPossible;
      end;
    gpMove:
      begin
        FLastX := p.X;
        FLastY := p.Y;
        FLastTime := AEvent.Time;
        // Wandering means it is a drag, not a hold.
        if FArmed and (not FFired) and
           ((Abs(p.X - FStartX) > FMoveTolerance) or
            (Abs(p.Y - FStartY) > FMoveTolerance)) then
        begin
          FArmed := False;
          FState := grFailed;
        end;
      end;
    gpUp:
      begin
        if FFired then
          FState := grEnded
        else
          FState := grFailed;   // released before the delay: an ordinary click
        FArmed := False;
      end;
    gpCancel:
      begin
        FArmed := False;
        FState := grFailed;
      end;
  end;
  Result := FState;
end;

function TwgLongPressRecogniser.Poll(ANowMs: LongWord): Boolean;
begin
  Result := False;
  if (not FArmed) or FFired then
    Exit;
  if ANowMs - FStartTime < FDelayMs then
    Exit;
  FFired := True;
  FState := grRecognised;
  Emit(gkLongPress, grRecognised, 0, 0, 0, 0);
  Result := True;
end;

end.
