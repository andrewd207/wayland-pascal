program wayland_wire_proj;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, sysutils, wayland_interface_reader, wayland_strings,
  //wayland_implementation,
  wayland_stream, Wayland_Core,
  wayland_errors, wayland_queue, wayland_internal_interfaces,//}
  wayland_unitwriter
  , wayland
  , xdg_shell, wayland_shm_impl, unix_fd_socket//}

  { you can add units after this };


type

  { TWaylandTest }

  TWaylandTest = class
    FQuit: Boolean;
    FDisplay: TWlDisplay;
    FRegistry: TWlRegistry;
    FCompositor: TWlCompositor;
    FBuffer: TWlBuffer;
    FSurface: TWlSurface;
    FXDGSurface: TXdgSurface;
    FToplevel: TXdgToplevel;
    FWM: TXdgWmBase;
    FShell: TWlShell;
    FSHM: TWlShm;
    FSeat: TWlSeat;
    FConfigured : Boolean;
    FWidth, FHeight: Integer;
    constructor Create;
  private
    procedure ButtonEvent(Sender: TWlPointer; aSerial: DWord; aTime: DWord; aButton: DWord; aState: TWlPointer.TButtonState);
    procedure HandleError(Sender: TWlDisplay; aObjectId: Cardinal; aCode: DWord; aMessage: String);
    procedure HandlePing(Sender: TXdgWmBase; aSerial: DWord);

    procedure Handle_Registry_Global(Sender: TWlRegistry; aName: DWord; aInterface: String; aVersion: DWord);

    procedure HandleShmFormat(Sender: TWlShm; aFormat: TWlShm.TFormat);
    procedure HandleXDGConfigure(Sender: TXdgSurface; aSerial: DWord);
    procedure MouseMotion(Sender: TWlPointer; aTime: DWord; aSurfaceX: TWaylandFixed; aSurfaceY: TWaylandFixed);
    procedure SeatCapabilities(Sender: TWlSeat; aCapabilities: TwlSeat.TCapability);
    procedure SeatName(Sender: TWlSeat; aName: String);
    procedure ToplevelClose(Sender: TXdgToplevel);
    procedure ToplevelConfigure(Sender: TXdgToplevel; aWidth: Integer; aHeight: Integer; aStates: TBytes);
    procedure ToplevelConfigureBounds(Sender: TXdgToplevel; aWidth: Integer; aHeight: Integer);
  end;
  //}

var
  lProtocol: TWIProtocolNode;
  lWriter: TWaylandUnitWriter;
  lStringStream: TStringStream;
  lWaylandTest: TWaylandTest;

{ TWaylandTest }

constructor TWaylandTest.Create;
var
  lCallback: TWlCallback;

  lShellSurface: TWlShellSurface;
  lRegion: TWlRegion;


  lData: Pointer;
  lFd: Integer;
  lPool: TWlShmPool;

begin

  //// Connection.SendRequest(GetObjectId, R_BIND, [ANameIndex, AInterfaceName, AVersion, AObjectID]);



  TWlDisplay.TryCreateConnection(FDisplay);

  FDisplay.OnError := @HAndleError;

  FRegistry := FDisplay.GetRegistry;
  FRegistry.OnGlobal:=@Handle_Registry_Global;
  FDisplay.SyncAndWait;


  //lPool := FSHM.AllocateShmPool(1024*1024, @lData, @lFd);
  FDisplay.SyncAndWait;

  FSurface := FCompositor.CreateSurface();



  //FDisplay.SyncAndWait;
  FXDGSurface := FWM.GetXdgSurface(FSurface);
  FXDGSurface.OnConfigure:=@HandleXDGConfigure;


  FToplevel := FXDGSurface.GetToplevel();
  FToplevel.SetTitle('My Test');
  FToplevel.OnConfigure:=@ToplevelConfigure;
  FTopLevel.OnClose:=@ToplevelClose;
  FToplevel.OnConfigureBounds:=@ToplevelConfigureBounds;
  //lTopLevel.OnConfigureBounds:=@ToplevelConfigureBounds;
  //lTopLevel.OnWmCapabilities:=@ToplevelWMCapabilities;
  FSurface.Commit;
  FDisplay.SyncAndWait;

  FBuffer := FSHM.AllocateShmBuffer(800, 600, TWlShm.TFormat.foXrgb8888, lData, lFd);
  FWidth := 800;
  FHeight := 600;

  // Fill With Green Color
  FillDWord(lData^, FWidth*FHeight, $FFAAFFAA);
  FSurface.Attach(FBuffer, 0,0);
  FSurface.Commit;

  FDisplay.SyncAndWait;



  while not FQuit do
  begin
    //FDisplay.SyncAndWait;
    FDisplay.WaitMessage(100);
    //Sleep(50);
  end;

end;

procedure TWaylandTest.ButtonEvent(Sender: TWlPointer; aSerial: DWord;
  aTime: DWord; aButton: DWord; aState: TWlPointer.TButtonState);
begin
  WriteLn(aButton);
  if (aButton = 272) and (aState = TWlPointer.TButtonState.buPressed) then
    FToplevel.Move(FSeat, aSerial);
end;

procedure TWaylandTest.HandleError(Sender: TWlDisplay; aObjectId: Cardinal;
  aCode: DWord; aMessage: String);
var
  lObj: IWaylandBase;
  lObjName: String;
begin
  lObj := (FDisplay as IWaylandDisplayCore).GetObject(aObjectId);
  if Assigned(lObj) then                           
  else lObjName:='nil';
     lObjName := (lObj as TWaylandBase).ClassName;
  WriteLn(Format('Error: obj(%s)[%d] err: %d, %s', [lObjName, aObjectId,  TWlDisplay.TError(aCode), aMessage]));
end;

procedure TWaylandTest.HandlePing(Sender: TXdgWmBase; aSerial: DWord);
begin
  Sender.Pong(aSerial);
  WriteLn('Ping..Sent Pong');
end;

procedure TWaylandTest.Handle_Registry_Global(Sender: TWlRegistry; aName: DWord;
  aInterface: String; aVersion: DWord);
begin
  WriteLn(aInterface, ' version: ', aVersion);


  if aInterface = 'wl_compositor' then
  begin
    //FCompositor:= TWlCompositor.Create(FDisplay);
    //Sender.Bind(aName,  FCompositor.GetObjectId, aVersion, 0);
    Sender.Bind(aName, aInterface, aVersion, TWlCompositor, FCompositor);
  end;

  if aInterface = 'xdg_wm_base' then
  begin
    //FWM:= TXdgWmBase.Create(FDisplay);
    //Sender.Bind(aName,  FCompositor.GetObjectId, aVersion, 0);
    Sender.Bind(aName, aInterface, aVersion, TXdgWmBase, FWM);
    FWM.OnPing:=@HandlePing;
  end;



  if aInterface = 'wl_shm' then
  begin
    //FSHM:= TWlShm.Create(FDisplay);
    //Sender.Bind(aName,  FCompositor.GetObjectId, aVersion, 0);
    //Sender.Bind(aName, aInterface,aVersion,  FSHM.GetObjectId);
    Sender.Bind(aName, aInterface, aVersion, TWlShm, FSHM);
    FSHM.OnFormat:=@HandleShmFormat;
  end;

  if aInterface = 'wl_seat' then
  begin
    //FSHM:= TWlShm.Create(FDisplay);
    //Sender.Bind(aName,  FCompositor.GetObjectId, aVersion, 0);
    //Sender.Bind(aName, aInterface,aVersion,  FSHM.GetObjectId);
    Sender.Bind(aName, aInterface, aVersion, TWlSeat, FSeat);
    FSeat.OnCapabilities := @SeatCapabilities;
    FSeat.OnName := @SeatName;
  end;

end;

procedure TWaylandTest.HandleShmFormat(Sender: TWlShm; aFormat: TWlShm.TFormat);
begin
  WriteLn(TWlShm.TFormat(aFormat));
end;

procedure TWaylandTest.HandleXDGConfigure(Sender: TXdgSurface; aSerial: DWord);
begin
  WriteLn('XDG configure');
  Sender.AckConfigure(aSerial);
  if FConfigured then
  begin
    FSurface.Attach(FBuffer, 0,0);
    FSurface.Commit;
  end;
  FConfigured:=TRue;;
end;

procedure TWaylandTest.MouseMotion(Sender: TWlPointer; aTime: DWord; aSurfaceX: TWaylandFixed; aSurfaceY: TWaylandFixed);
begin
  //WriteLn(Format('Mouse %d : %d', [aSurfaceX.AsInteger, aSurfaceY.AsInteger]) );
end;

procedure TWaylandTest.SeatCapabilities(Sender: TWlSeat;
  aCapabilities: TwlSeat.TCapability);
var
  lPointer: TWlPointer;
begin
  writeln(aCapabilities.Value, ' <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
  if aCapabilities.Pointer  then
  begin
    lPointer := Sender.GetPointer();
    lPointer.OnButton:=@ButtonEvent;
    lPointer.OnMotion:=@MouseMotion;
  end;

end;

procedure TWaylandTest.SeatName(Sender: TWlSeat; aName: String);
begin

end;

procedure TWaylandTest.ToplevelClose(Sender: TXdgToplevel);
begin
  WriteLn('toplevel close');
  FQuit := True;
end;

procedure TWaylandTest.ToplevelConfigure(Sender: TXdgToplevel; aWidth: Integer;
  aHeight: Integer; aStates: TBytes);
begin
  WriteLn('toplevel configure');




  {//if (aWidth <= FWidth);
  FWidth := 800;
  FHeight := 600;

  // Fill With Green Color
  FillDWord(lData^, FWidth*FHeight, $FFAAFFAA);}
end;

procedure TWaylandTest.ToplevelConfigureBounds(Sender: TXdgToplevel;
  aWidth: Integer; aHeight: Integer);
begin
  Writeln(Format('Screen = %d x %d', [aWidth, aHeight]));
end;

//}

begin

  lProtocol := TWIProtocolNode.Create('/usr/share/wayland/wayland.xml');
  //lProtocol := TWIProtocolNode.Create('/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml');
  //WriteLn(lProtocol.Interfaces.Count);
  lWriter := TWaylandUnitWriter.CreateNew();
  lStringStream := TStringStream.Create('');
  lWriter.WriteUnit(lProtocol, lStringStream);

  WriteLN(lStringStream.DataString);

  lStringStream.SaveToFile('wayland.pas');
 // lStringStream.SaveToFile('xdg_shell.pas');
  //}
  lWaylandTest := TWaylandTest.Create;
  //}
  {lDisplay := TWaylandDisplay.TryCreateConnection;
  //lWConn.QueryInterfaces;

  lRegistrlDisplay.GetRegistry;
  lDisplay.Sync;
      TWaylandCompositor.Create(lDisplay);
  while True do
  lDisplay.WaitMessage(1000);
  //lWConn.Read;
 // Sleep(2000);}
end.

