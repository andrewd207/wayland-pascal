// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.widget.layout — the concrete arrangement strategies.

  TwgLayout itself is declared in wlg.widget.core so a widget can own one; this
  unit supplies the implementations. They are strategy objects rather than
  container subclasses so a layout can be swapped at runtime and so a new one
  costs nothing structurally.

  Three ship, covering two different traditions on purpose:

    TwgBoxLayout     rows and columns with spacing and weights — composable,
                     and what new code should reach for
    TwgGridLayout    a fixed number of columns, filled row-major
    TwgAnchorLayout  Delphi/Lazarus Align and Anchors, so existing UI code
                     ports with light edits and simple forms need no layout
                     object at all

  MEASURE THEN ARRANGE. Measure asks what the container would like; Arrange
  commits. Two phases are needed because intrinsic sizes exist: a label's width
  follows its text, so nothing can be placed before asking.

  Per-child hints (margin, weight, alignment, min/max) live on the CHILD, in
  TwgLayoutHints, because that is where a caller expects to set them, even
  though the parent's layout is what reads them. }
unit wlg.widget.layout;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Types, Math,
  wlg.widget.types, wlg.widget.core;

type
  TwgBoxDirection = (bdHorizontal, bdVertical);

  { How a child is placed across the box's minor axis. }
  TwgCrossAlign = (
    caStretch,   // fill the cross axis (default)
    caStart,     // top for a row, left for a column
    caCenter,
    caEnd
  );

  { TwgBoxLayout — children in a row or a column.

    Leftover space along the main axis is shared out in proportion to each
    child's Weight; a child with Weight 0 keeps its natural size. That is the
    whole sizing model, and it composes: nest a vertical box inside a
    horizontal one and you have most real layouts. }

  TwgBoxLayout = class(TwgLayout)
  private
    FDirection: TwgBoxDirection;
    FSpacing: Integer;
    FCrossAlign: TwgCrossAlign;
    function MainOf(const ASize: TSize): Integer; inline;
    function CrossOf(const ASize: TSize): Integer; inline;
  public
    constructor Create(ADirection: TwgBoxDirection = bdVertical;
      ASpacing: Integer = 6; ACrossAlign: TwgCrossAlign = caStretch);
    function  Measure(AContainer: TwgWidget; AAvailW, AAvailH: Integer): TSize; override;
    procedure Arrange(AContainer: TwgWidget; const AClient: TRect); override;

    property Direction: TwgBoxDirection read FDirection write FDirection;
    property Spacing: Integer read FSpacing write FSpacing;
    property CrossAlign: TwgCrossAlign read FCrossAlign write FCrossAlign;
  end;

  { TwgGridLayout — a fixed column count, filled row-major.

    Column widths are the widest natural width in that column, row heights the
    tallest in that row; leftover space is shared among columns (and rows)
    containing at least one weighted child, so a grid can stretch sensibly
    without a per-column API. }

  TwgGridLayout = class(TwgLayout)
  private
    FColumns: Integer;
    FSpacingX, FSpacingY: Integer;
    procedure ComputeTracks(AContainer: TwgWidget; AAvailW, AAvailH: Integer;
      out AColW, ARowH: TIntegerDynArray; out AColWeighted, ARowWeighted: array of Boolean;
      out ARows: Integer);
  public
    constructor Create(AColumns: Integer = 2; ASpacingX: Integer = 6;
      ASpacingY: Integer = 6);
    function  Measure(AContainer: TwgWidget; AAvailW, AAvailH: Integer): TSize; override;
    procedure Arrange(AContainer: TwgWidget; const AClient: TRect); override;

    property Columns: Integer read FColumns write FColumns;
    property SpacingX: Integer read FSpacingX write FSpacingX;
    property SpacingY: Integer read FSpacingY write FSpacingY;
  end;

  { TwgAnchorLayout — Delphi-style Align and Anchors.

    Align runs first, in child order, each aligned child eating an edge of the
    remaining space; alClient takes whatever is left. Everything still
    unaligned is then anchored.

    Anchors are DELTA based, which is what makes them behave the way people
    expect: on a resize, a child anchored left keeps its x, anchored right
    moves with the edge, anchored both stretches, anchored neither stays
    proportionally centred. That needs the PREVIOUS client size, so the layout
    remembers it — the first Arrange only records it and leaves unaligned
    children exactly where they were put. }

  TwgAnchorLayout = class(TwgLayout)
  private
    FLastClient: TRect;
    FHaveLast: Boolean;
  public
    constructor Create;
    function  Measure(AContainer: TwgWidget; AAvailW, AAvailH: Integer): TSize; override;
    procedure Arrange(AContainer: TwgWidget; const AClient: TRect); override;
    // Forget the reference size, so the next Arrange re-baselines instead of
    // applying a delta. Call after moving children by hand.
    procedure Rebaseline;
  end;

implementation

function HMargin(const AHints: TwgLayoutHints): Integer; inline;
begin
  Result := AHints.Margin.Left + AHints.Margin.Right;
end;

function VMargin(const AHints: TwgLayoutHints): Integer; inline;
begin
  Result := AHints.Margin.Top + AHints.Margin.Bottom;
end;

// Children that take part in layout at all. Hidden widgets occupy no space —
// which is what makes Visible usable for showing and hiding parts of a form.
function Participates(AChild: TwgWidget): Boolean; inline;
begin
  Result := (AChild <> nil) and AChild.Visible;
end;

{ TwgBoxLayout }

constructor TwgBoxLayout.Create(ADirection: TwgBoxDirection; ASpacing: Integer;
  ACrossAlign: TwgCrossAlign);
begin
  inherited Create;
  FDirection := ADirection;
  FSpacing := ASpacing;
  FCrossAlign := ACrossAlign;
end;

function TwgBoxLayout.MainOf(const ASize: TSize): Integer;
begin
  if FDirection = bdHorizontal then
    Result := ASize.cx
  else
    Result := ASize.cy;
end;

function TwgBoxLayout.CrossOf(const ASize: TSize): Integer;
begin
  if FDirection = bdHorizontal then
    Result := ASize.cy
  else
    Result := ASize.cx;
end;

function TwgBoxLayout.Measure(AContainer: TwgWidget; AAvailW, AAvailH: Integer): TSize;
var
  i, lVisible: Integer;
  lChild: TwgWidget;
  lSize: TSize;
  lMain, lCross, lMainMargin, lCrossMargin: Integer;
begin
  lMain := 0;
  lCross := 0;
  lVisible := 0;
  for i := 0 to AContainer.ChildCount - 1 do
  begin
    lChild := AContainer.Children[i];
    if not Participates(lChild) then
      Continue;
    Inc(lVisible);
    lSize := lChild.PreferredSize(AAvailW, AAvailH);
    if FDirection = bdHorizontal then
    begin
      lMainMargin := HMargin(lChild.LayoutHints);
      lCrossMargin := VMargin(lChild.LayoutHints);
    end
    else
    begin
      lMainMargin := VMargin(lChild.LayoutHints);
      lCrossMargin := HMargin(lChild.LayoutHints);
    end;
    Inc(lMain, MainOf(lSize) + lMainMargin);
    lCross := Max(lCross, CrossOf(lSize) + lCrossMargin);
  end;
  if lVisible > 1 then
    Inc(lMain, FSpacing * (lVisible - 1));

  Inc(lMain, 0);
  if FDirection = bdHorizontal then
  begin
    Result.cx := lMain + AContainer.Padding.Left + AContainer.Padding.Right;
    Result.cy := lCross + AContainer.Padding.Top + AContainer.Padding.Bottom;
  end
  else
  begin
    Result.cx := lCross + AContainer.Padding.Left + AContainer.Padding.Right;
    Result.cy := lMain + AContainer.Padding.Top + AContainer.Padding.Bottom;
  end;
end;

procedure TwgBoxLayout.Arrange(AContainer: TwgWidget; const AClient: TRect);
var
  i, n, lAvailMain, lAvailCross, lUsed, lSpare, lGiven: Integer;
  lChild: TwgWidget;
  lKids: array of TwgWidget;
  lMainSize: TIntegerDynArray;
  lCrossSize: TIntegerDynArray;
  lTotalWeight, lAcc: Single;
  lSize: TSize;
  lPos, lCrossPos, lCrossAvail, lExtra: Integer;
begin
  n := 0;
  SetLength(lKids, AContainer.ChildCount);
  for i := 0 to AContainer.ChildCount - 1 do
    if Participates(AContainer.Children[i]) then
    begin
      lKids[n] := AContainer.Children[i];
      Inc(n);
    end;
  SetLength(lKids, n);
  if n = 0 then
    Exit;

  if FDirection = bdHorizontal then
  begin
    lAvailMain := AClient.Right - AClient.Left;
    lAvailCross := AClient.Bottom - AClient.Top;
  end
  else
  begin
    lAvailMain := AClient.Bottom - AClient.Top;
    lAvailCross := AClient.Right - AClient.Left;
  end;

  SetLength(lMainSize, n);
  SetLength(lCrossSize, n);
  lUsed := FSpacing * (n - 1);
  lTotalWeight := 0;
  for i := 0 to n - 1 do
  begin
    lChild := lKids[i];
    lSize := lChild.PreferredSize(lAvailMain, lAvailCross);
    lMainSize[i] := MainOf(lSize);
    lCrossSize[i] := CrossOf(lSize);
    if FDirection = bdHorizontal then
      Inc(lUsed, lMainSize[i] + HMargin(lChild.LayoutHints))
    else
      Inc(lUsed, lMainSize[i] + VMargin(lChild.LayoutHints));
    lTotalWeight := lTotalWeight + Max(0, lChild.LayoutHints.Weight);
  end;

  // Share the slack (or the shortfall — lSpare may be negative) by weight.
  lSpare := lAvailMain - lUsed;
  if (lTotalWeight > 0) and (lSpare <> 0) then
  begin
    lAcc := 0;
    lExtra := 0;
    for i := 0 to n - 1 do
      if lKids[i].LayoutHints.Weight > 0 then
      begin
        // Accumulate in floating point and round the RUNNING total, so the
        // rounding error cannot pile up and leave a gap at the far end.
        lAcc := lAcc + lKids[i].LayoutHints.Weight;
        lGiven := Round(lSpare * (lAcc / lTotalWeight));
        Inc(lMainSize[i], lGiven - lExtra);
        lExtra := lGiven;
        if lMainSize[i] < 0 then
          lMainSize[i] := 0;
      end;
  end;

  if FDirection = bdHorizontal then
    lPos := AClient.Left
  else
    lPos := AClient.Top;

  for i := 0 to n - 1 do
  begin
    lChild := lKids[i];
    if FDirection = bdHorizontal then
    begin
      Inc(lPos, lChild.LayoutHints.Margin.Left);
      lCrossAvail := lAvailCross - VMargin(lChild.LayoutHints);
      case FCrossAlign of
        caStretch: begin lCrossPos := AClient.Top + lChild.LayoutHints.Margin.Top;
                         lCrossSize[i] := Max(0, lCrossAvail); end;
        caCenter:  lCrossPos := AClient.Top + lChild.LayoutHints.Margin.Top
                     + Max(0, (lCrossAvail - lCrossSize[i]) div 2);
        caEnd:     lCrossPos := AClient.Bottom - lChild.LayoutHints.Margin.Bottom
                     - lCrossSize[i];
        else       lCrossPos := AClient.Top + lChild.LayoutHints.Margin.Top;
      end;
      lChild.SetBounds(lPos, lCrossPos, lMainSize[i], lCrossSize[i]);
      Inc(lPos, lMainSize[i] + lChild.LayoutHints.Margin.Right + FSpacing);
    end
    else
    begin
      Inc(lPos, lChild.LayoutHints.Margin.Top);
      lCrossAvail := lAvailCross - HMargin(lChild.LayoutHints);
      case FCrossAlign of
        caStretch: begin lCrossPos := AClient.Left + lChild.LayoutHints.Margin.Left;
                         lCrossSize[i] := Max(0, lCrossAvail); end;
        caCenter:  lCrossPos := AClient.Left + lChild.LayoutHints.Margin.Left
                     + Max(0, (lCrossAvail - lCrossSize[i]) div 2);
        caEnd:     lCrossPos := AClient.Right - lChild.LayoutHints.Margin.Right
                     - lCrossSize[i];
        else       lCrossPos := AClient.Left + lChild.LayoutHints.Margin.Left;
      end;
      lChild.SetBounds(lCrossPos, lPos, lCrossSize[i], lMainSize[i]);
      Inc(lPos, lMainSize[i] + lChild.LayoutHints.Margin.Bottom + FSpacing);
    end;
  end;
end;

{ TwgGridLayout }

constructor TwgGridLayout.Create(AColumns: Integer; ASpacingX, ASpacingY: Integer);
begin
  inherited Create;
  FColumns := Max(1, AColumns);
  FSpacingX := ASpacingX;
  FSpacingY := ASpacingY;
end;

procedure TwgGridLayout.ComputeTracks(AContainer: TwgWidget;
  AAvailW, AAvailH: Integer; out AColW, ARowH: TIntegerDynArray;
  out AColWeighted, ARowWeighted: array of Boolean; out ARows: Integer);
var
  i, n, c, r: Integer;
  lChild: TwgWidget;
  lSize: TSize;
  lKids: array of TwgWidget;
begin
  n := 0;
  SetLength(lKids, AContainer.ChildCount);
  for i := 0 to AContainer.ChildCount - 1 do
    if Participates(AContainer.Children[i]) then
    begin
      lKids[n] := AContainer.Children[i];
      Inc(n);
    end;

  ARows := (n + FColumns - 1) div FColumns;
  SetLength(AColW, FColumns);
  SetLength(ARowH, Max(ARows, 0));
  for c := 0 to FColumns - 1 do
  begin
    AColW[c] := 0;
    if c <= High(AColWeighted) then AColWeighted[c] := False;
  end;
  for r := 0 to ARows - 1 do
  begin
    ARowH[r] := 0;
    if r <= High(ARowWeighted) then ARowWeighted[r] := False;
  end;

  for i := 0 to n - 1 do
  begin
    lChild := lKids[i];
    c := i mod FColumns;
    r := i div FColumns;
    lSize := lChild.PreferredSize(AAvailW, AAvailH);
    AColW[c] := Max(AColW[c], lSize.cx + HMargin(lChild.LayoutHints));
    ARowH[r] := Max(ARowH[r], lSize.cy + VMargin(lChild.LayoutHints));
    if lChild.LayoutHints.Weight > 0 then
    begin
      if c <= High(AColWeighted) then AColWeighted[c] := True;
      if r <= High(ARowWeighted) then ARowWeighted[r] := True;
    end;
  end;
end;

function TwgGridLayout.Measure(AContainer: TwgWidget; AAvailW, AAvailH: Integer): TSize;
var
  lColW, lRowH: TIntegerDynArray;
  lColWt: array of Boolean;
  lRowWt: array of Boolean;
  lRows, i, lW, lH: Integer;
begin
  SetLength(lColWt, FColumns);
  SetLength(lRowWt, Max(1, AContainer.ChildCount));
  ComputeTracks(AContainer, AAvailW, AAvailH, lColW, lRowH, lColWt, lRowWt, lRows);
  lW := 0;
  for i := 0 to High(lColW) do
    Inc(lW, lColW[i]);
  if FColumns > 1 then
    Inc(lW, FSpacingX * (FColumns - 1));
  lH := 0;
  for i := 0 to High(lRowH) do
    Inc(lH, lRowH[i]);
  if lRows > 1 then
    Inc(lH, FSpacingY * (lRows - 1));
  Result.cx := lW + AContainer.Padding.Left + AContainer.Padding.Right;
  Result.cy := lH + AContainer.Padding.Top + AContainer.Padding.Bottom;
end;

procedure TwgGridLayout.Arrange(AContainer: TwgWidget; const AClient: TRect);
var
  lColW, lRowH: TIntegerDynArray;
  lColWt: array of Boolean;
  lRowWt: array of Boolean;
  lRows, n, i, c, r, lNat, lSpare, lCount, lShare: Integer;
  lKids: array of TwgWidget;
  lX, lY: Integer;
  lChild: TwgWidget;
begin
  n := 0;
  SetLength(lKids, AContainer.ChildCount);
  for i := 0 to AContainer.ChildCount - 1 do
    if Participates(AContainer.Children[i]) then
    begin
      lKids[n] := AContainer.Children[i];
      Inc(n);
    end;
  SetLength(lKids, n);
  if n = 0 then
    Exit;

  SetLength(lColWt, FColumns);
  SetLength(lRowWt, Max(1, n));
  ComputeTracks(AContainer, AClient.Right - AClient.Left,
    AClient.Bottom - AClient.Top, lColW, lRowH, lColWt, lRowWt, lRows);

  // Spread horizontal slack over the weighted columns, or over all of them if
  // nothing is weighted — a grid that refuses to fill its container is more
  // surprising than one that stretches evenly.
  lNat := 0;
  for i := 0 to High(lColW) do Inc(lNat, lColW[i]);
  if FColumns > 1 then Inc(lNat, FSpacingX * (FColumns - 1));
  lSpare := (AClient.Right - AClient.Left) - lNat;
  if lSpare > 0 then
  begin
    lCount := 0;
    for i := 0 to High(lColWt) do if lColWt[i] then Inc(lCount);
    if lCount = 0 then lCount := FColumns;
    lShare := lSpare div lCount;
    for i := 0 to High(lColW) do
      if (lColWt[i]) or (lCount = FColumns) then
        Inc(lColW[i], lShare);
  end;

  lNat := 0;
  for i := 0 to High(lRowH) do Inc(lNat, lRowH[i]);
  if lRows > 1 then Inc(lNat, FSpacingY * (lRows - 1));
  lSpare := (AClient.Bottom - AClient.Top) - lNat;
  if lSpare > 0 then
  begin
    lCount := 0;
    for i := 0 to lRows - 1 do if lRowWt[i] then Inc(lCount);
    if lCount > 0 then
    begin
      lShare := lSpare div lCount;
      for i := 0 to lRows - 1 do
        if lRowWt[i] then
          Inc(lRowH[i], lShare);
    end;
  end;

  lY := AClient.Top;
  for r := 0 to lRows - 1 do
  begin
    lX := AClient.Left;
    for c := 0 to FColumns - 1 do
    begin
      i := r * FColumns + c;
      if i < n then
      begin
        lChild := lKids[i];
        lChild.SetBounds(
          lX + lChild.LayoutHints.Margin.Left,
          lY + lChild.LayoutHints.Margin.Top,
          Max(0, lColW[c] - HMargin(lChild.LayoutHints)),
          Max(0, lRowH[r] - VMargin(lChild.LayoutHints)));
      end;
      Inc(lX, lColW[c] + FSpacingX);
    end;
    Inc(lY, lRowH[r] + FSpacingY);
  end;
end;

{ TwgAnchorLayout }

constructor TwgAnchorLayout.Create;
begin
  inherited Create;
end;

procedure TwgAnchorLayout.Rebaseline;
begin
  FHaveLast := False;
end;

function TwgAnchorLayout.Measure(AContainer: TwgWidget; AAvailW, AAvailH: Integer): TSize;
var
  i: Integer;
  lChild: TwgWidget;
begin
  // An anchored form has no natural size of its own; report the extent of what
  // is in it so a parent has something sensible to work with.
  Result.cx := 0;
  Result.cy := 0;
  for i := 0 to AContainer.ChildCount - 1 do
  begin
    lChild := AContainer.Children[i];
    if not Participates(lChild) then
      Continue;
    Result.cx := Max(Result.cx, lChild.Left + lChild.Width);
    Result.cy := Max(Result.cy, lChild.Top + lChild.Height);
  end;
  Inc(Result.cx, AContainer.Padding.Right);
  Inc(Result.cy, AContainer.Padding.Bottom);
end;

procedure TwgAnchorLayout.Arrange(AContainer: TwgWidget; const AClient: TRect);
var
  i, lDW, lDH: Integer;
  lChild: TwgWidget;
  lFree: TRect;
  lSize: TSize;
  lX, lY, lW, lH: Integer;
  lA: TwgAnchors;
begin
  lFree := AClient;

  // Pass 1: Align, in child order. Each aligned child consumes an edge of what
  // is left, which is exactly Delphi's rule and why order matters.
  for i := 0 to AContainer.ChildCount - 1 do
  begin
    lChild := AContainer.Children[i];
    if (not Participates(lChild)) or (lChild.LayoutHints.Align = alNone) then
      Continue;
    lSize := lChild.PreferredSize(lFree.Right - lFree.Left, lFree.Bottom - lFree.Top);
    case lChild.LayoutHints.Align of
      alLeft:
        begin
          lChild.SetBounds(lFree.Left, lFree.Top, lSize.cx, lFree.Bottom - lFree.Top);
          Inc(lFree.Left, lSize.cx);
        end;
      alRight:
        begin
          lChild.SetBounds(lFree.Right - lSize.cx, lFree.Top, lSize.cx,
            lFree.Bottom - lFree.Top);
          Dec(lFree.Right, lSize.cx);
        end;
      alTop:
        begin
          lChild.SetBounds(lFree.Left, lFree.Top, lFree.Right - lFree.Left, lSize.cy);
          Inc(lFree.Top, lSize.cy);
        end;
      alBottom:
        begin
          lChild.SetBounds(lFree.Left, lFree.Bottom - lSize.cy,
            lFree.Right - lFree.Left, lSize.cy);
          Dec(lFree.Bottom, lSize.cy);
        end;
      alClient:
        begin
          lChild.SetBounds(lFree.Left, lFree.Top, lFree.Right - lFree.Left,
            lFree.Bottom - lFree.Top);
          // alClient takes everything; later aligned children get nothing.
          lFree.Right := lFree.Left;
          lFree.Bottom := lFree.Top;
        end;
      else
        ; // alNone was skipped above and cannot reach here
    end;
  end;

  // Pass 2: anchors, as deltas against the previous client size. The first
  // time through there is no previous size, so children keep the bounds they
  // were given and this only records the baseline.
  if FHaveLast then
  begin
    lDW := (AClient.Right - AClient.Left) - (FLastClient.Right - FLastClient.Left);
    lDH := (AClient.Bottom - AClient.Top) - (FLastClient.Bottom - FLastClient.Top);
    if (lDW <> 0) or (lDH <> 0) then
      for i := 0 to AContainer.ChildCount - 1 do
      begin
        lChild := AContainer.Children[i];
        if (not Participates(lChild)) or (lChild.LayoutHints.Align <> alNone) then
          Continue;
        lA := lChild.LayoutHints.Anchors;
        lX := lChild.Left; lY := lChild.Top;
        lW := lChild.Width; lH := lChild.Height;

        if (akLeft in lA) and (akRight in lA) then
          Inc(lW, lDW)                       // pinned both sides: stretch
        else if akRight in lA then
          Inc(lX, lDW)                       // pinned right: move with the edge
        else if not (akLeft in lA) then
          Inc(lX, lDW div 2);                // pinned neither: stay centred

        if (akTop in lA) and (akBottom in lA) then
          Inc(lH, lDH)
        else if akBottom in lA then
          Inc(lY, lDH)
        else if not (akTop in lA) then
          Inc(lY, lDH div 2);

        lChild.SetBounds(lX, lY, Max(0, lW), Max(0, lH));
      end;
  end;
  FLastClient := AClient;
  FHaveLast := True;
end;

end.
