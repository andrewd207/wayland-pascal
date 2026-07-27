// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.widget.scroll — a scrolling viewport.

  TwgScrollBox holds exactly one child, the CONTENT, gives it as much room as
  it asks for, and shows a window onto it. Scrolling moves the content's
  position rather than transforming the canvas, so hit testing, damage and
  clipping all keep working with no special cases — a scrolled button is
  genuinely at the coordinates the router thinks it is.

  It is the control that justifies the gesture machinery. Drag-to-scroll cannot
  be done with ordinary input handling when the content contains buttons: the
  press legitimately lands on a button, and only once the finger has travelled
  does it become a scroll. So the box installs a pan recogniser, which claims
  the sequence at that point and the router cancels the button — the button was
  pressed, is told to unwind, and does not fire. Without the claim/cancel
  handshake you get one of the two classic bugs: buttons that cannot be clicked,
  or a list that cannot be dragged wherever a button happens to be.

  KINETIC scrolling comes free with the pan recogniser's smoothed velocity: the
  flick continues under friction after release. Step must be called each frame
  for that, which the window's frame loop does. }
unit wlg.widget.scroll;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Types, Math,
  wlg.canvas.base,
  wlg.widget.types, wlg.widget.core, wlg.widget.input, wlg.widget.gesture,
  wlg.widget.theme, wlg.widget.controls;

type
  { TwgScrollBox }

  TwgScrollBox = class(TwgControl)
  private
    FContent: TwgWidget;
    FOffsetX, FOffsetY: Integer;
    FPan: TwgPanRecogniser;
    FAxis: TwgPanAxis;
    // Kinetic state, in logical pixels per second.
    FVX, FVY: Single;
    FCoasting: Boolean;
    FLastStep: QWord;
    FShowBars: Boolean;
    procedure SetOffset(AX, AY: Integer);
    procedure HandlePan(Sender: TwgGestureRecogniser; const AEvent: TwgGestureEvent);
    function  MaxOffsetX: Integer;
    function  MaxOffsetY: Integer;
    procedure DrawBar(ACanvas: TwgCanvas; AVertical: Boolean);
  protected
    procedure Paint(ACanvas: TwgCanvas); override;
    procedure PaintOverlay(ACanvas: TwgCanvas); override;
    procedure BoundsChanged; override;
    function  MeasureSize(AAvailW, AAvailH: Integer): TSize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Install the pan recogniser. Must be called once the box is in a tree
    // whose window has a router; TwgScrollBox cannot reach one on its own.
    procedure AttachTo(ARouter: TwgInputRouter);

    // The single scrollable child. Setting it re-parents.
    procedure SetContent(AWidget: TwgWidget);
    procedure ScrollBy(ADX, ADY: Integer);
    procedure ScrollTo(AX, AY: Integer);
    // Advance kinetic coasting. Call once a frame; harmless when not coasting.
    procedure Step;

    function  CanFocus: Boolean; override;
    procedure Scroll(var AEvent: TwgScrollEvent); override;

    property Content: TwgWidget read FContent;
    property OffsetX: Integer read FOffsetX;
    property OffsetY: Integer read FOffsetY;
    property Axis: TwgPanAxis read FAxis write FAxis;
    property ShowBars: Boolean read FShowBars write FShowBars;
  end;

implementation

const
  // Per-second velocity retention while coasting. Tuned by feel: high enough
  // that a flick travels, low enough that it settles quickly.
  Friction = 0.004;
  // Below this the coast is over; without a floor it creeps forever.
  MinVelocity = 12.0;

{ TwgScrollBox }

constructor TwgScrollBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAxis := paVertical;
  FShowBars := True;
  // The viewport must clip, or the content would paint over its siblings.
  ClipChildren := True;
end;

destructor TwgScrollBox.Destroy;
begin
  FPan.Free;
  inherited Destroy;
end;

procedure TwgScrollBox.AttachTo(ARouter: TwgInputRouter);
begin
  if (ARouter = nil) or (FPan <> nil) then
    Exit;
  FPan := TwgPanRecogniser.Create(Self, FAxis);
  FPan.OnGesture := @HandlePan;
  ARouter.AddRecogniser(FPan);
end;

procedure TwgScrollBox.SetContent(AWidget: TwgWidget);
begin
  FContent := AWidget;
  if FContent <> nil then
    FContent.Parent := Self;
  FOffsetX := 0;
  FOffsetY := 0;
  InvalidateLayout;
end;

function TwgScrollBox.CanFocus: Boolean;
begin
  // Focusable so the wheel and (later) arrow keys have somewhere to land.
  Result := Enabled and Visible;
end;

function TwgScrollBox.MeasureSize(AAvailW, AAvailH: Integer): TSize;
begin
  // A viewport has no natural size — it is whatever its parent gives it. Report
  // something small rather than the content's size, or a box layout would try
  // to make it big enough to need no scrolling at all.
  Result.cx := 64;
  Result.cy := 64;
end;

function TwgScrollBox.MaxOffsetX: Integer;
begin
  if FContent = nil then
    Exit(0);
  Result := Max(0, FContent.Width - Width);
end;

function TwgScrollBox.MaxOffsetY: Integer;
begin
  if FContent = nil then
    Exit(0);
  Result := Max(0, FContent.Height - Height);
end;

procedure TwgScrollBox.BoundsChanged;
var
  lSize: TSize;
begin
  inherited BoundsChanged;
  if FContent = nil then
    Exit;
  // Give the content the width of the viewport but as much HEIGHT as it wants
  // (for a vertical box) — that is what makes it overflow and therefore scroll.
  lSize := FContent.PreferredSize(Width, Height);
  case FAxis of
    paVertical:   FContent.SetBounds(-FOffsetX, -FOffsetY, Width, Max(Height, lSize.cy));
    paHorizontal: FContent.SetBounds(-FOffsetX, -FOffsetY, Max(Width, lSize.cx), Height);
    else          FContent.SetBounds(-FOffsetX, -FOffsetY,
                    Max(Width, lSize.cx), Max(Height, lSize.cy));
  end;
  // A resize can leave us scrolled past the end.
  SetOffset(FOffsetX, FOffsetY);
end;

procedure TwgScrollBox.SetOffset(AX, AY: Integer);
begin
  AX := Max(0, Min(AX, MaxOffsetX));
  AY := Max(0, Min(AY, MaxOffsetY));
  if (AX = FOffsetX) and (AY = FOffsetY) then
    Exit;
  FOffsetX := AX;
  FOffsetY := AY;
  if FContent <> nil then
    // Moving the content is the whole implementation: hit testing, damage and
    // clipping then need no knowledge that scrolling exists.
    FContent.SetBounds(-FOffsetX, -FOffsetY, FContent.Width, FContent.Height);
  Invalidate;
end;

procedure TwgScrollBox.ScrollBy(ADX, ADY: Integer);
begin
  SetOffset(FOffsetX + ADX, FOffsetY + ADY);
end;

procedure TwgScrollBox.ScrollTo(AX, AY: Integer);
begin
  SetOffset(AX, AY);
end;

procedure TwgScrollBox.Scroll(var AEvent: TwgScrollEvent);
begin
  // A wheel notch stops any coast; the user has taken over.
  FCoasting := False;
  ScrollBy(-Round(AEvent.DX), -Round(AEvent.DY));
  AEvent.Handled := True;
end;

procedure TwgScrollBox.HandlePan(Sender: TwgGestureRecogniser;
  const AEvent: TwgGestureEvent);
begin
  case AEvent.State of
    grRecognised:
      begin
        // The claim has just happened and the button underneath (if any) has
        // been cancelled. DX/DY here is the whole travel since the press, so
        // the content catches up with the finger instead of lagging by the
        // recognition threshold.
        FCoasting := False;
        ScrollBy(-Round(AEvent.DX), -Round(AEvent.DY));
      end;
    grChanged:
      ScrollBy(-Round(AEvent.DX), -Round(AEvent.DY));
    grEnded:
      begin
        // Coast on the smoothed velocity, negated because content moves
        // opposite to the finger.
        FVX := -AEvent.VX;
        FVY := -AEvent.VY;
        FCoasting := (Abs(FVX) > MinVelocity) or (Abs(FVY) > MinVelocity);
        FLastStep := GetTickCount64;
      end;
    grFailed:
      FCoasting := False;
    else
      ; // grPossible: still undecided, nothing to scroll yet
  end;
end;

procedure TwgScrollBox.Step;
var
  lNow: QWord;
  lDT: Single;
  lDecay: Single;
begin
  if not FCoasting then
    Exit;
  lNow := GetTickCount64;
  lDT := (lNow - FLastStep) / 1000.0;
  FLastStep := lNow;
  if lDT <= 0 then
    Exit;
  if lDT > 0.1 then
    lDT := 0.1;   // a stalled frame must not teleport the content

  ScrollBy(Round(FVX * lDT), Round(FVY * lDT));

  // Exponential decay, frame-rate independent.
  lDecay := Power(Friction, lDT);
  FVX := FVX * lDecay;
  FVY := FVY * lDecay;

  if (Abs(FVX) < MinVelocity) and (Abs(FVY) < MinVelocity) then
    FCoasting := False
  // Hitting an end stops the coast rather than grinding against it.
  else if ((FVY < 0) and (FOffsetY = 0)) or
          ((FVY > 0) and (FOffsetY = MaxOffsetY)) then
    FCoasting := False;
end;

procedure TwgScrollBox.DrawBar(ACanvas: TwgCanvas; AVertical: Boolean);
var
  lTheme: TwgTheme;
  lTrack, lThumbLen, lThumbPos, lSize, lMax, lView, lContent: Integer;
begin
  lTheme := Theme;
  if (lTheme = nil) or (FContent = nil) then
    Exit;
  lSize := Max(4, lTheme.Metrics.ScrollBarSize div 3);

  if AVertical then
  begin
    lMax := MaxOffsetY;
    if lMax <= 0 then
      Exit;
    lView := Height;
    lContent := FContent.Height;
    lTrack := Height;
    lThumbLen := Max(24, Round(lTrack * (lView / lContent)));
    lThumbPos := Round((lTrack - lThumbLen) * (FOffsetY / lMax));
    ACanvas.FillRoundRect(Width - lSize - 2, lThumbPos, lSize, lThumbLen,
      lSize div 2, lSize div 2, lTheme.Palette.TextDim);
  end
  else
  begin
    lMax := MaxOffsetX;
    if lMax <= 0 then
      Exit;
    lView := Width;
    lContent := FContent.Width;
    lTrack := Width;
    lThumbLen := Max(24, Round(lTrack * (lView / lContent)));
    lThumbPos := Round((lTrack - lThumbLen) * (FOffsetX / lMax));
    ACanvas.FillRoundRect(lThumbPos, Height - lSize - 2, lThumbLen, lSize,
      lSize div 2, lSize div 2, lTheme.Palette.TextDim);
  end;
end;

procedure TwgScrollBox.Paint(ACanvas: TwgCanvas);
var
  lTheme: TwgTheme;
begin
  lTheme := Theme;
  if lTheme = nil then
    Exit;
  // The viewport paints its own background: a partial repaint never clears,
  // and the content does not necessarily cover the whole of it.
  ACanvas.FillRect(0, 0, Width, Height, lTheme.Palette.SurfaceAlt);
end;

procedure TwgScrollBox.PaintOverlay(ACanvas: TwgCanvas);
begin
  // The bars go in the overlay pass, after the content: content is normally
  // opaque, so a bar drawn with the background would simply be buried.
  if not FShowBars then
    Exit;
  if FAxis in [paVertical, paBoth] then
    DrawBar(ACanvas, True);
  if FAxis in [paHorizontal, paBoth] then
    DrawBar(ACanvas, False);
end;

end.
