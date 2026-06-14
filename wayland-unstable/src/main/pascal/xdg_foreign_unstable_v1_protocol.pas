unit xdg_foreign_unstable_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TXdgImportedV1Class = class of TXdgImportedV1;
  { TXdgImportedV1 }
  TXdgImportedV1 = class;

  TXdgImporterV1Class = class of TXdgImporterV1;
  { TXdgImporterV1 }
  TXdgImporterV1 = class;

  TXdgExportedV1Class = class of TXdgExportedV1;
  { TXdgExportedV1 }
  TXdgExportedV1 = class;

  TXdgExporterV1Class = class of TXdgExporterV1;
  { TXdgExporterV1 }
  TXdgExporterV1 = class;

  IXdgExporterV1Listener = interface;

  [TWLIntfAttribute('destroy(),export(no)', '')]
  { TXdgExporterV1 }
  TXdgExporterV1 = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _EXPORT = 1);
  public
    destructor Destroy; override;
    function Export(aSurface: TWlSurface; aClassType: TXdgExportedV1Class = nil): TXdgExportedV1;
  private
    FListeners: array of IXdgExporterV1Listener;
  public
    function AddListener(AIntf: IXdgExporterV1Listener): LongInt;
  end;

  IXdgExporterV1Listener = interface
  ['IXdgExporterV1Listener']
  end;

  IXdgImporterV1Listener = interface;

  [TWLIntfAttribute('destroy(),import(ns)', '')]
  { TXdgImporterV1 }
  TXdgImporterV1 = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _IMPORT = 1);
  public
    destructor Destroy; override;
    function Import(aHandle: String; aClassType: TXdgImportedV1Class = nil): TXdgImportedV1;
  private
    FListeners: array of IXdgImporterV1Listener;
  public
    function AddListener(AIntf: IXdgImporterV1Listener): LongInt;
  end;

  IXdgImporterV1Listener = interface
  ['IXdgImporterV1Listener']
  end;

  IXdgExportedV1Listener = interface;

  [TWLIntfAttribute('destroy()', 'handle(s)')]
  { TXdgExportedV1 }
  TXdgExportedV1 = class(TWaylandBase)
  public type
    THandleEvent = procedure(Sender: TXdgExportedV1; aHandle: String) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0);
    TEvents = (EV_HANDLE = 0);
  private
    FOnHandlePriv: THandleEvent;
  protected
    procedure HandleHandle(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_HANDLE); virtual;
  published
    property OnHandle: THandleEvent read FOnHandlePriv write FOnHandlePriv;
  public
    destructor Destroy; override;
  private
    FListeners: array of IXdgExportedV1Listener;
  public
    function AddListener(AIntf: IXdgExportedV1Listener): LongInt;
  end;

  IXdgExportedV1Listener = interface
  ['IXdgExportedV1Listener']
    procedure xdg_exported_v1_handle(AXdgExportedV1: TXdgExportedV1; aHandle: String);
  end;

  IXdgImportedV1Listener = interface;

  [TWLIntfAttribute('destroy(),set_parent_of(o)', 'destroyed()')]
  { TXdgImportedV1 }
  TXdgImportedV1 = class(TWaylandBase)
  public type
    TDestroyedEvent = procedure(Sender: TXdgImportedV1) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _SET_PARENT_OF = 1);
    TEvents = (EV_DESTROYED = 0);
  private
    FOnDestroyedPriv: TDestroyedEvent;
  protected
    procedure HandleDestroyed(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DESTROYED); virtual;
  published
    property OnDestroyed: TDestroyedEvent read FOnDestroyedPriv write FOnDestroyedPriv;
  public
    destructor Destroy; override;
    procedure SetParentOf(aSurface: TWlSurface);
  private
    FListeners: array of IXdgImportedV1Listener;
  public
    function AddListener(AIntf: IXdgImportedV1Listener): LongInt;
  end;

  IXdgImportedV1Listener = interface
  ['IXdgImportedV1Listener']
    procedure xdg_imported_v1_destroyed(AXdgImportedV1: TXdgImportedV1);
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TXdgExporterV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TXdgExporterV1.GetInterfaceName: String;
begin
  Result := 'zxdg_exporter_v1';
end;

destructor TXdgExporterV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TXdgExporterV1.Export(aSurface: TWlSurface; aClassType: TXdgExportedV1Class = nil): TXdgExportedV1;
begin
  if aClassType = nil then aClassType := TXdgExportedV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._EXPORT), [Result.GetObjectId,aSurface.GetObjectId]);
end;

function TXdgExporterV1.AddListener(AIntf: IXdgExporterV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TXdgImporterV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TXdgImporterV1.GetInterfaceName: String;
begin
  Result := 'zxdg_importer_v1';
end;

destructor TXdgImporterV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TXdgImporterV1.Import(aHandle: String; aClassType: TXdgImportedV1Class = nil): TXdgImportedV1;
begin
  if aClassType = nil then aClassType := TXdgImportedV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._IMPORT), [Result.GetObjectId,aHandle]);
end;

function TXdgImporterV1.AddListener(AIntf: IXdgImporterV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TXdgExportedV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TXdgExportedV1.GetInterfaceName: String;
begin
  Result := 'zxdg_exported_v1';
end;

procedure TXdgExportedV1.HandleHandle(var AMsg: TWaylandEventMessage);
var
  lHandle: String;
  lListenerIdx: Integer;
begin
  lHandle := AMsg.Args.ReadString;
  if Assigned(OnHandle) then OnHandle(Self,lHandle);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].xdg_exported_v1_handle(Self,lHandle);
  AMsg.SetHandled;
end;

destructor TXdgExportedV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TXdgExportedV1.AddListener(AIntf: IXdgExportedV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TXdgImportedV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TXdgImportedV1.GetInterfaceName: String;
begin
  Result := 'zxdg_imported_v1';
end;

procedure TXdgImportedV1.HandleDestroyed(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDestroyed) then OnDestroyed(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].xdg_imported_v1_destroyed(Self);
  AMsg.SetHandled;
end;

destructor TXdgImportedV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TXdgImportedV1.SetParentOf(aSurface: TWlSurface);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_PARENT_OF), [aSurface.GetObjectId]);
end;

function TXdgImportedV1.AddListener(AIntf: IXdgImportedV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.