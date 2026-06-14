unit wayland_unitwriter;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, wayland_interface_reader, unit_and_object_writeer, jsonobjects, jsonparser;

type

  { TWaylandUnitWriter }

  TWaylandUnitWriter = class(TJsonBase)
  private type
    TTypeVariety = (tvNormal, tvObject, tvNewObject, tvArray, tvEnum, tvFixed, tvFd);
  private

    FOutStream: TStream;
    FUnit: TUnitNode;
    FProtocol: TWIProtocolNode;
    FSEnderUsesBase: Boolean;
    FWrittenInterfaces: TStringList;
    FWritingInterfaces: TStringList;
    FForwardList: TStringList;
    function GetFullEnumName(AName: String): String;
    function GetArgTypeName(AArg: TWIArgNode; out AKind: TTypeVariety): String;
    function LookupIsBitfield(AThisInterface: TWInterfaceNode; AName: String): Boolean;
    procedure WriteForward(AClassName: String);
    procedure WriteShmFunctionsForTWlSHM(AClass: TClassNode);
    procedure WriteInterfaceOverides(AInterface: TWInterfaceNode; AClass: TClassNode);
    procedure WriteInterface(AInterface: TWInterfaceNode);
    procedure WriteEvent(AInterface: TWInterfaceNode; aEvent: TWIEventNode; AClass: TClassNode; AProtected, APublished: TVisibilityNode);
    procedure WriteRequest(AInterface: TWInterfaceNode; ARequest: TWIRequestNode; AClass: TClassNode; AProtected, APublished: TVisibilityNode);
  public
    procedure WriteUnit(AProtocol: TWIProtocolNode; AStream: TStream; ASenderUsesBase: Boolean = False);
  end;

implementation

{ TWaylandUnitWriter }

function TWaylandUnitWriter.GetFullEnumName(AName: String): String;
var
  lStrings: TStringList;
  i: Integer;
begin
  lStrings := TStringList.Create;
  lStrings.AddStrings(AName.Split('.'));
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
            Result := TClassNode.Pascalify(AArg.Interface_, True, 'T');
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
            Result := TClassNode.Pascalify(AArg.Interface_, True, 'T');
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
begin
  if FWrittenInterfaces.IndexOf(AInterface.Name) <> -1 then
      Exit; // already written

  lClassName := TClassNode.Pascalify(AInterface.Name, True);

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
      WriteEvent(AInterface, AInterface.Events.Items[i], lClass, lProtected, lPublished);
    end;
  end;

  // Create "requests"
  for i := 0 to AInterface.Requests.Count-1 do
  begin
    WriteRequest(AInterface, AInterface.Requests.Items[i], lClass, lProtected, lPublished);
  end;
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
    FWritingInterfaces.Delete(lWritingIndex);
    FWrittenInterfaces.Add(AInterface.Name);
  end;
  FreeAndNil(lIntfAttrEvents);
  FreeAndNil(lIntfAttrRequests);
end;

procedure TWaylandUnitWriter.WriteEvent(AInterface: TWInterfaceNode;
  aEvent: TWIEventNode; AClass: TClassNode; AProtected,
  APublished: TVisibilityNode);
var
  lEventName, lName, lType, lTypeName, lReadArg, lCallArgs, lTypeCast,
    lLookingFor: String;
  lInterfaceProc, lProcType: TRoutineNode;
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

  for i := 0 to aEvent.Args.Count-1 do
  begin
    lEventArg := aEvent.Args.Items[i];
    lName := TClassNode.Pascalify(lEventArg.Name, True, 'a');
    lTypeName := GetArgTypeName(lEventArg, lKind); // if lIsEnum add forward?
    lProcType.AddParameter(lName, lTypeName);
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
            lTypeCast:='';  // todo. how do we read an fd from and event?
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
      lAssign.Name:=Format('%s := %sAMsg.Args.%s;', [lName, lTypeCast, lReadArg]);
      lTypeCast:='';
    end; // for
  end;
  lCallArgs:='('+Copy(lCallArgs, 1, Length(lCallArgs)-1)+')'; // trim comma
  lCall := TNamedNode.CreateNew(lBeginEnd.List);
  lBeginEnd.List.Add(lCall);
  lCall.Name:= Format('if Assigned(%s) then %s%s;', [lProperty.Name, lProperty.Name, lCallArgs]);
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

  lPublic := AClass.WantVisibiltySection(vcPublic, True);
  lIntfProc := lPublic.AddRoutine(lIntfProcType, TClassNode.Pascalify(ARequest.Name, True, ''), '');
  if ARequest.Type_ = 'destructor' then
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
        tvArray     : lParams+= TClassNode.Pascalify(lArg.Name, True, 'a')+',';
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

procedure TWaylandUnitWriter.WriteUnit(AProtocol: TWIProtocolNode;
  AStream: TStream; ASenderUsesBase: Boolean);
var
  i: Integer;
begin
  FWrittenInterfaces := TStringList.Create;
  FWrittenInterfaces.Sorted:=True;
  FWrittenInterfaces.Duplicates:=TDuplicates.dupIgnore;
  FWritingInterfaces := TStringList.Create;
  FWritingInterfaces.Sorted:=True;
  FWritingInterfaces.Duplicates:=TDuplicates.dupIgnore;
  FForwardList := TStringList.Create;
  FForwardList.Sorted:=True;

  FProtocol := AProtocol;
  FUnit := TUnitNode.CreateNew(Self);
  FUnit.Name:= FProtocol.Name;
  FUnit.ModeSwitches.AddModeSwitch('{$mode ObjFPC}{$H+}');
  FUnit.ModeSwitches.AddModeSwitch('{$ScopedEnums on}');
  FUnit.ModeSwitches.AddModeSwitch('{$modeswitch advancedrecords}');
  FUnit.ModeSwitches.AddModeSwitch('{$modeswitch prefixedattributes}');
  FUnit.InterfaceNode.UsesNode.AddUnit(['Classes', 'Sysutils', 'Wayland_Core', 'wayland_queue', 'wayland_internal_interfaces']);
  if AProtocol.Name <> 'wayland' then
    FUnit.InterfaceNode.UsesNode.AddUnit('wayland')
  else
  begin // is wayland.xml
    FUnit.ImplentationNode.UsesNode.AddUnit('wayland_shm_impl');

  end;


  FUnit.ImplentationNode.UsesNode.AddUnit(['wayland_stream', 'wayland_interfaces']);

  for i := 0 to FProtocol.Interfaces.Count-1 do
  begin
    WriteInterface(FProtocol.Interfaces.Items[i]);
  end;
  FreeAndNil(FWrittenInterfaces);
  FreeAndNil(FWritingInterfaces);
  FreeAndNil(FForwardList);

  FUnit.WriteToStream(AStream);



end;

end.

