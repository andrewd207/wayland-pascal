program regen_units;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, sysutils,
  wayland_interface_reader, wayland_unitwriter;

const
  // core wayland.xml — always scanned so wl_* interfaces map to the 'wayland'
  // unit, regardless of whether it is in the output set this run.
  CoreWaylandXml = '/usr/share/wayland/wayland.xml';

var
  GMap: TStringList; // raw interface name -> defining unit name
  GServer: Boolean = False; // emit server-side bindings

// Unit-name convention: the core protocol keeps its bare 'wayland' name (it is
// integrated with the runtime); every other protocol gets a '_protocol' suffix.
// Server bindings use a parallel '_server' naming so they never collide with the
// client units (core -> 'wayland_server', others -> '<name>_server').
function ProtocolUnitName(const AName: String): String;
begin
  if GServer then
  begin
    if AName = 'wayland' then
      Result := 'wayland_server'
    else
      Result := AName + '_server';
  end
  else if AName = 'wayland' then
    Result := 'wayland'
  else
    Result := AName + '_protocol';
end;

// Read just the interface names from a protocol XML and record their unit.
procedure ScanProtocol(const AXml: String);
var
  lProtocol: TWIProtocolNode;
  lUnit: String;
  i: Integer;
begin
  if not FileExists(AXml) then
  begin
    WriteLn('WARNING: cannot scan (missing): ', AXml);
    Exit;
  end;
  lProtocol := TWIProtocolNode.Create(AXml);
  try
    lUnit := ProtocolUnitName(lProtocol.Name);
    for i := 0 to lProtocol.Interfaces.Count-1 do
      GMap.Values[lProtocol.Interfaces.Items[i].Name] := lUnit;
  finally
    lProtocol.Free;
  end;
end;

procedure Generate(const AXml, AOutDir: String);
var
  lProtocol: TWIProtocolNode;
  lWriter: TWaylandUnitWriter;
  lStream: TStringStream;
  lUnitName, lOutFile: String;
begin
  lProtocol := TWIProtocolNode.Create(AXml);
  lWriter := TWaylandUnitWriter.CreateNew();
  lWriter.FInterfaceUnitMap := GMap;
  lStream := TStringStream.Create('');
  try
    lUnitName := ProtocolUnitName(lProtocol.Name);
    lOutFile := IncludeTrailingPathDelimiter(AOutDir) + lUnitName + '.pas';
    lWriter.WriteUnit(lProtocol, lStream, False, lUnitName, GServer);
    lStream.SaveToFile(lOutFile);
    WriteLn('Wrote ', lOutFile, ' (', lStream.Size, ' bytes) from ', AXml);
  finally
    lStream.Free;
    lProtocol.Free;
  end;
end;

var
  i, lFirstXml: Integer;
  lOutDir: String;
  lArgs: array of String;
  s: String;
begin
  // usage: regen_units [--server] <outdir> <xml> [<xml> ...]
  // All given XMLs (plus the core wayland.xml) are scanned to build the
  // interface->unit map, then each given XML is generated into <outdir>.
  // --server emits the server-side bindings ('_server' units) instead of the
  // client proxies.
  lArgs := nil;
  for i := 1 to ParamCount do
  begin
    s := ParamStr(i);
    if s = '--server' then
      GServer := True
    else
    begin
      SetLength(lArgs, Length(lArgs)+1);
      lArgs[High(lArgs)] := s;
    end;
  end;

  if Length(lArgs) < 2 then
  begin
    WriteLn('usage: regen_units [--server] <outdir> <protocol.xml> [<protocol.xml> ...]');
    Halt(1);
  end;

  lOutDir := lArgs[0];
  lFirstXml := 1;
  if not DirectoryExists(lOutDir) then ForceDirectories(lOutDir);

  GMap := TStringList.Create;
  try
    ScanProtocol(CoreWaylandXml);
    for i := lFirstXml to High(lArgs) do
      ScanProtocol(lArgs[i]);

    for i := lFirstXml to High(lArgs) do
      Generate(lArgs[i], lOutDir);
  finally
    GMap.Free;
  end;
end.
