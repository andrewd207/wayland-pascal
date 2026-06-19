// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ cursor_info — dump the frames of a named cursor from an XCursor theme, using
  the pure-Pascal xcursor loader (no libXcursor / no Wayland connection needed).

  Usage:  cursor-info [theme] [name] [size]
    e.g.  cursor-info Adwaita left_ptr 24
          cursor-info '' watch        (default theme, animated cursor) }
program cursor_info;

{$mode objfpc}{$H+}

uses
  SysUtils, xcursor;

var
  lTheme, lName: String;
  lSize, i: Integer;
  lXTheme: TXCursorTheme;
  lImages: TXCursorImages;
begin
  lTheme := '';
  lName  := 'left_ptr';
  lSize  := 24;
  if ParamCount >= 1 then lTheme := ParamStr(1);
  if ParamCount >= 2 then lName  := ParamStr(2);
  if ParamCount >= 3 then lSize  := StrToIntDef(ParamStr(3), 24);

  lXTheme := TXCursorTheme.Create(lTheme, lSize);
  try
    lImages := lXTheme.LoadCursor(lName);
    if Length(lImages) = 0 then
    begin
      WriteLn(Format('cursor "%s" not found in theme "%s" (or its inherited themes)',
        [lName, lXTheme.Theme]));
      Halt(1);
    end;
    WriteLn(Format('theme=%s  cursor=%s  requested-size=%d  ->  %d frame(s):',
      [lXTheme.Theme, lName, lSize, Length(lImages)]));
    for i := 0 to High(lImages) do
      WriteLn(Format('  [%2d] %dx%d  hotspot=(%d,%d)  delay=%dms  %d bytes',
        [i, lImages[i].Width, lImages[i].Height,
         lImages[i].XHot, lImages[i].YHot, lImages[i].Delay,
         Length(lImages[i].Pixels)]));
  finally
    lXTheme.Free;
  end;
end.
