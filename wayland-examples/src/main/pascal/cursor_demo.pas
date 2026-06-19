{ cursor_demo — load several named cursors, paint them in a grid, and change the
  pointer to whichever cell it is hovering.

  Demonstrates the wayland-classes cursor path (pure-Pascal XCursor loader): the
  same TXCursorTheme that backs TfpgwDisplay.SetCursor is used here to fetch each
  cursor's pixels, which are alpha-composited (Xcursor images are premultiplied
  ARGB) into the window via TWaylandCanvas. Hovering a cell calls
  Display.SetCursor with that cell's candidate names, so the real pointer turns
  into the pictured cursor.

  Controls:
    move    — hover a cell to change the pointer to that cursor
    left    — press-and-hold to drag the window (interactive move)
    right   — quit

  Open against a Wayland compositor with a cursor theme installed. }
program cursor_demo;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, BaseUnix,{$ENDIF}
  SysUtils, Types,
  fpg_wayland_classes, wayland, wayland_canvas, xcursor;

const
  COLS     = 4;
  CELL     = 100;       { grid cell size in pixels }
  PAD      = 8;

type
  { A grid cell: candidate cursor names (first that resolves wins) plus the
    loaded first-frame image used to paint the cell. }
  TCell = record
    Names: array of String;
    Img: TXCursorImage;
    HasImg: Boolean;
  end;

  TDemo = class
    Display: TfpgwDisplay;
    Window: TfpgwWindow;
    Theme: TXCursorTheme;
    Cells: array of TCell;
    Rows: Integer;
    Hovered: Integer;       { index of the hovered cell, or -1 }
    Quit: Boolean;
    Dirty: Boolean;
    Painted: Boolean;
    procedure AddCursor(const ANames: array of String);
    function  CellAt(AX, AY: Integer): Integer;
    procedure DoPaint(Sender: TObject);
    procedure DoMotion(Sender: TObject; ATime: LongWord; AX, AY: Integer);
    procedure DoButton(Sender: TObject; ATime: LongWord; AButton: LongWord; AState: TWlPointer.TButtonState);
    procedure DoLeave(Sender: TObject);
    procedure Run;
  end;

{ Composite a premultiplied-ARGB cursor image onto the (opaque) canvas. }
procedure BlitCursor(c: TWaylandCanvas; const AImg: TXCursorImage; ADestX, ADestY: Integer);
var
  sx, sy, px, py: Integer;
  s, d: DWord;
  sa, sr, sg, sb, dr, dg, db: Integer;
begin
  if Length(AImg.Pixels) = 0 then
    Exit;
  for sy := 0 to AImg.Height - 1 do
  begin
    py := ADestY + sy;
    if (py < 0) or (py >= c.Height) then Continue;
    for sx := 0 to AImg.Width - 1 do
    begin
      px := ADestX + sx;
      if (px < 0) or (px >= c.Width) then Continue;
      s := PDWord(@AImg.Pixels[(sy * AImg.Width + sx) * 4])^;
      sa := (s shr 24) and $FF;
      if sa = 0 then Continue;            { fully transparent — keep background }
      sr := (s shr 16) and $FF;           { channels are already premultiplied }
      sg := (s shr 8) and $FF;
      sb := s and $FF;
      d := c.GetPixel(px, py);
      dr := (d shr 16) and $FF;
      dg := (d shr 8) and $FF;
      db := d and $FF;
      { out = src + dst*(255-srcAlpha), src premultiplied -> result opaque }
      dr := sr + dr * (255 - sa) div 255;
      dg := sg + dg * (255 - sa) div 255;
      db := sb + db * (255 - sa) div 255;
      c.PutPixel(px, py, ARGB(255, dr, dg, db));
    end;
  end;
end;

procedure TDemo.AddCursor(const ANames: array of String);
var
  lCell: TCell;
  lImages: TXCursorImages;
  S: String;
  i: Integer;
begin
  lCell := Default(TCell);
  SetLength(lCell.Names, Length(ANames));
  for i := 0 to High(ANames) do
    lCell.Names[i] := ANames[i];
  { Load the first candidate that resolves in the theme chain. }
  for S in ANames do
  begin
    lImages := Theme.LoadCursor(S);
    if Length(lImages) > 0 then
    begin
      lCell.Img := lImages[0];
      lCell.HasImg := True;
      Break;
    end;
  end;
  SetLength(Cells, Length(Cells) + 1);
  Cells[High(Cells)] := lCell;
end;

function TDemo.CellAt(AX, AY: Integer): Integer;
var
  col, row: Integer;
begin
  Result := -1;
  if (AX < 0) or (AY < 0) then Exit;
  col := AX div CELL;
  row := AY div CELL;
  if (col >= COLS) or (row >= Rows) then Exit;
  Result := row * COLS + col;
  if Result >= Length(Cells) then
    Result := -1;
end;

procedure TDemo.DoPaint(Sender: TObject);
var
  lBuf: TfpgwBuffer;
  c: TWaylandCanvas;
  i, col, row, cx, cy, ix, iy: Integer;
  bg, border: TCanvasColor;
begin
  lBuf := Window.NextBuffer;
  if lBuf = nil then
    Exit;
  c := TWaylandCanvas.Create(lBuf.Data, lBuf.Width, lBuf.Height, lBuf.Stride);
  try
    c.Clear(RGB(30, 30, 38));
    for i := 0 to High(Cells) do
    begin
      col := i mod COLS;
      row := i div COLS;
      cx := col * CELL;
      cy := row * CELL;
      if i = Hovered then
      begin
        bg := RGB(54, 70, 96);
        border := RGB(150, 200, 255);
      end
      else
      begin
        bg := RGB(42, 42, 52);
        border := RGB(80, 80, 96);
      end;
      c.FillRoundRect(cx + PAD, cy + PAD, CELL - 2 * PAD, CELL - 2 * PAD, 10, 10, bg);
      c.RoundRect(cx + PAD, cy + PAD, CELL - 2 * PAD, CELL - 2 * PAD, 10, 10, border);
      if Cells[i].HasImg then
      begin
        ix := cx + (CELL - Cells[i].Img.Width) div 2;
        iy := cy + (CELL - Cells[i].Img.Height) div 2;
        BlitCursor(c, Cells[i].Img, ix, iy);
      end;
    end;
  finally
    c.Free;
  end;
  lBuf.SetPaintRect(0, 0, lBuf.Width, lBuf.Height);
  Window.Paint(lBuf);
end;

procedure TDemo.DoMotion(Sender: TObject; ATime: LongWord; AX, AY: Integer);
var
  lCell: Integer;
begin
  lCell := CellAt(AX, AY);
  if lCell = Hovered then
    Exit;
  Hovered := lCell;
  if (lCell >= 0) and Cells[lCell].HasImg then
    Display.SetCursor(Cells[lCell].Names)
  else
    Display.SetCursor(['left_ptr', 'default']);
  Dirty := True;   { repaint the highlight in the main loop }
end;

procedure TDemo.DoButton(Sender: TObject; ATime: LongWord; AButton: LongWord;
  AState: TWlPointer.TButtonState);
begin
  if AState <> TWlPointer.TButtonState.buPressed then
    Exit;
  if AButton = BTN_RIGHT then
    Quit := True
  else if AButton = BTN_LEFT then
    { hand the drag to the compositor (server-side interactive move) }
    Window.SurfaceShell.Move(Window.ButtonPressSerial);
end;

procedure TDemo.DoLeave(Sender: TObject);
begin
  if Hovered <> -1 then
  begin
    Hovered := -1;
    Dirty := True;
  end;
end;

procedure TDemo.Run;
var
  lW, lH: Integer;
begin
  {$IFDEF UNIX}
  FpSignal(SIGPIPE, SignalHandler(SIG_IGN));
  {$ENDIF}
  Display := TfpgwDisplay.Create(Self, '');
  if not Display.Connected then
  begin
    WriteLn('could not connect to a Wayland compositor (is WAYLAND_DISPLAY set?)');
    Halt(1);
  end;
  Display.AfterCreate;

  { Our own theme loader for painting the grid (the same loader backs
    Display.SetCursor for the live pointer). }
  Theme := TXCursorTheme.Create('', 32);
  Hovered := -1;

  { Each entry lists candidate names; themes vary, so the first that resolves
    is used both for painting and for SetCursor. }
  AddCursor(['left_ptr', 'default', 'arrow']);
  AddCursor(['hand2', 'hand1', 'pointing_hand']);
  AddCursor(['xterm', 'text', 'ibeam']);
  AddCursor(['crosshair', 'cross']);
  AddCursor(['fleur', 'move', 'all-scroll']);
  AddCursor(['watch', 'wait']);
  AddCursor(['sb_h_double_arrow', 'col-resize', 'ew-resize']);
  AddCursor(['sb_v_double_arrow', 'row-resize', 'ns-resize']);
  AddCursor(['question_arrow', 'help', 'whats_this']);
  AddCursor(['not-allowed', 'crossed_circle', 'forbidden']);
  AddCursor(['grabbing', 'closedhand', 'dnd-none']);
  AddCursor(['pirate', 'X_cursor', 'kill']);

  Rows := (Length(Cells) + COLS - 1) div COLS;
  lW := COLS * CELL;
  lH := Rows * CELL;

  Window := TfpgwWindow.Create(Self, Display, nil, 0, 0, lW, lH, nil);
  Window.OnPaint := @DoPaint;
  Window.SurfaceShell.SetTitle('wayland cursor demo — hover to change, left-drag moves, right-click quits');
  Window.SurfaceShell.SetServerSideDecorations;
  Display.OnMouseMotion := @DoMotion;
  Display.OnMouseButton := @DoButton;
  Display.OnMouseLeave := @DoLeave;

  WriteLn('cursor demo: hover a cell to change the cursor; left-drag moves; right-click quits');
  Flush(Output);

  while not Quit do
  begin
    Display.WaitEvent(50);
    if Window.Configured and not Painted then
    begin
      Painted := True;
      Window.Redraw;
    end
    else if Dirty then
    begin
      Dirty := False;
      Window.Redraw;
    end;
  end;

  Window.Free;
  Theme.Free;
  Display.Free;
end;

var
  lDemo: TDemo;
begin
  lDemo := TDemo.Create;
  try
    lDemo.Run;
  finally
    lDemo.Free;
  end;
end.
