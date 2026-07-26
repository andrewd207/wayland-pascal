// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.widget.core — TwgWidget, the retained widget tree.

  A widget owns a rectangle in its parent's coordinates, paints itself in its
  own local coordinates, and holds children. It knows nothing about Wayland,
  nothing about buffers, and nothing about which canvas backend is in use — it
  is handed a TwgCanvas and draws. That is what lets the same tree run on the
  GPU or the CPU, and lets the whole thing be tested headlessly.

  COORDINATES are integer LOGICAL pixels. Integer because widgets want to land
  on pixel boundaries and float bounds invite seams between adjacent controls.
  Logical because HiDPI is handled once, by the host applying a scale to the
  canvas before painting: the canvas is resolution-independent, so a 2x display
  costs nothing here and no widget contains a scale factor. Device pixels must
  not leak into widget code.

  PAINTING is driven by the core, not by widgets: Paint draws only the widget
  itself, and PaintTree handles the transform, the clip and the recursion. So
  Paint always starts at local (0,0) with the clip already correct.

  DAMAGE. Widgets call Invalidate; the request travels up the parent chain to
  the root and out through IwgWidgetHost to whatever owns the surface. The host
  is an interface precisely so this unit does not depend on the window layer —
  a headless test can implement it in ten lines.

  LIFETIME. TwgWidget descends from TComponent for owner-based destruction and
  to leave room for streaming later. Note carefully that TComponent.Owner is
  NOT TwgWidget.Parent: Owner decides who frees you, Parent decides where you
  appear. They are usually the same object but need not be, and conflating them
  is a reliable way to produce double-frees. Setting Parent adds to the parent's
  child list and removes from any previous one; it does not change ownership. }
unit wlg.widget.core;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Types, Math,
  wlg.surface, wlg.canvas.base, wlg.widget.types;

type
  TwgWidget = class;

  { IwgWidgetHost — whatever owns the surface a widget tree paints into.

    Implemented by TwgWindow in the window unit, and trivially by tests. }
  IwgWidgetHost = interface
    ['{5B1D8C40-72E3-4A96-BF08-3C6A91D25E74}']
    // A region of the root, in ROOT coordinates, needs repainting.
    procedure WidgetInvalidated(const ARect: TRect);
    // Something changed that requires layout before the next paint.
    procedure WidgetLayoutInvalidated;
    // Default font for widgets that have not been given one.
    function  HostFont: IwgGlyphSource;
  end;

  TwgWidgetList = array of TwgWidget;

  { TwgWidget }

  TwgWidget = class(TComponent)
  private
    FParent: TwgWidget;
    FChildren: TwgWidgetList;
    FChildCount: Integer;
    FHost: IwgWidgetHost;

    FLeft, FTop, FWidth, FHeight: Integer;
    FVisible: Boolean;
    FEnabled: Boolean;
    FClipChildren: Boolean;
    FHints: TwgLayoutHints;
    FStates: TwgWidgetStates;
    FFont: IwgGlyphSource;

    procedure AddChild(AChild: TwgWidget);
    procedure RemoveChild(AChild: TwgWidget);
    function  GetChild(AIndex: Integer): TwgWidget;
    procedure SetParent(AValue: TwgWidget);
    procedure SetVisible(AValue: Boolean);
    procedure SetEnabled(AValue: Boolean);
    function  GetHost: IwgWidgetHost;
  protected
    // Draw ONLY this widget, in local coordinates with (0,0) at its top-left.
    // Children are painted by the core afterwards; never paint them here.
    procedure Paint(ACanvas: TwgCanvas); virtual;
    // Called after the bounds change; override to re-lay-out children.
    procedure BoundsChanged; virtual;
    // Natural size when unconstrained. Containers override to consult a layout.
    function  MeasureSize(AAvailW, AAvailH: Integer): TSize; virtual;

    property Host: IwgWidgetHost read GetHost;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { --- tree --- }
    property Parent: TwgWidget read FParent write SetParent;
    property Children[AIndex: Integer]: TwgWidget read GetChild;
    property ChildCount: Integer read FChildCount;
    function Root: TwgWidget;
    // Only the root has one directly; children resolve through their parent.
    procedure SetHost(const AHost: IwgWidgetHost);

    { --- geometry --- }
    procedure SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
    function  BoundsRect: TRect;
    // The widget's own drawable area, at the origin: (0, 0, Width, Height).
    function  ClientRect: TRect;
    // Map a local point/rect into root coordinates.
    function  LocalToRoot(X, Y: Integer): TPoint;
    function  LocalRectToRoot(const R: TRect): TRect;
    function  RootToLocal(X, Y: Integer): TPoint;

    { --- painting --- }
    // Paint this widget and its subtree. AClipRoot bounds the work, in ROOT
    // coordinates; subtrees that cannot intersect it are skipped entirely.
    procedure PaintTree(ACanvas: TwgCanvas; const AClipRoot: TRect);
    procedure Invalidate;
    procedure InvalidateRect(const ARect: TRect);   // local coordinates
    procedure InvalidateLayout;

    { --- hit testing --- }
    // Deepest visible, enabled descendant containing the LOCAL point, or nil.
    // Later siblings win, matching paint order (they are drawn on top).
    function  HitTest(X, Y: Integer): TwgWidget; virtual;
    // Whether this widget accepts the point at all; override for non-rectangular
    // or click-through widgets.
    function  ContainsPoint(X, Y: Integer): Boolean; virtual;

    { --- state --- }
    property States: TwgWidgetStates read FStates;
    procedure SetState(AState: TwgWidgetState; AOn: Boolean);

    property Left: Integer read FLeft;
    property Top: Integer read FTop;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property Visible: Boolean read FVisible write SetVisible;
    property Enabled: Boolean read FEnabled write SetEnabled;
    property ClipChildren: Boolean read FClipChildren write FClipChildren;
    property LayoutHints: TwgLayoutHints read FHints write FHints;
    // Falls back to the host's font when unset.
    property Font: IwgGlyphSource read FFont write FFont;
    function EffectiveFont: IwgGlyphSource;
  end;

  { TwgDamage — accumulated repaint regions, one per buffer.

    Why per buffer and not per frame: a surface is multiply buffered, so the
    buffer about to be painted is not the one painted last frame — it is N
    frames stale. Repainting only the region that changed THIS frame would
    leave that buffer's older damage unrepaired, which shows up as stale
    rectangles flickering back whenever buffers alternate.

    So an invalidation is added to EVERY buffer's region, and painting buffer i
    consumes and clears only that buffer's. One union rectangle per buffer for
    now; a coalescing rect list is a drop-in improvement later that does not
    change this interface. }
  TwgDamage = class
  private
    FRegions: array of TRect;
    function GetRegion(AIndex: Integer): TRect;
  public
    constructor Create(ABufferCount: Integer);
    procedure SetBufferCount(ACount: Integer);
    // Record a newly dirty rectangle against every buffer.
    procedure Add(const ARect: TRect);
    // Mark everything dirty — after a resize, or for the first frame.
    procedure AddAll(AWidth, AHeight: Integer);
    // The region buffer AIndex must repaint; clears it.
    function  Take(AIndex: Integer): TRect;
    function  IsDirty(AIndex: Integer): Boolean;
    property  Region[AIndex: Integer]: TRect read GetRegion;
    function  BufferCount: Integer;
  end;

implementation

{ TwgWidget }

constructor TwgWidget.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FVisible := True;
  FEnabled := True;
  FClipChildren := True;
  FHints := wgDefaultHints;
end;

destructor TwgWidget.Destroy;
var
  i: Integer;
begin
  // Detach first so the parent cannot paint or hit-test a half-destroyed child.
  if FParent <> nil then
    FParent.RemoveChild(Self);
  // Children owned by this widget are freed by TComponent; children merely
  // parented here are only detached. Owner and Parent are separate on purpose.
  for i := FChildCount - 1 downto 0 do
    FChildren[i].FParent := nil;
  FChildCount := 0;
  SetLength(FChildren, 0);
  FHost := nil;
  FFont := nil;
  inherited Destroy;
end;

procedure TwgWidget.AddChild(AChild: TwgWidget);
begin
  if FChildCount = Length(FChildren) then
    SetLength(FChildren, FChildCount * 2 + 4);
  FChildren[FChildCount] := AChild;
  Inc(FChildCount);
end;

procedure TwgWidget.RemoveChild(AChild: TwgWidget);
var
  i, j: Integer;
begin
  for i := 0 to FChildCount - 1 do
    if FChildren[i] = AChild then
    begin
      for j := i to FChildCount - 2 do
        FChildren[j] := FChildren[j + 1];
      Dec(FChildCount);
      Exit;
    end;
end;

function TwgWidget.GetChild(AIndex: Integer): TwgWidget;
begin
  if (AIndex < 0) or (AIndex >= FChildCount) then
    raise EwgWidget.CreateFmt('child index %d out of range (%d children)',
      [AIndex, FChildCount]);
  Result := FChildren[AIndex];
end;

procedure TwgWidget.SetParent(AValue: TwgWidget);
var
  lWalk: TwgWidget;
begin
  if AValue = FParent then
    Exit;
  if AValue = Self then
    raise EwgWidget.Create('a widget cannot be its own parent');
  // A cycle would make PaintTree and Root recurse forever; catch it here where
  // the mistake is, not later in a stack overflow.
  lWalk := AValue;
  while lWalk <> nil do
  begin
    if lWalk = Self then
      raise EwgWidget.Create('re-parenting would create a cycle');
    lWalk := lWalk.FParent;
  end;

  if FParent <> nil then
  begin
    FParent.InvalidateRect(BoundsRect);   // repaint where we used to be
    FParent.RemoveChild(Self);
  end;
  FParent := AValue;
  if FParent <> nil then
  begin
    FParent.AddChild(Self);
    Invalidate;
    FParent.InvalidateLayout;
  end;
end;

function TwgWidget.Root: TwgWidget;
begin
  Result := Self;
  while Result.FParent <> nil do
    Result := Result.FParent;
end;

procedure TwgWidget.SetHost(const AHost: IwgWidgetHost);
begin
  FHost := AHost;
end;

function TwgWidget.GetHost: IwgWidgetHost;
var
  lRoot: TwgWidget;
begin
  // Only the root normally carries the host; everything resolves through it,
  // so re-parenting a subtree does not need the host propagated to each node.
  if FHost <> nil then
    Exit(FHost);
  lRoot := Root;
  if lRoot <> Self then
    Result := lRoot.FHost
  else
    Result := nil;
end;

function TwgWidget.EffectiveFont: IwgGlyphSource;
var
  lHost: IwgWidgetHost;
begin
  if FFont <> nil then
    Exit(FFont);
  if FParent <> nil then
  begin
    Result := FParent.EffectiveFont;
    if Result <> nil then
      Exit;
  end;
  lHost := GetHost;
  if lHost <> nil then
    Result := lHost.HostFont
  else
    Result := nil;
end;

{ --- geometry --- }

procedure TwgWidget.SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
var
  lOld: TRect;
  lChanged, lResized: Boolean;
begin
  if AWidth < 0 then AWidth := 0;
  if AHeight < 0 then AHeight := 0;
  lChanged := (ALeft <> FLeft) or (ATop <> FTop) or
              (AWidth <> FWidth) or (AHeight <> FHeight);
  if not lChanged then
    Exit;
  lResized := (AWidth <> FWidth) or (AHeight <> FHeight);
  lOld := BoundsRect;

  FLeft := ALeft;
  FTop := ATop;
  FWidth := AWidth;
  FHeight := AHeight;

  // Both the vacated and the newly occupied areas need repainting, and the
  // parent is the one whose coordinates those rectangles are in.
  if FParent <> nil then
  begin
    FParent.InvalidateRect(lOld);
    FParent.InvalidateRect(BoundsRect);
  end
  else
    Invalidate;

  if lResized then
    BoundsChanged;
end;

function TwgWidget.BoundsRect: TRect;
begin
  Result := Rect(FLeft, FTop, FLeft + FWidth, FTop + FHeight);
end;

function TwgWidget.ClientRect: TRect;
begin
  Result := Rect(0, 0, FWidth, FHeight);
end;

function TwgWidget.LocalToRoot(X, Y: Integer): TPoint;
var
  w: TwgWidget;
begin
  Result.X := X;
  Result.Y := Y;
  w := Self;
  while w.FParent <> nil do
  begin
    Inc(Result.X, w.FLeft);
    Inc(Result.Y, w.FTop);
    w := w.FParent;
  end;
end;

function TwgWidget.LocalRectToRoot(const R: TRect): TRect;
var
  p: TPoint;
begin
  p := LocalToRoot(R.Left, R.Top);
  Result := Rect(p.X, p.Y, p.X + (R.Right - R.Left), p.Y + (R.Bottom - R.Top));
end;

function TwgWidget.RootToLocal(X, Y: Integer): TPoint;
var
  p: TPoint;
begin
  p := LocalToRoot(0, 0);
  Result.X := X - p.X;
  Result.Y := Y - p.Y;
end;

{ --- painting --- }

procedure TwgWidget.Paint(ACanvas: TwgCanvas);
begin
  // Nothing by default: a bare TwgWidget is an invisible container.
end;

procedure TwgWidget.BoundsChanged;
begin
end;

function TwgWidget.MeasureSize(AAvailW, AAvailH: Integer): TSize;
begin
  Result.cx := FWidth;
  Result.cy := FHeight;
end;

procedure TwgWidget.PaintTree(ACanvas: TwgCanvas; const AClipRoot: TRect);
var
  i: Integer;
  lRootBounds: TRect;
begin
  if (not FVisible) or (FWidth <= 0) or (FHeight <= 0) then
    Exit;

  // Skip whole subtrees that cannot touch the damaged region. With a clipped
  // partial repaint this is where nearly all the work is avoided.
  lRootBounds := LocalRectToRoot(ClientRect);
  if wgRectEmpty(wgIntersectRect(lRootBounds, AClipRoot)) then
    Exit;

  ACanvas.Save;
  try
    ACanvas.Translate(FLeft, FTop);
    if FClipChildren then
      ACanvas.ClipRect(0, 0, FWidth, FHeight);
    Paint(ACanvas);
    for i := 0 to FChildCount - 1 do
      FChildren[i].PaintTree(ACanvas, AClipRoot);
  finally
    ACanvas.Restore;
  end;
end;

procedure TwgWidget.Invalidate;
begin
  InvalidateRect(ClientRect);
end;

procedure TwgWidget.InvalidateRect(const ARect: TRect);
var
  lHost: IwgWidgetHost;
  lRoot: TRect;
begin
  if wgRectEmpty(ARect) then
    Exit;
  lHost := GetHost;
  if lHost = nil then
    Exit;   // not attached to a surface yet; nothing to repaint
  lRoot := LocalRectToRoot(ARect);
  lHost.WidgetInvalidated(lRoot);
end;

procedure TwgWidget.InvalidateLayout;
var
  lHost: IwgWidgetHost;
begin
  lHost := GetHost;
  if lHost <> nil then
    lHost.WidgetLayoutInvalidated;
end;

{ --- hit testing --- }

function TwgWidget.ContainsPoint(X, Y: Integer): Boolean;
begin
  Result := (X >= 0) and (Y >= 0) and (X < FWidth) and (Y < FHeight);
end;

function TwgWidget.HitTest(X, Y: Integer): TwgWidget;
var
  i: Integer;
  lChild: TwgWidget;
begin
  Result := nil;
  if (not FVisible) or (not FEnabled) then
    Exit;
  if not ContainsPoint(X, Y) then
    Exit;
  // Last to first: later siblings paint on top, so they get the hit.
  for i := FChildCount - 1 downto 0 do
  begin
    lChild := FChildren[i];
    Result := lChild.HitTest(X - lChild.FLeft, Y - lChild.FTop);
    if Result <> nil then
      Exit;
  end;
  Result := Self;
end;

{ --- state --- }

procedure TwgWidget.SetState(AState: TwgWidgetState; AOn: Boolean);
begin
  if (AState in FStates) = AOn then
    Exit;
  if AOn then
    Include(FStates, AState)
  else
    Exclude(FStates, AState);
  Invalidate;
end;

procedure TwgWidget.SetVisible(AValue: Boolean);
begin
  if FVisible = AValue then
    Exit;
  FVisible := AValue;
  // Invalidate through the PARENT either way: when hiding, the widget can no
  // longer report its own area (PaintTree skips invisible widgets), so the
  // space it vacated would never be repainted.
  if FParent <> nil then
    FParent.InvalidateRect(BoundsRect)
  else
    Invalidate;
  InvalidateLayout;
end;

procedure TwgWidget.SetEnabled(AValue: Boolean);
begin
  if FEnabled = AValue then
    Exit;
  FEnabled := AValue;
  SetState(wsDisabled, not AValue);
  Invalidate;
end;

{ TwgDamage }

constructor TwgDamage.Create(ABufferCount: Integer);
begin
  inherited Create;
  SetBufferCount(ABufferCount);
end;

procedure TwgDamage.SetBufferCount(ACount: Integer);
begin
  if ACount < 1 then
    ACount := 1;
  SetLength(FRegions, ACount);
end;

function TwgDamage.BufferCount: Integer;
begin
  Result := Length(FRegions);
end;

function TwgDamage.GetRegion(AIndex: Integer): TRect;
begin
  Result := FRegions[AIndex];
end;

procedure TwgDamage.Add(const ARect: TRect);
var
  i: Integer;
begin
  if wgRectEmpty(ARect) then
    Exit;
  // Every buffer, not just the next one: each will eventually be painted and
  // must repair everything that changed since IT was last painted.
  for i := 0 to High(FRegions) do
    FRegions[i] := wgUnionRect(FRegions[i], ARect);
end;

procedure TwgDamage.AddAll(AWidth, AHeight: Integer);
begin
  Add(Rect(0, 0, AWidth, AHeight));
end;

function TwgDamage.Take(AIndex: Integer): TRect;
begin
  Result := FRegions[AIndex];
  FRegions[AIndex] := Rect(0, 0, 0, 0);
end;

function TwgDamage.IsDirty(AIndex: Integer): Boolean;
begin
  Result := not wgRectEmpty(FRegions[AIndex]);
end;

end.
