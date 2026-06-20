// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

unit wayland_unitwriter;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, wayland_interface_reader, pascal_writer;

type

  { TWaylandUnitWriter }

  TWaylandUnitWriter = class(TVendNode)
  private type
    TTypeVariety = (tvNormal, tvObject, tvNewObject, tvArray, tvEnum, tvFixed, tvFd);
  private

    FOutStream: TStream;
    FUnit: TUnitNode;
    FProtocol: TWIProtocolNode;
    FServerMode: Boolean; // emit server-side bindings (requests in, events out)
    FSEnderUsesBase: Boolean;
    FWrittenInterfaces: TStringList;
    FWritingInterfaces: TStringList;
    FForwardList: TStringList;
    FListenerNodes: TStringList; // class name -> full TInterfaceTypeNode, placed after its class
    FDestructorMapped: Boolean;  // a destructor request already became Pascal Destroy for the current interface
    procedure CollectExternalUnits(AOut: TStringList);
    function GetFullEnumName(AName: String): String;
    function GetArgTypeName(AArg: TWIArgNode; out AKind: TTypeVariety): String;
    function LookupIsBitfield(AThisInterface: TWInterfaceNode; AName: String): Boolean;
    procedure WriteForward(AClassName: String);
    procedure AppendListenerNode(const AClassName: String);
    procedure WriteShmFunctionsForTWlSHM(AClass: TClassNode);
    procedure WriteInterfaceOverides(AInterface: TWInterfaceNode; AClass: TClassNode);
    procedure WriteInterface(AInterface: TWInterfaceNode);
    procedure WriteEvent(AInterface: TWInterfaceNode; aEvent: TWIEventNode; AClass: TClassNode; AProtected, APublished: TVisibilityNode; AListener: TInterfaceTypeNode; const AListenerPrefix: String);
    procedure WriteRequest(AInterface: TWInterfaceNode; ARequest: TWIRequestNode; AClass: TClassNode; AProtected, APublished: TVisibilityNode);
    // --- server-mode emitters (direction is swapped: requests come in and are
    //     dispatched to a handler interface; events go out and are marshalled) ---
    procedure WriteServerInterface(AInterface: TWInterfaceNode);
    procedure WriteServerRequestHandler(AInterface: TWInterfaceNode; ARequest: TWIRequestNode; AClass: TClassNode; AProtected, APublished: TVisibilityNode; AListener: TInterfaceTypeNode; const AListenerPrefix: String);
    procedure WriteServerEvent(AInterface: TWInterfaceNode; AEvent: TWIEventNode; AClass: TClassNode);
  public
    // raw interface name (e.g. 'xdg_toplevel') -> defining unit name (e.g.
    // 'xdg_shell_protocol'). Core wl_* interfaces map to 'wayland'. Set by the
    // caller before WriteUnit so cross-protocol references emit a uses clause.
    FInterfaceUnitMap: TStringList;
    // overrides the generated unit name; '' falls back to the protocol name.
    // AServerMode emits the server-side binding (TWaylandServerResource subclasses
    // built on wayland_server_core) instead of the client proxies.
    procedure WriteUnit(AProtocol: TWIProtocolNode; AStream: TStream; ASenderUsesBase: Boolean = False; const AUnitName: String = ''; AServerMode: Boolean = False);
  end;

implementation

{ TWaylandUnitWriter }

// Wayland prefixes unstable/experimental interfaces with a leading 'z'
// (zwp_, zxdg_, zwlr_, zext_, ...). Drop it so the generated class names match
// the convention used elsewhere, e.g. zwp_linux_dmabuf_v1 -> TWpLinuxDmabufV1.
function StripZPrefix(const AInterfaceName: String): String;
begin
  Result := AInterfaceName;
  if (Length(Result) > 1) and ((Result[1] = 'z') or (Result[1] = 'Z')) then
    Delete(Result, 1, 1);
end;

// True if APascalName would clash with a Pascal reserved word or a base-class /
// constructor identifier when used as a method name. Server events become public
// methods named after the event, so reserved words like 'type'/'begin'/'end'
// (e.g. tablet / pointer-gesture events) and base methods must be suffixed.
function NeedsMethodSuffix(const APascalName: String): Boolean;
const
  Reserved: array[0..57] of String = (
    'absolute','and','array','asm','begin','case','const','constructor','destructor',
    'div','do','downto','else','end','file','for','function','goto','if',
    'implementation','in','inherited','inline','interface','label','mod','nil','not',
    'object','of','on','operator','or','packed','procedure','program','record',
    'repeat','set','shl','shr','string','then','to','type','unit','until','uses',
    'var','while','with','xor','out','property','raise','is','as','class');
  // base-class / constructor identifiers a method name must not shadow
  BaseIdents: array[0..4] of String = ('create','destroy','free','dispatch','getobjectid');
var
  i: Integer;
begin
  Result := False;
  for i := Low(Reserved) to High(Reserved) do
    if SameText(APascalName, Reserved[i]) then Exit(True);
  for i := Low(BaseIdents) to High(BaseIdents) do
    if SameText(APascalName, BaseIdents[i]) then Exit(True);
end;

// Walk every request/event arg of this protocol. Any interface or qualified-
// enum reference that resolves to a DIFFERENT unit than the one being written
// is collected so WriteUnit can emit the corresponding uses clause. 'wayland'
// is added by WriteUnit unconditionally and skipped here.
procedure TWaylandUnitWriter.CollectExternalUnits(AOut: TStringList);
var
  lLocal: TStringList;
  i, j, k: Integer;
  lIface: TWInterfaceNode;

  procedure ConsiderRef(const ARawIface: String);
  var
    lUnit, lCoreUnit: String;
  begin
    if (ARawIface = '') or (FInterfaceUnitMap = nil) then Exit;
    if lLocal.IndexOf(ARawIface) <> -1 then Exit; // defined in this protocol
    lUnit := FInterfaceUnitMap.Values[ARawIface];
    // The core unit is added to the uses clause unconditionally (see WriteUnit),
    // so skip it here. Its name depends on the mode.
    if FServerMode then lCoreUnit := 'wayland_server' else lCoreUnit := 'wayland';
    if (lUnit = '') or (lUnit = lCoreUnit) or (lUnit = FUnit.Name) then Exit;
    if AOut.IndexOf(lUnit) = -1 then AOut.Add(lUnit);
  end;

  procedure ConsiderArgs(AArgs: TWIArgList);
  var
    a: Integer;
    lArg: TWIArgNode;
    lDot: TAnsiStringArray;
  begin
    for a := 0 to AArgs.Count-1 do
    begin
      lArg := AArgs.Items[a];
      ConsiderRef(lArg.Interface_);
      if lArg.Enum <> '' then
      begin
        lDot := lArg.Enum.Split(['.']);
        if Length(lDot) > 1 then ConsiderRef(lDot[0]);
      end;
    end;
  end;

begin
  lLocal := TStringList.Create;
  try
    for i := 0 to FProtocol.Interfaces.Count-1 do
      lLocal.Add(FProtocol.Interfaces.Items[i].Name);
    for i := 0 to FProtocol.Interfaces.Count-1 do
    begin
      lIface := FProtocol.Interfaces.Items[i];
      for j := 0 to lIface.Requests.Count-1 do
        ConsiderArgs(lIface.Requests.Items[j].Args);
      for k := 0 to lIface.Events.Count-1 do
        ConsiderArgs(lIface.Events.Items[k].Args);
    end;
  finally
    lLocal.Free;
  end;
end;

function TWaylandUnitWriter.GetFullEnumName(AName: String): String;
var
  lStrings: TStringList;
  i: Integer;
begin
  lStrings := TStringList.Create;
  lStrings.AddStrings(AName.Split('.'));
  // the first segment of a qualified enum ref is an interface name (e.g.
  // zwp_foo.bar) -> strip its z so it matches the class name TWpFoo.TBar
  if lStrings.Count > 1 then
    lStrings[0] := StripZPrefix(lStrings[0]);
  for i := 0 to lStrings.Count-1 do
    lStrings[i] := TClassNode.Pascalify(lStrings[i], True);

  lStrings.Delimiter:='.';
  Result := lStrings.DelimitedText;
  lStrings.Free;
end;

function TWaylandUnitWriter.GetArgTypeName(AArg: TWIArgNode; out
  AKind: TTypeVariety): String;
begin
  AKind:=tvNormal;
  if AArg.Enum <> '' then AKind:= tvEnum;
  case AArg.Type_ of
      'uint'    : Result := 'DWord';
      'int'     : Result := 'Integer';
      'string'  : Result := 'String';
      'new_id'  :
        begin
          if AArg.Interface_ = '' then
            Result := 'DWord'
          else
            Result := TClassNode.Pascalify(StripZPrefix(AArg.Interface_), True, 'T');
          AKind:=tvNewObject;
        end;
      'fd'      :
        begin
          Result := 'Integer';
          AKind := tvFd;
        end;
      'fixed'   :
        begin
          Result := 'TWaylandFixed';
          AKind := tvFixed;
        end;
      'object'  :
        begin
          if AArg.Name = 'object_id' then
            Result := 'Cardinal'
          else
          begin
            Result := TClassNode.Pascalify(StripZPrefix(AArg.Interface_), True, 'T');
            AKind:=tvObject
          end;
        end;
      'array':
        begin
          Result := 'TBytes';
          AKind:=tvArray;
        end
  else
    raise Exception.Create('Unhandled type: '+AArg.Type_);
  end;
  if AKind = tvEnum then
    Result:=GetFullEnumName(AArg.Enum); // perhaps add forward to unit if not added yet?

end;

function TWaylandUnitWriter.LookupIsBitfield(AThisInterface: TWInterfaceNode;
  AName: String): Boolean;
var
  lSplit: TAnsiStringArray;
  i: Integer;
begin
  Result := False;
  lSplit := AName.Split(['.']);
  if Length(lSplit) > 1 then
  begin
    for i := 0 to FProtocol.Interfaces.Count-1 do
    begin
      if FProtocol.Interfaces.Items[i].Name = lSplit[0] then
      begin
        AThisInterface := FProtocol.Interfaces.Items[i];
        Break;
      end;
    end;
    AName:=lSplit[1];
  end;

  for i := 0 to AThisInterface.Enums.Count-1 do
  begin
    if AThisInterface.Enums.Items[i].Name = AName then
    begin
      Result := AThisInterface.Enums.Items[i].IsBitfield;
      Break;
    end;
  end;
end;

procedure TWaylandUnitWriter.WriteForward(AClassName: String);
var
  lForward: TClassNode;
begin
  if FForwardList.IndexOf(AClassName) <> -1 then Exit;
  FUnit.InterfaceNode.WantTypeSection.AddClassType(AClassName, '', True);
  FUnit.InterfaceNode.WantTypeSection.AddClassOfNode(AClassName, True);
  FForwardList.Add(AClassName);
end;

procedure TWaylandUnitWriter.AppendListenerNode(const AClassName: String);
var
  lIdx: Integer;
begin
  // emit the full I<Class>Listener decl right after its class body, so the
  // class's nested enum types are visible to typed listener-method params
  lIdx := FListenerNodes.IndexOf(AClassName);
  if lIdx <> -1 then
  begin
    FUnit.InterfaceNode.WantTypeSection.List.Add(TInterfaceTypeNode(FListenerNodes.Objects[lIdx]));
    FListenerNodes.Delete(lIdx);
  end;
end;

procedure TWaylandUnitWriter.WriteShmFunctionsForTWlSHM(AClass: TClassNode);
var
  lPublic: TVisibilityNode;
  lIntf: TRoutineNode;
  lImplementation: TRoutineImplNode;
begin
  lPublic := AClass.WantVisibiltySection(vcPublic, True);
  lIntf := lPublic.AddRoutine(rtFunc, 'AllocateShmBuffer', 'TWlBuffer');
  lIntf.AddParameter('aWidth', 'Integer');
  lIntf.AddParameter('aHeight', 'Integer');
  lIntf.AddParameter('aFormat', 'TWlShm.TFormat');
  lIntf.AddParameter('out aData', 'Pointer');
  lIntf.AddParameter('out fd', 'Integer');

  lImplementation := FUnit.ImplentationNode.AddRoutineImplementation(lIntf);
  lImplementation.BeginEnd.AddCodeLine('Result := Create_shm_buffer(Self, aWidth, aHeight, aFormat, aData, fd);');

  lIntf := lPublic.AddRoutine(rtFunc, 'AllocateShmPool', 'TWlShmPool');
  lIntf.AddParameter('aSize', 'Integer');
  lIntf.AddParameter('aOutData', 'PPointer');
  lIntf.AddParameter('aOutFd', 'PInteger');

  lImplementation := FUnit.ImplentationNode.AddRoutineImplementation(lIntf);
  lImplementation.BeginEnd.AddCodeLine('Result := Create_shm_pool(Self, aSize, aOutData, aOutFd);');
end;

procedure TWaylandUnitWriter.WriteInterfaceOverides(
  AInterface: TWInterfaceNode; AClass: TClassNode);
var
  lProtected: TVisibilityNode;
  lInterfaceVersionFunc, lInterfaceNameFunc: TRoutineNode;
  lVersionImpl, lNameImpl: TRoutineImplNode;
begin
  lProtected := ACLass.WantVisibiltySection(vcProtected, True);

  lInterfaceVersionFunc := lProtected.AddRoutine(rtFunc, 'GetInterfaceVersion', 'Integer');
  lInterfaceNameFunc := lProtected.AddRoutine(rtFunc, 'GetInterfaceName', 'String');

  lInterfaceVersionFunc.RoutineSpecialType:=rstClassMethod;
  lInterfaceNameFunc.RoutineSpecialType:=rstClassMethod;
  lInterfaceVersionFunc.IsOverride:=True;
  lInterfaceNameFunc.IsOverride:=True;

  lVersionImpl := FUnit.ImplentationNode.AddRoutineImplementation(lInterfaceVersionFunc);
  lNameImpl := FUnit.ImplentationNode.AddRoutineImplementation(lInterfaceNameFunc);

  lVersionImpl.BeginEnd.AddCodeLine(Format('Result := %d;', [AInterface.Version]));
  lNameImpl.BeginEnd.AddCodeLine(Format('Result := ''%s'';', [AInterface.Name]));
end;

procedure TWaylandUnitWriter.WriteInterface(AInterface: TWInterfaceNode);
var
  lClassName, lParentClass: String;
  lClass: TClassNode;
  lProtected, lPublished, lPrivate, lPublic, lBitPublic,
    lBitPrivate: TVisibilityNode;
  //lConsts: TConstSectionNode;
  lRequestConst, lEventConst, lIntfAttrArg: TNamedNode;
  i, x: Integer;
  lPublicType, lTypeSection: TTypeSectionNode;
  lEnum, lRequestEnums: TEnumNode;
  lEntry: TWIEntry;
  lWritingIndex: Integer;
  lIntfEnum: TWIEnumNode;
  lRoutine: TRoutineNode;
  lRoutineImpl: TRoutineImplNode;
  lObject: TObjectNode;
  lIntfAttr: TAttributeNode;
  lIntfAttrRequests: TStringList;
  lIntfAttrEvents: TStringList;
  lListener: TInterfaceTypeNode;
  lListenerName, lListenerPrefix: String;
  lAddListener: TRoutineNode;
  lAddListenerImpl: TRoutineImplNode;
begin
  if FWrittenInterfaces.IndexOf(AInterface.Name) <> -1 then
      Exit; // already written

  lClassName := TClassNode.Pascalify(StripZPrefix(AInterface.Name), True);
  lListenerName := 'I' + Copy(lClassName, 2, MaxInt) + 'Listener';
  lListenerPrefix := StripZPrefix(AInterface.Name);

  if FWritingInterfaces.IndexOf(AInterface.Name) <> -1 then
  begin
    lWritingIndex := FWritingInterfaces.IndexOf(AInterface.Name);
    lClass := TClassNode(FWritingInterfaces.Objects[lWritingIndex]);
    if FForwardList.IndexOf(lClassName) = -1 then
    begin
      FUnit.InterfaceNode.WantTypeSection.AddClassOfNode(lClassName);
      FForwardList.Add(lClassName);
    end;
    FUnit.InterfaceNode.WantTypeSection.List.add(lClass);
    AppendListenerNode(lClassName);
    FWritingInterfaces.Delete(lWritingIndex);
    FWrittenInterfaces.Add(AInterface.Name);
    Exit;
  end;

  lWritingIndex := FWritingInterfaces.Add(AInterface.Name);

  if AInterface.Name = 'wl_display' then
    lParentClass := 'TWaylandDisplayBase'
  else
    lParentClass := 'TWaylandBase';


  lIntfAttr := TAttributeNode.CreateNew(nil);
  lIntfAttr.IndentAdjust:=2;
  lIntfAttr.Name:='TWLIntfAttribute';
  lIntfAttrRequests := TStringList.Create;
  lIntfAttrEvents := TStringList.Create;
  lClass := TClassNode.CreateNew(nil); // don't add it yet
  lClass.Name:=lClassName;
  lClass.AncestorClass := TClassNode.CreateNew(lClass);
  lClass.AncestorClass.Name:=lParentClass;
  //lClass := FUnit.InterfaceNode.WantTypeSection.AddClassType(lClassName, lParentClass);

  // Listener interface (matches the libwayland-bindings I<Class>Listener).
  // Forward-declare the class so the listener methods can reference it, and
  // forward-declare the listener itself so the class's AddListener can take it.
  // The FULL listener decl is emitted AFTER the class body (see the add-paths
  // below) so the class's nested enum types are in scope for typed params.
  WriteForward(lClassName);
  FUnit.InterfaceNode.WantTypeSection.AddInterfaceType(lListenerName).IsForward := True;
  lListener := TInterfaceTypeNode.CreateNew(FUnit.InterfaceNode.WantTypeSection);
  lListener.Name := lListenerName;
  lListener.IID := lListenerName;
  FListenerNodes.AddObject(lClassName, lListener);

  // functions to return the version
  WriteInterfaceOverides(AInterface, lClass);

  FWritingInterfaces.Objects[lWritingIndex] := lClass;
  // Create Enums
  if AInterface.Enums.Count > 0 then
  begin
    lPublicType := lClass.FindFirstPublicType(True);
    for i := 0 to AInterface.Enums.Count-1 do
    begin
      lIntfEnum := AInterface.Enums.Items[i];
      if not lIntfEnum.IsBitfield then
      begin
        lEnum := lPublicType.AddEnumType(TClassNode.Pascalify(lIntfEnum.Name, True));
        for x := 0 to lIntfEnum.Entries.Count -1 do
        begin
          lEntry := lIntfEnum.Entries.Items[x];
          lEnum.AddValue(Format('%s = %d', [Copy(TClassNode.Pascalify(lEntry.Name, True), 2, MaxInt), lEntry.Value]));
        end;
      end
      else
      begin
        lObject := lPublicType.AddObjectType(TClassNode.Pascalify(lIntfEnum.Name, True), 'TBitfield');
        lBitPublic := lObject.WantVisibiltySection(vcPublic, True);
        for x := 0 to lIntfEnum.Entries.Count -1 do
        begin
          lEntry := lIntfEnum.Entries.Items[x];
          lBitPublic.AddProperty(TClassNode.Pascalify(lEntry.Name, True, ''), 'Boolean', 'GetValue', False, 'SetValue').Index:=lEntry.Value.ToString;
          //lEnum.AddValue(Format('%s = %d', [Copy(TClassNode.Pascalify(lEntry.Name, True), 2, MaxInt), lEntry.Value]));
        end;
      end;
    end;
  end;

  // Create Consts
  lProtected := lClass.AddSection(vcProtected);
  //lConsts := lProtected.;
  lTypeSection := lProtected.AddTypeSection(True);
  if AInterface.Requests.Count > 0 then
    lRequestEnums := lTypeSection.AddEnumType('TRequests');
  for i := 0 to AInterface.Requests.Count-1 do
  begin
    //lRequestConst:=lConsts.List.AddItem;
    lIntfAttrRequests.Add(Format('%s(%s)', [AInterface.Requests.Items[i].Name, AInterface.Requests.Items[i].Args.Signature]));
    lRequestEnums.AddValue(Format('_%s = %d',  [UpperCase(AInterface.Requests.Items[i].Name), i]), False);
    //lRequestConst.Name:=Format('_%s = %d;',  [UpperCase(AInterface.Requests.Items[i].Name), i]);
  end;
  if AInterface.Events.Count > 0 then
    lEnum := lTypeSection.AddEnumType('TEvents');
  for i := 0 to AInterface.Events.Count-1 do
  begin
    lIntfAttrEvents.Add(Format('%s(%s)', [AInterface.Events.Items[i].Name, AInterface.Events.Items[i].Args.Signature]));
    //lEventConst:=lConsts.List.AddItem;
    //lEventConst.Name:=Format('EV_%s = %d;',  [UpperCase(AInterface.Events.Items[i].Name), i]);
    lEnum.AddValue(Format('EV_%s = %d',  [UpperCase(AInterface.Events.Items[i].Name), i]), False);
  end;

  // Create Events
  if AInterface.Events.Count > 0 then
  begin
    lPrivate := lClass.AddSection(vcPrivate);
    lProtected := lClass.AddSection(vcProtected);
    lPublished := lClass.AddSection(vcPublished);
    for i := 0 to AInterface.Events.Count-1 do
    begin
      WriteEvent(AInterface, AInterface.Events.Items[i], lClass, lProtected, lPublished, lListener, lListenerPrefix);
    end;
  end;

  // Create "requests"
  FDestructorMapped := False; // only one destructor request may become Pascal Destroy
  for i := 0 to AInterface.Requests.Count-1 do
  begin
    WriteRequest(AInterface, AInterface.Requests.Items[i], lClass, lProtected, lPublished);
  end;

  // Listener storage + AddListener. Unlike libwayland (one listener per proxy),
  // this backs the listeners with a list and AddListener appends, so an object
  // can have multiple listeners; events fan out to all of them (see WriteEvent).
  lClass.AddSection(vcPrivate).AddVariable('FListeners', 'array of ' + lListenerName);
  lAddListener := lClass.AddSection(vcPublic).AddRoutine(rtFunc, 'AddListener', 'LongInt');
  lAddListener.AddParameter('AIntf', lListenerName);
  lAddListenerImpl := FUnit.ImplentationNode.AddRoutineImplementation(lAddListener);
  lAddListenerImpl.BeginEnd.AddCodeLine('SetLength(FListeners, Length(FListeners)+1);');
  lAddListenerImpl.BeginEnd.AddCodeLine('FListeners[High(FListeners)] := AIntf;');
  lAddListenerImpl.BeginEnd.AddCodeLine('Result := 0;');
  if AInterface.Name = 'wl_shm' then
    WriteShmFunctionsForTWlSHM(lClass);


  if AInterface.Name = 'wl_callback' then
  begin
    lClass.WantVisibiltySection(vcPublic, True).AddPropertyReadOnly('IsDone', 'Boolean', True);
  end;

  if FWrittenInterfaces.IndexOf(AInterface.Name) = -1 then
  begin
    // finally add at the end. to allow needed types to bewritten first
    if FForwardList.IndexOf(lClassName) = -1 then
    begin
      FUnit.InterfaceNode.WantTypeSection.AddClassOfNode(lClassName);
      FForwardList.Add(lClassName);
    end;
    lIntfAttrArg := TNamedNode(lIntfAttr.List.AddItem);
    lIntfAttrArg.Name:=QuotedStr(lIntfAttrRequests.CommaText);
    lIntfAttrArg := TNamedNode(lIntfAttr.List.AddItem);
    lIntfAttrArg.Name:=QuotedStr(lIntfAttrEvents.CommaText);
    FUnit.InterfaceNode.WantTypeSection.List.add(lIntfAttr);
    FUnit.InterfaceNode.WantTypeSection.List.add(lClass);
    AppendListenerNode(lClassName);
    FWritingInterfaces.Delete(lWritingIndex);
    FWrittenInterfaces.Add(AInterface.Name);
  end;
  FreeAndNil(lIntfAttrEvents);
  FreeAndNil(lIntfAttrRequests);
end;

procedure TWaylandUnitWriter.WriteEvent(AInterface: TWInterfaceNode;
  aEvent: TWIEventNode; AClass: TClassNode; AProtected,
  APublished: TVisibilityNode; AListener: TInterfaceTypeNode;
  const AListenerPrefix: String);
var
  lEventName, lName, lType, lTypeName, lReadArg, lCallArgs, lTypeCast,
    lLookingFor, lListenerMethodName: String;
  lInterfaceProc, lProcType, lListenerMethod: TRoutineNode;
  lPublicType: TTypeSectionNode;
  i, x: Integer;
  lEventArg: TWIArgNode;
  lKind: TTypeVariety;
  lImplProc: TRoutineImplNode;
  lVar: TVarSectionNode;
  lBeginEnd: TBeginEndNode;
  lVarDecl: TParameterNode;
  lAssign, lCall, lSetHandled: TNamedNode;
  lProperty: TPropertyNode;
  lInterfaceXML: TWInterfaceNode;
begin
  lEventName := 'Handle'+Copy(TClassNode.Pascalify(aEvent.Name, True), 2, MaxInt);
  lInterfaceProc := AProtected.AddRoutine(rtProc, lEventName, '');
  lInterfaceProc.RoutineSpecialType:=rstMethod;
  lInterfaceProc.IsVirtual:=True;
  lInterfaceProc.AddParameter('var AMsg', 'TWaylandEventMessage');
  lInterfaceProc.Message:= 'Ord(TEvents.EV_'+UpperCase(aEvent.Name)+')';

  // add procedure var type that matches the args    : do_something becomes TDoSomethingEvent = procedure(args)of object
  lPublicType := AClass.FindFirstPublicType(True);
  lProcType := lPublicType.AddProcedureType(TClassNode.Pascalify(aEvent.Name+'_Event', true), rtProc, True);

  if FSenderUsesBase then
    lProcType.AddParameter('Sender', 'TWaylandBase')
  else
    lProcType.AddParameter('Sender', AClass.Name);

  // matching method on the listener interface: <iface>_<event>(A<Class>, args...)
  lListenerMethodName := AListenerPrefix + '_' + aEvent.Name;
  lListenerMethod := AListener.AddMethod(rtProc, lListenerMethodName);
  lListenerMethod.AddParameter('A'+Copy(AClass.Name, 2, MaxInt), AClass.Name);

  for i := 0 to aEvent.Args.Count-1 do
  begin
    lEventArg := aEvent.Args.Items[i];
    lName := TClassNode.Pascalify(lEventArg.Name, True, 'a');
    lTypeName := GetArgTypeName(lEventArg, lKind); // if lIsEnum add forward?
    // Event fds arrive out-of-band; deliver them as a ready-to-use stream (the
    // message owns it). Request fd args stay Integer (the caller supplies the fd).
    if lKind = tvFd then
      lTypeName := 'TWaylandFdStream';
    lProcType.AddParameter(lName, lTypeName);
    // The listener interface is a top-level type, so a same-interface enum/
    // bitfield type (nested in the class, hence unqualified) must be qualified
    // with the class name. Cross-interface refs already contain a '.'.
    if (lKind = tvEnum) and (Pos('.', lTypeName) = 0) then
      lListenerMethod.AddParameter(lName, AClass.Name + '.' + lTypeName)
    else
      lListenerMethod.AddParameter(lName, lTypeName);
    if (lEventArg.Interface_ <> '') or (Pos('.', lEventArg.Enum) > 0 ) then
    begin
      lLookingFor := lEventArg.Interface_;
      if lLookingFor = '' then
        lLookingFor:=lEventArg.Enum.Split(['.'])[0];
      for x := 0 to FProtocol.Interfaces.Count-1 do
      begin
        lInterfaceXML := FProtocol.Interfaces.Items[x];
        if lInterfaceXML.Name = lLookingFor then
        begin
          if lEventArg.Interface_ <> '' then
            WriteForward(lTypeName)
          else
            WriteInterface(lInterfaceXML);
          Break;
        end;
      end;
    end;
  end;

  // add property with procedure var    // property OnDoSomething: TDoDomethingEvent read FOnDoSomething write ...
  lProperty := APublished.AddPropertyRW('On'+TClassNode.Pascalify(aEvent.Name, True, ''), lProcType.Name, True);
  // add implementation procedure for lInterfaceProc that calls the procedure var

  lImplProc := TRoutineImplNode.CreateNew(FUnit.ImplentationNode.Declarations);
  FUnit.ImplentationNode.Declarations.Add(lImplProc);
  lImplProc.RoutineDeclaration:= lInterfaceProc;
  lVar := lImplProc.VarSection;
  lBeginEnd := lImplProc.BeginEnd;
  lCallArgs := 'Self,';
  if aEvent.Args.Count > 0 then
  begin

    for i := 0 to aEvent.Args.Count-1 do
    begin
      lEventArg := aEvent.Args.Items[i];
      lName := TClassNode.Pascalify(lEventArg.Name, True, 'l');
      lTypeName := GetArgTypeName(lEventArg, lKind); // if lIsEnum add forward?
      if lKind = tvFd then
        lTypeName := 'TWaylandFdStream'; // event fds are delivered as a stream
      lVarDecl := TParameterNode.CreateNew(lVar);
      lCallArgs+=lName+',';
      lVar.List.Add(lVarDecl);
      lVarDecl.Name:=lName;
      lVarDecl.Value := TNamedNode.CreateNew(lVarDecl);
      lVarDecl.Value.Name:=lTypeName;
      lAssign := TNamedNode.CreateNew(lBeginEnd.List);
      lBeginEnd.List.Add(lAssign);
      case lEventArg.Type_ of
        'uint'    : lReadArg := 'ReadDWord';
        'int'     : lReadArg := 'ReadInteger';
        'string'  : lReadArg := 'ReadString';
        'object'  : lReadArg := 'ReadDWord';
        'fd'      : lReadArg := 'ReadInteger';
        'new_id'  : lReadArg := 'ReadDWord';
        'fixed'   : lReadArg := 'ReadDWord';
        'array'   : lReadArg := 'ReadBlob';
      else
        raise Exception.Create('unsupported type as argument: ' +lEventArg.Type_);
      end;

      case lKind of
        tvNormal:
          begin
            lTypeCast:='';
          end;
        tvFd:
          begin
            lTypeCast:='';  // fd handled specially below: read from NextFd, not the body
          end;

        tvEnum:
          begin
            lTypeCast := lTypeName+'(';
            lReadArg+=')';
          end;
        tvObject:
          begin
            lTypeCast := '(Connection.GetObject(';
            lReadArg+=') as '+lTypename+')';
          end;
        tvFixed:
          begin
            lTypeCast := 'TWaylandFixed.FromFixed(';
            lReadArg+=')';
          end;
        tvArray:
          begin
            lTypeCast := '';
          end;
        tvNewObject:
          begin
            // ok this is wierd. do we use our object id or set the one here?
            lTypeCast := lTypeName+'.Create(Connection, nil, ';
            lReadArg+=')';
          end
      else
        raise Exception.Create('Unhandled type: '+ lEventArg.Interface_)
      end;
      // fds travel out-of-band (SCM_RIGHTS), not in the message body, so they are
      // taken from the message's fd queue (as a stream) and occupy no bytes in
      // Args. Reading them from Args would over-run the body and mis-align the
      // args that follow.
      if lKind = tvFd then
        lAssign.Name:=Format('%s := AMsg.NextFdStream;', [lName])
      else
        lAssign.Name:=Format('%s := %sAMsg.Args.%s;', [lName, lTypeCast, lReadArg]);
      lTypeCast:='';
    end; // for
  end;
  lCallArgs:='('+Copy(lCallArgs, 1, Length(lCallArgs)-1)+')'; // trim comma
  lCall := TNamedNode.CreateNew(lBeginEnd.List);
  lBeginEnd.List.Add(lCall);
  lCall.Name:= Format('if Assigned(%s) then %s%s;', [lProperty.Name, lProperty.Name, lCallArgs]);
  // fan out to every registered listener (the native binding allows more than
  // one; libwayland/waylandbinding only support a single listener per object)
  lImplProc.AddVariable('lListenerIdx', 'Integer');
  lBeginEnd.AddCodeLine(Format('for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].%s%s;',
    [lListenerMethodName, lCallArgs]));
  lSetHandled := TNamedNode.CreateNew(lBeginEnd.List);
  lBeginEnd.List.Add(lSetHandled);
  lSetHandled.Name:='AMsg.SetHandled;';
  if AInterface.Name = 'wl_callback' then
    lBeginEnd.AddCodeLine('FIsDonePriv := True;');
end;

procedure TWaylandUnitWriter.WriteRequest(AInterface: TWInterfaceNode;
  ARequest: TWIRequestNode; AClass: TClassNode; AProtected,
  APublished: TVisibilityNode);
var
  lReturnsType: Boolean;
  lPublic: TVisibilityNode;
  i, x: Integer;
  lIntfProcType: TRoutineType = rtProc;
  lMapToDestructor: Boolean;
  lArg, lReturnArg: TWIArgNode;
  lIntfProc: TRoutineNode;
  lType: TTypeVariety;
  lTypeName, lParams, lName, lRequestConst, lLookingFor, lFd: String;
  lImplProc: TRoutineImplNode;
  lInterfaceXML: TWInterfaceNode;
begin
  lReturnArg := nil;
  if (ARequest.Args.Count > 0) and ((ARequest.Args.Items[0].Type_ = 'new_id') and (ARequest.Args.Items[0].Interface_ <> ''))then
  begin
    lReturnArg := ARequest.Args.Items[0];
    lIntfProcType := rtFunc;
  end;

  // Map a request to the Pascal destructor ONLY when it has no args -- the
  // classic parameterless destructor (wl_surface.destroy etc.), so obj.Free
  // sends the destroy request. A destructor-type request that also returns a
  // new_id or carries args (e.g. color-management's "create", which consumes
  // the creator AND produces an image description) cannot be a Pascal
  // destructor (those take no params / return nothing); emit it as a normal
  // method instead.
  lMapToDestructor := (ARequest.Type_ = 'destructor') and (ARequest.Args.Count = 0)
                      and (not FDestructorMapped);
  if lMapToDestructor then
    FDestructorMapped := True;

  lPublic := AClass.WantVisibiltySection(vcPublic, True);
  lName := TClassNode.Pascalify(ARequest.Name, True, '');
  // A request whose Pascal name collides with a TObject / constructor identifier
  // (e.g. a protocol request literally named "create", as in
  // zwp_linux_buffer_params_v1) would shadow the constructor and break
  // aClass.Create(...) calls. Suffix such names with '_'. (requests mapped to
  // the Pascal destructor are intentionally named Destroy below and exempt.)
  if (not lMapToDestructor)
     and (SameText(lName, 'Create') or SameText(lName, 'Destroy')
          or SameText(lName, 'Free') or SameText(lName, 'Dispatch')) then
    lName := lName + '_';
  lIntfProc := lPublic.AddRoutine(lIntfProcType, lName, '');
  if lMapToDestructor then
  begin
    lIntfProc.RoutineType:=rtDestructor;
    lIntfProc.Name:='Destroy'; // some are release etc.
    lIntfProc.IsOverride:=True;
  end;


  if Assigned(lReturnArg) then
  begin
    lIntfProc.SetReturnValue(GetArgTypeName(lReturnArg, lType));
    if not (lType in [tvNewObject]) then
      Raise Exception.Create('Wrong kind of type for new_id');
  end;

  if (ARequest.Name = 'bind') and (AClass.Name = 'TWlRegistry') then
  begin
    lIntfProc.AddParameter('aInterfaceIndex', 'DWord');
    lIntfProc.AddParameter('aInterfaceName', 'String');
    lIntfProc.AddParameter('aInterfaceVersion', 'Integer');
    lIntfProc.AddParameter('aClassType', 'TWaylandBaseClass');
    lIntfProc.AddParameter('var aOutObject{aClassType}', '').IsUntyped:=True;

    lImplProc := FUnit.ImplentationNode.AddRoutineImplementation(lIntfProc);
    lImplProc.AddVariable('lVersion', 'Integer');

    lImplProc.BeginEnd.AddCodeLine('lVersion := aClassType.GetInterfaceVersion;');
    lImplProc.BeginEnd.AddCodeLine('if lVersion > aInterfaceVersion then');
    lImplProc.BeginEnd.AddCodeLine('  lVersion := aInterfaceVersion;');
    lImplProc.BeginEnd.AddCodeLine(Format('if aInterfaceName <> AClassType.GetInterfaceName then', []));
    lImplProc.BeginEnd.AddCodeLine('  raise Exception.CreateFmt(''interface names must match: %s != %s'', [TWaylandBase(aOutObject).GetInterfaceName, aInterfaceName]);');
    lImplProc.BeginEnd.AddCodeLine(Format('TWaylandBase(aOutObject) := aClassType.Create(Connection);', []));
    lParams:='aInterfaceIndex, TWaylandBase(aOutObject).GetInterfaceName, lVersion,TWaylandBase(aOutObject).GetObjectId';
    lImplProc.BeginEnd.AddCodeLine(Format('Connection.SendRequest(GetObjectId, Ord(TRequests._BIND), [%s]);', [lParams]));
    lImplProc.BeginEnd.AddCodeLine('TWaylandBase(aOutObject).SetProtocolVersion(lVersion);');
                                    ;

    exit;
  end
  else
  begin
    for i := 0 to ARequest.Args.Count-1 do
    begin
      lArg := ARequest.Args.Items[i];
      lName := TClassNode.Pascalify(lArg.Name, True, 'a');
      lTypeName := GetArgTypeName(lArg, lType);
      if (i > 0) or not (lType in [tvNewObject]) then // ignore NewObject if it's the first parameter
      begin
        lIntfProc.AddParameter(lName, lTypeName);
      end;
      if (lArg.Interface_ <> '') or (Pos('.', lArg.Enum) > 0 ) then
      begin
        lLookingFor := lArg.Interface_;
        if lLookingFor = '' then
          lLookingFor:=lArg.Enum.Split(['.'])[0];
        for x := 0 to FProtocol.Interfaces.Count-1 do
        begin
          lInterfaceXML := FProtocol.Interfaces.Items[x];
          if lInterfaceXML.Name = lLookingFor then
          begin
            if lArg.Interface_ <> '' then
              WriteForward(lTypeName)
            else
              WriteInterface(lInterfaceXML);
            Break;
          end;
        end;
      end;
    end;

  end;

  // finally add a special class to allow contructing custom classes
  if Assigned(lReturnArg) then
  begin
    lName := 'aClassType';
    lTypeName := lIntfProc.ReturnValue.Name+'Class = nil';
    lIntfProc.AddParameter(lName, lTypeName);
  end;


  // now write the implementation
  lImplProc := TRoutineImplNode.CreateNew(FUnit.ImplentationNode.Declarations);
  FUnit.ImplentationNode.Declarations.Add(lImplProc);
  lImplProc.RoutineDeclaration:= lIntfProc;

  if Assigned(lReturnArg) then
  begin
    lImplProc.BeginEnd.AddCodeLine(Format('if aClassType = nil then aClassType := %s;', [lIntfProc.ReturnValue.Name]));
    lImplProc.BeginEnd.AddCodeLine(Format('Result := aClassType.Create(Connection);', []));
  end;

  lParams := '';
  lFd:='';
  if ARequest.Args.Count > 0 then
  begin

    for i := 0 to ARequest.Args.Count-1 do
    begin
      lArg := ARequest.Args.Items[i];
      lTypeName := GetArgTypeName(lArg, lType);
      case lType of
        tvNormal    : lParams+= TClassNode.Pascalify(lArg.Name, True, 'a')+',';
        tvFd        :
                      begin
                        lParams+= TClassNode.Pascalify(lArg.Name, True, 'a')+',';
                        lFd := ', '+i.ToString;
                      end;
        tvEnum      : lParams+= 'DWord('+TClassNode.Pascalify(lArg.Name, True, 'a')+'),';
        tvFixed     : lParams+= TClassNode.Pascalify(lArg.Name, True, 'a')+'.AsFixed,';
        tvNewObject : if i <> 0 then
                        lParams+= TClassNode.Pascalify(lArg.Name, True, 'a')+','
                      else
                        lParams+='Result.GetObjectId,';
        tvArray     : lParams+= 'Length('+TClassNode.Pascalify(lArg.Name, True, 'a')+'),Pointer('+TClassNode.Pascalify(lArg.Name, True, 'a')+'),';
        tvObject    : if lArg.Allow_Null then
                        // nullable object: send 0 (null id) when nil instead of
                        // dereferencing nil via .GetObjectId
                        lParams+= 'WlObjectId('+TClassNode.Pascalify(lArg.Name, True, 'a')+'),'
                      else
                        lParams+= TClassNode.Pascalify(lArg.Name, True, 'a')+'.GetObjectId,';
      else
        raise Exception.Create('unsupported type: '+ lArg.Type_);
      end;
    end;
  end;


  // if it's the bind procedure it needs two args added
  if (ARequest.Name = 'bind') and (AClass.Name = 'TWlRegistry') then
  begin
    lParams +='aVersion,ANewObjectId,';
  end;

  lParams:=Copy(lParams, 1, Length(lParams)-1); // eliminate comma

  lRequestConst := '_'+UpperCase(ARequest.Name);
  lImplProc.BeginEnd.AddCodeLine(Format('Connection.SendRequest(GetObjectId, Ord(TRequests.%s), [%s]%s);', [lRequestConst, lParams, lFd]));
  if lIntfProc.RoutineType = rtDestructor then
  begin
    lImplProc.BeginEnd.AddCodeLine('inherited Destroy;');
  end;
end;

procedure TWaylandUnitWriter.WriteServerInterface(AInterface: TWInterfaceNode);
var
  lClassName, lParentClass: String;
  lClass: TClassNode;
  lProtected, lPublished, lPrivate, lBitPublic: TVisibilityNode;
  lIntfAttrArg: TNamedNode;
  i, x: Integer;
  lPublicType, lTypeSection: TTypeSectionNode;
  lEnum, lRequestEnums: TEnumNode;
  lEntry: TWIEntry;
  lWritingIndex: Integer;
  lIntfEnum: TWIEnumNode;
  lObject: TObjectNode;
  lIntfAttr: TAttributeNode;
  lIntfAttrRequests: TStringList;
  lIntfAttrEvents: TStringList;
  lListener: TInterfaceTypeNode;
  lListenerName, lListenerPrefix: String;
  lAddListener: TRoutineNode;
  lAddListenerImpl: TRoutineImplNode;
begin
  if FWrittenInterfaces.IndexOf(AInterface.Name) <> -1 then
      Exit; // already written

  lClassName := TClassNode.Pascalify(StripZPrefix(AInterface.Name), True);
  // Incoming dispatch fans out to I<Class>Requests (the server-side counterpart
  // of the client's I<Class>Listener — it carries the request handlers).
  lListenerName := 'I' + Copy(lClassName, 2, MaxInt) + 'Requests';
  lListenerPrefix := StripZPrefix(AInterface.Name);

  if FWritingInterfaces.IndexOf(AInterface.Name) <> -1 then
  begin
    lWritingIndex := FWritingInterfaces.IndexOf(AInterface.Name);
    lClass := TClassNode(FWritingInterfaces.Objects[lWritingIndex]);
    if FForwardList.IndexOf(lClassName) = -1 then
    begin
      FUnit.InterfaceNode.WantTypeSection.AddClassOfNode(lClassName);
      FForwardList.Add(lClassName);
    end;
    FUnit.InterfaceNode.WantTypeSection.List.add(lClass);
    AppendListenerNode(lClassName);
    FWritingInterfaces.Delete(lWritingIndex);
    FWrittenInterfaces.Add(AInterface.Name);
    Exit;
  end;

  lWritingIndex := FWritingInterfaces.Add(AInterface.Name);

  // Self-register the class so its interface name resolves to it at runtime
  // (e.g. a proxy seeding a wl_registry.bind without a hand-written table).
  FUnit.AddInitLine(Format('RegisterServerInterface(%s, %s);',
    [QuotedStr(AInterface.Name), lClassName]));

  lParentClass := 'TWaylandServerResource';

  lIntfAttr := TAttributeNode.CreateNew(nil);
  lIntfAttr.IndentAdjust:=2;
  lIntfAttr.Name:='TWLIntfAttribute';
  lIntfAttrRequests := TStringList.Create;
  lIntfAttrEvents := TStringList.Create;
  lClass := TClassNode.CreateNew(nil);
  lClass.Name:=lClassName;
  lClass.AncestorClass := TClassNode.CreateNew(lClass);
  lClass.AncestorClass.Name:=lParentClass;

  WriteForward(lClassName);
  FUnit.InterfaceNode.WantTypeSection.AddInterfaceType(lListenerName).IsForward := True;
  lListener := TInterfaceTypeNode.CreateNew(FUnit.InterfaceNode.WantTypeSection);
  lListener.Name := lListenerName;
  lListener.IID := lListenerName;
  FListenerNodes.AddObject(lClassName, lListener);

  WriteInterfaceOverides(AInterface, lClass);

  FWritingInterfaces.Objects[lWritingIndex] := lClass;
  // Enums (identical to the client emitter)
  if AInterface.Enums.Count > 0 then
  begin
    lPublicType := lClass.FindFirstPublicType(True);
    for i := 0 to AInterface.Enums.Count-1 do
    begin
      lIntfEnum := AInterface.Enums.Items[i];
      if not lIntfEnum.IsBitfield then
      begin
        lEnum := lPublicType.AddEnumType(TClassNode.Pascalify(lIntfEnum.Name, True));
        for x := 0 to lIntfEnum.Entries.Count -1 do
        begin
          lEntry := lIntfEnum.Entries.Items[x];
          lEnum.AddValue(Format('%s = %d', [Copy(TClassNode.Pascalify(lEntry.Name, True), 2, MaxInt), lEntry.Value]));
        end;
      end
      else
      begin
        lObject := lPublicType.AddObjectType(TClassNode.Pascalify(lIntfEnum.Name, True), 'TBitfield');
        lBitPublic := lObject.WantVisibiltySection(vcPublic, True);
        for x := 0 to lIntfEnum.Entries.Count -1 do
        begin
          lEntry := lIntfEnum.Entries.Items[x];
          lBitPublic.AddProperty(TClassNode.Pascalify(lEntry.Name, True, ''), 'Boolean', 'GetValue', False, 'SetValue').Index:=lEntry.Value.ToString;
        end;
      end;
    end;
  end;

  // Opcode enums + the interface attribute (the runtime reads Request[] from the
  // attribute to count a request's out-of-band fds).
  lProtected := lClass.AddSection(vcProtected);
  lTypeSection := lProtected.AddTypeSection(True);
  if AInterface.Requests.Count > 0 then
    lRequestEnums := lTypeSection.AddEnumType('TRequests');
  for i := 0 to AInterface.Requests.Count-1 do
  begin
    lIntfAttrRequests.Add(Format('%s(%s)', [AInterface.Requests.Items[i].Name, AInterface.Requests.Items[i].Args.Signature]));
    lRequestEnums.AddValue(Format('_%s = %d',  [UpperCase(AInterface.Requests.Items[i].Name), i]), False);
  end;
  if AInterface.Events.Count > 0 then
    lEnum := lTypeSection.AddEnumType('TEvents');
  for i := 0 to AInterface.Events.Count-1 do
  begin
    lIntfAttrEvents.Add(Format('%s(%s)', [AInterface.Events.Items[i].Name, AInterface.Events.Items[i].Args.Signature]));
    lEnum.AddValue(Format('EV_%s = %d',  [UpperCase(AInterface.Events.Items[i].Name), i]), False);
  end;

  // Incoming: requests -> Handle<name> dispatch methods + On<name> + handler iface.
  lPrivate := lClass.AddSection(vcPrivate);
  lProtected := lClass.AddSection(vcProtected);
  lPublished := lClass.AddSection(vcPublished);
  for i := 0 to AInterface.Requests.Count-1 do
    WriteServerRequestHandler(AInterface, AInterface.Requests.Items[i], lClass, lProtected, lPublished, lListener, lListenerPrefix);

  // Outgoing: events -> public methods that SendEvent.
  for i := 0 to AInterface.Events.Count-1 do
    WriteServerEvent(AInterface, AInterface.Events.Items[i], lClass);

  // Handler registration (multi-listener, fan-out — same shape as the client).
  lClass.AddSection(vcPrivate).AddVariable('FListeners', 'array of ' + lListenerName);
  lAddListener := lClass.AddSection(vcPublic).AddRoutine(rtFunc, 'AddListener', 'LongInt');
  lAddListener.AddParameter('AIntf', lListenerName);
  lAddListenerImpl := FUnit.ImplentationNode.AddRoutineImplementation(lAddListener);
  lAddListenerImpl.BeginEnd.AddCodeLine('SetLength(FListeners, Length(FListeners)+1);');
  lAddListenerImpl.BeginEnd.AddCodeLine('FListeners[High(FListeners)] := AIntf;');
  lAddListenerImpl.BeginEnd.AddCodeLine('Result := 0;');

  if FWrittenInterfaces.IndexOf(AInterface.Name) = -1 then
  begin
    if FForwardList.IndexOf(lClassName) = -1 then
    begin
      FUnit.InterfaceNode.WantTypeSection.AddClassOfNode(lClassName);
      FForwardList.Add(lClassName);
    end;
    lIntfAttrArg := TNamedNode(lIntfAttr.List.AddItem);
    lIntfAttrArg.Name:=QuotedStr(lIntfAttrRequests.CommaText);
    lIntfAttrArg := TNamedNode(lIntfAttr.List.AddItem);
    lIntfAttrArg.Name:=QuotedStr(lIntfAttrEvents.CommaText);
    FUnit.InterfaceNode.WantTypeSection.List.add(lIntfAttr);
    FUnit.InterfaceNode.WantTypeSection.List.add(lClass);
    AppendListenerNode(lClassName);
    FWritingInterfaces.Delete(lWritingIndex);
    FWrittenInterfaces.Add(AInterface.Name);
  end;
  FreeAndNil(lIntfAttrEvents);
  FreeAndNil(lIntfAttrRequests);
end;

// Incoming request -> Handle<name>(var AMsg) message Ord(TRequests._<NAME>),
// decoding the request args and fanning out to On<name> + the handler interface.
// The mirror of WriteEvent (client incoming), with these direction swaps:
//  * opcode enum is TRequests._<NAME> (not TEvents.EV_<NAME>),
//  * object args resolve via Client.GetObject,
//  * a new_id arg is a CLIENT-allocated id, so the resource is created bound to
//    that id (T.Create(Client, id, Version)) rather than allocated by us.
procedure TWaylandUnitWriter.WriteServerRequestHandler(AInterface: TWInterfaceNode;
  ARequest: TWIRequestNode; AClass: TClassNode; AProtected, APublished: TVisibilityNode;
  AListener: TInterfaceTypeNode; const AListenerPrefix: String);
var
  lEventName, lName, lTypeName, lReadArg, lCallArgs, lTypeCast,
    lLookingFor, lListenerMethodName: String;
  lInterfaceProc, lProcType, lListenerMethod: TRoutineNode;
  lPublicType: TTypeSectionNode;
  i, x: Integer;
  lEventArg: TWIArgNode;
  lKind: TTypeVariety;
  lImplProc: TRoutineImplNode;
  lVar: TVarSectionNode;
  lBeginEnd: TBeginEndNode;
  lVarDecl: TParameterNode;
  lAssign, lCall, lSetHandled: TNamedNode;
  lProperty: TPropertyNode;
  lInterfaceXML: TWInterfaceNode;
begin
  // wl_registry.bind: the one request with an untyped new_id. The wire carries
  // (name:uint, interface:string, version:uint, id:uint), so the new resource's
  // type is only known at runtime from the interface string. Deliver all four to
  // the handler and let it create the resource. (Mirrors the client's bind
  // special in WriteRequest.)
  if (ARequest.Name = 'bind') and (AClass.Name = 'TWlRegistry') then
  begin
    lInterfaceProc := AProtected.AddRoutine(rtProc, 'HandleBind', '');
    lInterfaceProc.RoutineSpecialType := rstMethod;
    lInterfaceProc.IsVirtual := True;
    lInterfaceProc.AddParameter('var AMsg', 'TWaylandEventMessage');
    lInterfaceProc.Message := 'Ord(TRequests._BIND)';

    lPublicType := AClass.FindFirstPublicType(True);
    lProcType := lPublicType.AddProcedureType('TBindEvent', rtProc, True);
    lProcType.AddParameter('Sender', AClass.Name);
    lProcType.AddParameter('aName', 'DWord');
    lProcType.AddParameter('aInterface', 'String');
    lProcType.AddParameter('aVersion', 'DWord');
    lProcType.AddParameter('aId', 'DWord');

    lListenerMethod := AListener.AddMethod(rtProc, AListenerPrefix + '_bind');
    lListenerMethod.AddParameter('A'+Copy(AClass.Name, 2, MaxInt), AClass.Name);
    lListenerMethod.AddParameter('aName', 'DWord');
    lListenerMethod.AddParameter('aInterface', 'String');
    lListenerMethod.AddParameter('aVersion', 'DWord');
    lListenerMethod.AddParameter('aId', 'DWord');

    lProperty := APublished.AddPropertyRW('OnBind', lProcType.Name, True);

    lImplProc := FUnit.ImplentationNode.AddRoutineImplementation(lInterfaceProc);
    lImplProc.AddVariable('lName', 'DWord');
    lImplProc.AddVariable('lInterface', 'String');
    lImplProc.AddVariable('lVersion', 'DWord');
    lImplProc.AddVariable('lId', 'DWord');
    lImplProc.AddVariable('lListenerIdx', 'Integer');
    lImplProc.BeginEnd.AddCodeLine('lName := AMsg.Args.ReadDWord;');
    lImplProc.BeginEnd.AddCodeLine('lInterface := AMsg.Args.ReadString;');
    lImplProc.BeginEnd.AddCodeLine('lVersion := AMsg.Args.ReadDWord;');
    lImplProc.BeginEnd.AddCodeLine('lId := AMsg.Args.ReadDWord;');
    lImplProc.BeginEnd.AddCodeLine(Format('if Assigned(%s) then %s(Self, lName, lInterface, lVersion, lId);', [lProperty.Name, lProperty.Name]));
    lImplProc.BeginEnd.AddCodeLine(Format('for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].%s_bind(Self, lName, lInterface, lVersion, lId);', [AListenerPrefix]));
    lImplProc.BeginEnd.AddCodeLine('AMsg.SetHandled;');
    Exit;
  end;

  lEventName := 'Handle'+Copy(TClassNode.Pascalify(ARequest.Name, True), 2, MaxInt);
  lInterfaceProc := AProtected.AddRoutine(rtProc, lEventName, '');
  lInterfaceProc.RoutineSpecialType:=rstMethod;
  lInterfaceProc.IsVirtual:=True;
  lInterfaceProc.AddParameter('var AMsg', 'TWaylandEventMessage');
  lInterfaceProc.Message:= 'Ord(TRequests._'+UpperCase(ARequest.Name)+')';

  lPublicType := AClass.FindFirstPublicType(True);
  lProcType := lPublicType.AddProcedureType(TClassNode.Pascalify(ARequest.Name+'_Event', true), rtProc, True);
  lProcType.AddParameter('Sender', AClass.Name);

  lListenerMethodName := AListenerPrefix + '_' + ARequest.Name;
  lListenerMethod := AListener.AddMethod(rtProc, lListenerMethodName);
  lListenerMethod.AddParameter('A'+Copy(AClass.Name, 2, MaxInt), AClass.Name);

  for i := 0 to ARequest.Args.Count-1 do
  begin
    lEventArg := ARequest.Args.Items[i];
    lName := TClassNode.Pascalify(lEventArg.Name, True, 'a');
    lTypeName := GetArgTypeName(lEventArg, lKind);
    // Incoming fd args arrive out-of-band; deliver them as a ready stream.
    if lKind = tvFd then
      lTypeName := 'TWaylandFdStream';
    lProcType.AddParameter(lName, lTypeName);
    if (lKind = tvEnum) and (Pos('.', lTypeName) = 0) then
      lListenerMethod.AddParameter(lName, AClass.Name + '.' + lTypeName)
    else
      lListenerMethod.AddParameter(lName, lTypeName);
    if (lEventArg.Interface_ <> '') or (Pos('.', lEventArg.Enum) > 0 ) then
    begin
      lLookingFor := lEventArg.Interface_;
      if lLookingFor = '' then
        lLookingFor:=lEventArg.Enum.Split(['.'])[0];
      for x := 0 to FProtocol.Interfaces.Count-1 do
      begin
        lInterfaceXML := FProtocol.Interfaces.Items[x];
        if lInterfaceXML.Name = lLookingFor then
        begin
          if lEventArg.Interface_ <> '' then
            WriteForward(lTypeName)
          else
            WriteServerInterface(lInterfaceXML);
          Break;
        end;
      end;
    end;
  end;

  lProperty := APublished.AddPropertyRW('On'+TClassNode.Pascalify(ARequest.Name, True, ''), lProcType.Name, True);

  lImplProc := TRoutineImplNode.CreateNew(FUnit.ImplentationNode.Declarations);
  FUnit.ImplentationNode.Declarations.Add(lImplProc);
  lImplProc.RoutineDeclaration:= lInterfaceProc;
  lVar := lImplProc.VarSection;
  lBeginEnd := lImplProc.BeginEnd;
  lCallArgs := 'Self,';
  if ARequest.Args.Count > 0 then
  begin
    for i := 0 to ARequest.Args.Count-1 do
    begin
      lEventArg := ARequest.Args.Items[i];
      lName := TClassNode.Pascalify(lEventArg.Name, True, 'l');
      lTypeName := GetArgTypeName(lEventArg, lKind);
      if lKind = tvFd then
        lTypeName := 'TWaylandFdStream';
      lVarDecl := TParameterNode.CreateNew(lVar);
      lCallArgs+=lName+',';
      lVar.List.Add(lVarDecl);
      lVarDecl.Name:=lName;
      lVarDecl.Value := TNamedNode.CreateNew(lVarDecl);
      lVarDecl.Value.Name:=lTypeName;
      lAssign := TNamedNode.CreateNew(lBeginEnd.List);
      lBeginEnd.List.Add(lAssign);
      case lEventArg.Type_ of
        'uint'    : lReadArg := 'ReadDWord';
        'int'     : lReadArg := 'ReadInteger';
        'string'  : lReadArg := 'ReadString';
        'object'  : lReadArg := 'ReadDWord';
        'fd'      : lReadArg := 'ReadInteger';
        'new_id'  : lReadArg := 'ReadDWord';
        'fixed'   : lReadArg := 'ReadDWord';
        'array'   : lReadArg := 'ReadBlob';
      else
        raise Exception.Create('unsupported type as argument: ' +lEventArg.Type_);
      end;

      case lKind of
        tvNormal: lTypeCast:='';
        tvFd:     lTypeCast:='';
        tvEnum:
          begin
            lTypeCast := lTypeName+'(';
            lReadArg+=')';
          end;
        tvObject:
          begin
            lTypeCast := '(Client.GetObject(';
            lReadArg+=') as '+lTypename+')';
          end;
        tvFixed:
          begin
            lTypeCast := 'TWaylandFixed.FromFixed(';
            lReadArg+=')';
          end;
        tvArray: lTypeCast := '';
        tvNewObject:
          if lTypeName = 'DWord' then
            // Untyped new_id (no interface in the XML): we cannot create a typed
            // resource, so just deliver the raw client-allocated id. (The only
            // such request, wl_registry.bind, is fully special-cased above.)
            lTypeCast := ''
          else
          begin
            // The client allocated this id and sent it; create the resource bound
            // to that id, at this resource's version.
            lTypeCast := lTypeName+'.Create(Client, ';
            lReadArg+=', Version)';
          end
      else
        raise Exception.Create('Unhandled type: '+ lEventArg.Interface_)
      end;
      if lKind = tvFd then
        lAssign.Name:=Format('%s := AMsg.NextFdStream;', [lName])
      else
        lAssign.Name:=Format('%s := %sAMsg.Args.%s;', [lName, lTypeCast, lReadArg]);
      lTypeCast:='';
    end;
  end;
  lCallArgs:='('+Copy(lCallArgs, 1, Length(lCallArgs)-1)+')';
  lCall := TNamedNode.CreateNew(lBeginEnd.List);
  lBeginEnd.List.Add(lCall);
  lCall.Name:= Format('if Assigned(%s) then %s%s;', [lProperty.Name, lProperty.Name, lCallArgs]);
  lImplProc.AddVariable('lListenerIdx', 'Integer');
  lBeginEnd.AddCodeLine(Format('for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].%s%s;',
    [lListenerMethodName, lCallArgs]));
  lSetHandled := TNamedNode.CreateNew(lBeginEnd.List);
  lBeginEnd.List.Add(lSetHandled);
  lSetHandled.Name:='AMsg.SetHandled;';
end;

// Outgoing event -> a public method that marshals via SendEvent. The mirror of
// WriteRequest (client outgoing), with these direction swaps:
//  * opcode enum is TEvents.EV_<NAME>, sent via SendEvent (not SendRequest),
//  * a leading new_id is a SERVER-allocated child: NewResource(...) then send its
//    id (vs the client allocating and sending its own),
//  * object args use .Id / WlResourceId,
//  * none of the client-only specials (bind / shm / destructor mapping) apply.
procedure TWaylandUnitWriter.WriteServerEvent(AInterface: TWInterfaceNode;
  AEvent: TWIEventNode; AClass: TClassNode);
var
  lPublic: TVisibilityNode;
  i, x: Integer;
  lIntfProcType: TRoutineType = rtProc;
  lArg, lReturnArg: TWIArgNode;
  lIntfProc: TRoutineNode;
  lType: TTypeVariety;
  lTypeName, lParams, lName, lEventConst, lLookingFor, lFd, lInd: String;
  lImplProc: TRoutineImplNode;
  lInterfaceXML: TWInterfaceNode;
begin
  lReturnArg := nil;
  if (AEvent.Args.Count > 0) and ((AEvent.Args.Items[0].Type_ = 'new_id') and (AEvent.Args.Items[0].Interface_ <> ''))then
  begin
    lReturnArg := AEvent.Args.Items[0];
    lIntfProcType := rtFunc;
  end;

  lPublic := AClass.WantVisibiltySection(vcPublic, True);
  lName := TClassNode.Pascalify(AEvent.Name, True, '');
  // An event becomes a public method; suffix it if the name is a Pascal reserved
  // word (type/begin/end/...) or would shadow a base method.
  if NeedsMethodSuffix(lName) then
    lName := lName + '_';
  lIntfProc := lPublic.AddRoutine(lIntfProcType, lName, '');
  // Mark (and below, gate) events introduced after version 1, so a server never
  // sends an event a resource's negotiated version is too old to receive. since=1
  // events carry no attribute and no guard (the common case, no output churn).
  if AEvent.Since > 1 then
    lIntfProc.AttributeText := Format('[TSince(%d)]', [AEvent.Since]);

  if Assigned(lReturnArg) then
  begin
    lIntfProc.SetReturnValue(GetArgTypeName(lReturnArg, lType));
    if not (lType in [tvNewObject]) then
      Raise Exception.Create('Wrong kind of type for new_id');
  end;

  for i := 0 to AEvent.Args.Count-1 do
  begin
    lArg := AEvent.Args.Items[i];
    lName := TClassNode.Pascalify(lArg.Name, True, 'a');
    lTypeName := GetArgTypeName(lArg, lType);
    if (i > 0) or not (lType in [tvNewObject]) then // a leading new_id is the result
      lIntfProc.AddParameter(lName, lTypeName);
    if (lArg.Interface_ <> '') or (Pos('.', lArg.Enum) > 0 ) then
    begin
      lLookingFor := lArg.Interface_;
      if lLookingFor = '' then
        lLookingFor:=lArg.Enum.Split(['.'])[0];
      for x := 0 to FProtocol.Interfaces.Count-1 do
      begin
        lInterfaceXML := FProtocol.Interfaces.Items[x];
        if lInterfaceXML.Name = lLookingFor then
        begin
          if lArg.Interface_ <> '' then
            WriteForward(lTypeName)
          else
            WriteServerInterface(lInterfaceXML);
          Break;
        end;
      end;
    end;
  end;

  if Assigned(lReturnArg) then
  begin
    lName := 'aClassType';
    lTypeName := lIntfProc.ReturnValue.Name+'Class = nil';
    lIntfProc.AddParameter(lName, lTypeName);
  end;

  lImplProc := TRoutineImplNode.CreateNew(FUnit.ImplentationNode.Declarations);
  FUnit.ImplentationNode.Declarations.Add(lImplProc);
  lImplProc.RoutineDeclaration:= lIntfProc;

  // Version gate: for since>1 events, wrap the body in `if Version >= N then`
  // so it is a no-op on a resource bound to an older version. lInd indents the
  // wrapped statements.
  lInd := '';
  if AEvent.Since > 1 then
  begin
    if Assigned(lReturnArg) then
      lImplProc.BeginEnd.AddCodeLine('Result := nil;'); // gated function: define the result
    lImplProc.BeginEnd.AddCodeLine(Format('if Version >= %d then', [AEvent.Since]));
    lImplProc.BeginEnd.AddCodeLine('begin');
    lInd := '  ';
  end;

  if Assigned(lReturnArg) then
  begin
    lImplProc.BeginEnd.AddCodeLine(Format('%sif aClassType = nil then aClassType := %s;', [lInd, lIntfProc.ReturnValue.Name]));
    lImplProc.BeginEnd.AddCodeLine(Format('%sResult := %s(NewResource(aClassType, Version));', [lInd, lIntfProc.ReturnValue.Name]));
  end;

  lParams := '';
  lFd:='';
  if AEvent.Args.Count > 0 then
  begin
    for i := 0 to AEvent.Args.Count-1 do
    begin
      lArg := AEvent.Args.Items[i];
      lTypeName := GetArgTypeName(lArg, lType);
      case lType of
        tvNormal    : lParams+= TClassNode.Pascalify(lArg.Name, True, 'a')+',';
        tvFd        :
                      begin
                        lParams+= TClassNode.Pascalify(lArg.Name, True, 'a')+',';
                        lFd := ', '+i.ToString;
                      end;
        tvEnum      : lParams+= 'DWord('+TClassNode.Pascalify(lArg.Name, True, 'a')+'),';
        tvFixed     : lParams+= TClassNode.Pascalify(lArg.Name, True, 'a')+'.AsFixed,';
        tvNewObject : if i <> 0 then
                        lParams+= 'Integer('+TClassNode.Pascalify(lArg.Name, True, 'a')+'.GetObjectId),'
                      else
                        lParams+='Integer(Result.GetObjectId),';
        tvArray     : lParams+= 'Length('+TClassNode.Pascalify(lArg.Name, True, 'a')+'),Pointer('+TClassNode.Pascalify(lArg.Name, True, 'a')+'),';
        tvObject    : if lArg.Allow_Null then
                        lParams+= 'Integer(WlResourceId('+TClassNode.Pascalify(lArg.Name, True, 'a')+')),'
                      else
                        lParams+= 'Integer('+TClassNode.Pascalify(lArg.Name, True, 'a')+'.GetObjectId),';
      else
        raise Exception.Create('unsupported type: '+ lArg.Type_);
      end;
    end;
  end;

  lParams:=Copy(lParams, 1, Length(lParams)-1); // eliminate trailing comma

  lEventConst := 'EV_'+UpperCase(AEvent.Name);
  lImplProc.BeginEnd.AddCodeLine(Format('%sSendEvent(Ord(TEvents.%s), [%s]%s);', [lInd, lEventConst, lParams, lFd]));
  if AEvent.Since > 1 then
    lImplProc.BeginEnd.AddCodeLine('end;');
end;

procedure WriteSPDXHeader(AStream: TStream);
const
  H =
    '// SPDX-License-Identifier: BSD-3-Clause'#10 +
    '// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>'#10 +
    '//'#10 +
    '// Generated by wayland-gen — do not edit by hand.'#10#10;
begin
  AStream.WriteBuffer(H[1], Length(H));
end;

procedure TWaylandUnitWriter.WriteUnit(AProtocol: TWIProtocolNode;
  AStream: TStream; ASenderUsesBase: Boolean; const AUnitName: String;
  AServerMode: Boolean);
var
  i: Integer;
  lExtUnits: TStringList;
begin
  FServerMode := AServerMode;
  FWrittenInterfaces := TStringList.Create;
  FWrittenInterfaces.Sorted:=True;
  FWrittenInterfaces.Duplicates:=TDuplicates.dupIgnore;
  FWritingInterfaces := TStringList.Create;
  FWritingInterfaces.Sorted:=True;
  FWritingInterfaces.Duplicates:=TDuplicates.dupIgnore;
  FForwardList := TStringList.Create;
  FForwardList.Sorted:=True;
  FListenerNodes := TStringList.Create;
  FListenerNodes.Sorted:=True;

  FProtocol := AProtocol;
  FUnit := TUnitNode.CreateNew(Self);
  if AUnitName <> '' then
    FUnit.Name:= AUnitName
  else
    FUnit.Name:= FProtocol.Name;
  FUnit.ModeSwitches.AddModeSwitch('{$mode ObjFPC}{$H+}');
  FUnit.ModeSwitches.AddModeSwitch('{$ScopedEnums on}');
  FUnit.ModeSwitches.AddModeSwitch('{$modeswitch advancedrecords}');
  FUnit.ModeSwitches.AddModeSwitch('{$modeswitch prefixedattributes}');
  // corba interfaces: no IUnknown/GUID required, no refcounting -- lets the
  // generated I<Class>Listener interfaces use a plain string IID and be stored
  // as raw pointers, matching the libwayland-bindings convention.
  FUnit.ModeSwitches.AddModeSwitch('{$interfaces corba}');
  if FServerMode then
  begin
    // Server units build on the server runtime core; the shared transport's
    // event-message / fd-stream value types come from wayland_queue.
    FUnit.InterfaceNode.UsesNode.AddUnit(['Classes', 'Sysutils', 'wayland_server_core', 'wayland_queue']);
    if AProtocol.Name <> 'wayland' then
      FUnit.InterfaceNode.UsesNode.AddUnit('wayland_server');
    FUnit.ImplentationNode.UsesNode.AddUnit('wayland_stream');
  end
  else
  begin
    FUnit.InterfaceNode.UsesNode.AddUnit(['Classes', 'Sysutils', 'Wayland_Core', 'wayland_queue', 'wayland_internal_interfaces']);
    if AProtocol.Name <> 'wayland' then
      FUnit.InterfaceNode.UsesNode.AddUnit('wayland')
    else
    begin // is wayland.xml
      FUnit.ImplentationNode.UsesNode.AddUnit('wayland_shm_impl');
    end;
    FUnit.ImplentationNode.UsesNode.AddUnit(['wayland_stream', 'wayland_interfaces']);
  end;

  // cross-protocol references (e.g. xdg_decoration -> xdg_shell) need the
  // defining unit in the interface uses clause.
  lExtUnits := TStringList.Create;
  try
    CollectExternalUnits(lExtUnits);
    for i := 0 to lExtUnits.Count-1 do
      FUnit.InterfaceNode.UsesNode.AddUnit(lExtUnits[i]);
  finally
    lExtUnits.Free;
  end;

  for i := 0 to FProtocol.Interfaces.Count-1 do
  begin
    if FServerMode then
      WriteServerInterface(FProtocol.Interfaces.Items[i])
    else
      WriteInterface(FProtocol.Interfaces.Items[i]);
  end;
  FreeAndNil(FWrittenInterfaces);
  FreeAndNil(FWritingInterfaces);
  FreeAndNil(FForwardList);
  FreeAndNil(FListenerNodes);

  WriteSPDXHeader(AStream);
  FUnit.WriteToStream(AStream);



end;

end.

