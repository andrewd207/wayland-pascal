program regen_units;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, sysutils,
  wayland_interface_reader, wayland_unitwriter;

  procedure Generate(const AXml, AOutFile: String);
  var
    lProtocol: TWIProtocolNode;
    lWriter: TWaylandUnitWriter;
    lStream: TStringStream;
  begin
    lProtocol := TWIProtocolNode.Create(AXml);
    lWriter := TWaylandUnitWriter.CreateNew();
    lStream := TStringStream.Create('');
    try
      lWriter.WriteUnit(lProtocol, lStream);
      lStream.SaveToFile(AOutFile);
      WriteLn('Wrote ', AOutFile, ' (', lStream.Size, ' bytes) from ', AXml);
    finally
      lStream.Free;
      // lWriter / lProtocol intentionally not freed; matches main program usage
    end;
  end;

var
  i: Integer;
begin
  // args: <xml> <outfile> [<xml2> <outfile2> ...]
  i := 1;
  while i + 1 <= ParamCount do
  begin
    Generate(ParamStr(i), ParamStr(i + 1));
    Inc(i, 2);
  end;
end.
