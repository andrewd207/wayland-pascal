unit xdg_dialog_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland, xdg_shell_protocol;

type
  TXdgDialogV1Class = class of TXdgDialogV1;
  { TXdgDialogV1 }
  TXdgDialogV1 = class;

  TXdgWmDialogV1Class = class of TXdgWmDialogV1;
  { TXdgWmDialogV1 }
  TXdgWmDialogV1 = class;

  IXdgWmDialogV1Listener = interface;

  [TWLIntfAttribute('destroy(),get_xdg_dialog(no)', '')]
  { TXdgWmDialogV1 }
  TXdgWmDialogV1 = class(TWaylandBase)
  public type
    TError = (erAlreadyused = 0);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_XDG_DIALOG = 1);
  public
    destructor Destroy; override;
    function GetXdgDialog(aToplevel: TXdgToplevel; aClassType: TXdgDialogV1Class = nil): TXdgDialogV1;
  private
    FListeners: array of IXdgWmDialogV1Listener;
  public
    function AddListener(AIntf: IXdgWmDialogV1Listener): LongInt;
  end;

  IXdgWmDialogV1Listener = interface
  ['IXdgWmDialogV1Listener']
  end;

  IXdgDialogV1Listener = interface;

  [TWLIntfAttribute('destroy(),set_modal(),unset_modal()', '')]
  { TXdgDialogV1 }
  TXdgDialogV1 = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _SET_MODAL = 1, _UNSET_MODAL = 2);
  public
    destructor Destroy; override;
    procedure SetModal;
    procedure UnsetModal;
  private
    FListeners: array of IXdgDialogV1Listener;
  public
    function AddListener(AIntf: IXdgDialogV1Listener): LongInt;
  end;

  IXdgDialogV1Listener = interface
  ['IXdgDialogV1Listener']
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TXdgWmDialogV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TXdgWmDialogV1.GetInterfaceName: String;
begin
  Result := 'xdg_wm_dialog_v1';
end;

destructor TXdgWmDialogV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TXdgWmDialogV1.GetXdgDialog(aToplevel: TXdgToplevel; aClassType: TXdgDialogV1Class = nil): TXdgDialogV1;
begin
  if aClassType = nil then aClassType := TXdgDialogV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_XDG_DIALOG), [Result.GetObjectId,aToplevel.GetObjectId]);
end;

function TXdgWmDialogV1.AddListener(AIntf: IXdgWmDialogV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TXdgDialogV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TXdgDialogV1.GetInterfaceName: String;
begin
  Result := 'xdg_dialog_v1';
end;

destructor TXdgDialogV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TXdgDialogV1.SetModal;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_MODAL), []);
end;

procedure TXdgDialogV1.UnsetModal;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._UNSET_MODAL), []);
end;

function TXdgDialogV1.AddListener(AIntf: IXdgDialogV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.