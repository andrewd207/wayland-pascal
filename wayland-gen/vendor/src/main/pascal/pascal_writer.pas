// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>
//
// Vendored Pascal-source AST writer. Derived from json_easy's
// unit_and_object_writeer, re-based off the RTL (a small TVendNode/TVendList
// object model) so the code generator no longer depends on json_easy or tiOPF.
unit pascal_writer;

{$mode objfpc}{$H+}
{$modeswitch prefixedattributes}
{$M+}   // emit RTTI for published members (used to auto-create child nodes)

interface

uses
  Classes, SysUtils, contnrs, TypInfo, Rtti, md5;

const
  CReservedKeywords: TStringArray = ('and',
'array',
'begin',
'case',
'const',
'div',
'do',
'downto',
'else',
'end',
'file',
'for',
'function',
'goto',
'if',
'implementation',
'in',
'inline',
'interface',
'label',
'mod',
'nil',
'not',
'object',
'of',
'or',
'packed',
'procedure',
'program',
'record',
'repeat',
'set',
'then',
'to',
'type',
'unit',
'until',
'uses',
'var',
'while',
'with',
'xor');

type
  // Pascal member visibility (replaces json_easy's TVisibilityClass).
  TVisibilityClass = (vcPublic, vcPrivate, vcProtected, vcPublished);

  { TVendNode — minimal owner/parent object with RTTI auto-creation of its
    published object children. Replaces tiOPF's TtiObject + json_easy's
    TJsonBase, but with no JSON and no persistence. The writer builds a tree of
    these and serialises it to Pascal source. }
  TVendNode = class
  private
    FOwner: TVendNode;
    function GetParent: TVendNode;
    procedure AutoCreateChildren;
  protected
    procedure SetOwner(AValue: TVendNode); virtual;
  public
    constructor Create; virtual;
    constructor CreateNew(AOwner: TVendNode = nil); virtual;
    destructor Destroy; override;
    // Owner is the immediate container; Parent skips a list container (so a node
    // inside a list reports the list's owner as its parent — see GetParent).
    property Owner: TVendNode read FOwner write SetOwner;
    property Parent: TVendNode read GetParent;
  end;
  TVendNodeClass = class of TVendNode;

  { TVendList — minimal owner-aware object list (replaces TtiObjectList). Owns
    its items by default; Add re-assigns each item's Owner to the list so the
    Parent chain skips the list container. }
  TVendList = class(TVendNode)
  private
    FList: TObjectList;
    FItemOwner: TVendNode;
    FAutoSetItemOwner: Boolean;
    function GetCount: Integer;
    function GetItem(i: Integer): TVendNode;
    procedure SetItem(i: Integer; AValue: TVendNode);
    function GetOwnsObjects: Boolean;
    procedure SetOwnsObjects(AValue: Boolean);
    function GetInnerList: TList;
  public
    constructor Create; override;
    destructor Destroy; override;
    function Add(AObject: TVendNode): Integer;
    procedure Insert(AIndex: Integer; AObject: TVendNode); overload;
    procedure Insert(AInsertBefore: TVendNode; AObject: TVendNode); overload;
    function IndexOf(AObject: TVendNode): Integer;
    function Last: TVendNode;
    procedure Clear;
    property Count: Integer read GetCount;
    property Items[i: Integer]: TVendNode read GetItem write SetItem; default;
    property OwnsObjects: Boolean read GetOwnsObjects write SetOwnsObjects;
    property ItemOwner: TVendNode read FItemOwner write FItemOwner;
    property AutoSetItemOwner: Boolean read FAutoSetItemOwner write FAutoSetItemOwner;
    // the raw inner container (mirrors tiOPF's TtiObjectList.List); used by code
    // that adds/iterates without owner re-assignment
    property List: TList read GetInnerList;
  end;

  { TVendNodeList — typed list (replaces json_easy's generic TJsonList<T>). }
  generic TVendNodeList<T: TVendNode> = class(TVendList)
  public type
    TEnumerator = class
    private
      FList: TVendList;
      FIndex: Integer;
      function GetCurrent: T;
    public
      constructor Create(AList: TVendList);
      function MoveNext: Boolean;
      property Current: T read GetCurrent;
    end;
  protected
    function CreateItem: T;
  private
    function GetItemT(i: Integer): T;
    procedure SetItemT(i: Integer; AValue: T);
  public
    function AddItem: T;
    function GetEnumerator: TEnumerator;
    property Item[i: Integer]: T read GetItemT write SetItemT;
  end;

  { NamedAttribute }

  NamedAttribute = class(TCustomAttribute)
  private
    FName: String;
  published
    property Name: String read FName;
  public
    constructor Create(AName: String);
  end;

  { VisibilityAttribute }

  VisibilityAttribute = class(TCustomAttribute)
  private
    FVisibility: TVisibilityClass;
  published
    property Visibility: TVisibilityClass read FVisibility;
  public
    constructor Create(AVisibliity: TVisibilityClass);
  end;

  { TPascalNode }

  TPascalNode = class(TVendNode)
  protected
    function GetIndent: Integer; virtual;
    procedure WriteLine(const AStream: TStream; ALine: RawByteString; ALineEndings: Integer = 1); virtual;
    procedure WriteToStream(AStream: TStream); virtual; abstract;
    function IsAllowedParent(AParent: TPascalnode): Boolean; virtual;
  end;


  { TNamedNode }
  // any subclass of this can use [NamedAttribute('name')] to automatically set the name
  TNamedNode = class(TPascalNode)
  private
    FName: String;
  protected
    function SanitizeName(AString: String): String;
    procedure WriteToStream(AStream: TStream); override;
  published
    property Name: String read FName write FName;
  public
    constructor Create; override;
  end;

  { TModeSwitchNode }

  TModeSwitchNode = class(TNamedNode)
  end;

  { TNamedWithList }

  generic TNamedWithList<T: TPascalNode> = class(TNamedNode)
  public type
    TListOfT = specialize TVendNodeList<T>;
  protected
    procedure WriteToStream(AStream: TStream); override;
  private
    FList: TListOfT;
    FNoDefaultWriteList: Boolean;
  published
    property List: TListofT read FList write FList;
  end;


  { TUsesNode }

  TUsesItemNode = class(TNamedNode)
  end;

  [NamedAttribute('uses')]
  TUsesNode = class(specialize TNamedWithList<TUsesItemNode>)
  protected
    function GetIndent: Integer; override;
    procedure WriteToStream(AStream: TStream); override;
  public
    procedure AddUnit(AName: String);
    procedure AddUnit(ANames: array of String);
  end;


  TRoutineType = (rtProc, rtFunc, rtDestructor, rtConstructor);
  TRoutineSpecialType = (rstNone, rstMethod, rstClassMethod);


  TEnumNode = class;
  TClassNode = class;
  TRecordNode = class;
  TObjectNode = class;
  TInterfaceTypeNode = class;
  TRoutineNode = class;
  TRoutineImplNode = class;
  { TDeclarationSectionNode }


  // Base class for [type|var|const] section
  TDeclarationSectionNode = class(specialize TNamedWithList<TNamedNode>)
  public type
    TVisibility = (vDefault, vPublic, vPrivate);
  private
    FVisibility: TVisibility;
  published
    property Visibility: TVisibility read FVisibility write FVisibility;
  end;



  { TClassOfNode }

  TClassOfNode = class (TNamedNode)
    procedure WriteToStream(AStream: TStream); override;
  end;

  { TTypeSectionNode }
  [NamedAttribute('type')]
  TTypeSectionNode = class(TDeclarationSectionNode)
  protected
    function GetIndent: Integer; override;
  public
    function AddClassOfNode(AClassname: String; AAddToStart: Boolean = False): TNamedNode;
    function AddClassType(AClassName: String; AParentClass: String = ''; AAddToStart: Boolean = False): TClassNode;
    function AddClassType(AClassName: String; AParentClass: TClassNode): TClassNode;
    function AddRecordType(ARecordName: String): TRecordNode;
    function AddObjectType(AObjectName: String; AParentObject: String): TObjectNode;
    function AddProcedureType(AProcName: String; aRoutineType: TRoutineType; AOfObject: Boolean): TRoutineNode;
    function AddEnumType(AEnumName: String): TEnumNode;
    function AddInterfaceType(AName: String; AIID: String = ''; AParent: String = ''): TInterfaceTypeNode;
  end;





  { TVarSectionNode }
  [NamedAttribute('var')]
  TVarSectionNode = class(TDeclarationSectionNode)
  protected
    procedure WriteToStream(AStream: TStream); override;
  end;
  { TConstNode }

  [NamedAttribute('const')]
  TConstSectionNode = class(TDeclarationSectionNode);


  { TInterfaceNode }

  [NamedAttribute('interface')]
  TInterfaceNode = class(TNamedNode)
  private
    FDeclarations: TDeclarationSectionNode.TListOfT;
    FUsesNode: TUsesNode;
    procedure WriteDeclarations(AStream: TStream);
  protected
    function GetIndent: Integer; override;
    procedure WriteToStream(AStream: TStream); override;
  published
    property UsesNode: TUsesNode read FUsesNode write FUsesNode;
    property Declarations: TDeclarationSectionNode.TListOfT read FDeclarations write FDeclarations;
  public
    //procedure AddDeclaration(
    function AddTypeSection: TTypeSectionNode;
    function WantTypeSection: TTypeSectionNode;
    function WantConstSection: TConstSectionNode;
    function WantVarSection: TVarSectionNode;
  end;




  { RoutineAttribute }

  RoutineAttribute = class(TCustomAttribute)
  private
    FRoutineSpecialType: TRoutineSpecialType;
    FRoutineType: TRoutineType;
  public
    constructor Create(AType: TRoutineType);
    constructor Create(AType: TRoutineType; ASpecialType: TRoutineSpecialType);
  published
    property RoutineType: TRoutineType read FRoutineType;
    property RoutineSpecialType: TRoutineSpecialType read FRoutineSpecialType;
  end;


  { TParameterNode }

  { TVariableNode }

  TVariableNode = class(TNamedNode)
  private
    FValue: TNamedNode;
  protected
    procedure WriteToStream(AStream: TStream); override;
  published
    property Value: TNamedNode read FValue write FValue;
  end;

  TParameterNode = class(TVariableNode)
  private
    FIsUntyped: Boolean;
  protected
    procedure WriteToStream(AStream: TStream); override;
  published
    property IsUntyped: Boolean read FIsUntyped write FIsUntyped;
  end;


  { TRoutineNode }

  TRoutineNode = class(specialize TNamedWithList<TParameterNode>)
    constructor Create; override;
  protected
    procedure WriteToStream(AStream: TStream); override;
    function GetImplClassNamePrefix: String;
    procedure SetClassPrefix(AValue: String);

  private
    FIsAbstract: Boolean;
    FIsOverride: Boolean;
    FIsType: Boolean;
    FIsVirtual: Boolean;
    FMessage: String;
    FReturnValue: TNamedNode;
    FRoutineSpecialType: TRoutineSpecialType;
    FRoutineType: TRoutineType;
    FClassPrefix: String; // only set by TRoutineImpl
  published
    function AddParameter(AName, AType: String): TParameterNode;
    procedure SetReturnValue(AValue: String);
    property RoutineType: TRoutineType read FRoutineType write FRoutineType;
    property RoutineSpecialType: TRoutineSpecialType read FRoutineSpecialType write FRoutineSpecialType;
    Property List; // parameters
    property ReturnValue: TNamedNode read FReturnValue write FReturnValue;
    property IsVirtual: Boolean read FIsVirtual write FIsVirtual;
    property IsAbstract: Boolean read FIsAbstract write FIsAbstract;
    property IsOverride: Boolean read FIsOverride write FIsOverride;
    property Message: String read FMessage write FMessage;
    property IsType: Boolean read FIsType write FIsType; // TRoutine = procedure(args)[of object]
  end;


  [RoutineAttribute(rtFunc)]
  TFunctionNode = class(TRoutineNode);

  [RoutineAttribute(rtProc)]
  TProcedureNode = class(TRoutineNode);

  [RoutineAttribute(rtConstructor)]
  TConstructorNode = class(TRoutineNode);

  [RoutineAttribute(rtDestructor)]
  TDestructorNode = class(TRoutineNode);

  TCodeNode = class;

  { TBeginEndNode }

  TBeginEndNode = class(specialize TNamedWithList<TPascalNode>)
  protected
    procedure WriteToStream(AStream: TStream); override;
  public
    function AddCodeLine(ACode: String=''): TCodeNode;

  end;

  { TRoutineImplNode }

  TRoutineImplNode = class (specialize TNamedWithList<TNamedNode>)
  private
    FBeginEnd: TBeginEndNode;
    FRoutineDeclaration: TRoutineNode;
    FVarSection: TVarSectionNode;
  protected
    function GetIndent: Integer; override;
    procedure WriteToStream(AStream: TStream); override;
  published
    property RoutineDeclaration: TRoutineNode read FRoutineDeclaration write FRoutineDeclaration;
    property VarSection: TVarSectionNode read FVarSection write FVarSection;
    property BeginEnd: TBeginEndNode read FBeginEnd write FBeginEnd;
    property list;
  public
    function AddVariable(AName, AType: String): TVariableNode;
  end;


  { TPropertyNode }

  TPropertyNode = class(TNamedNode)
  private
    FAliasName: String;
    FDefaultValue: String;
    FIndex: String;
    FIsRequired: Boolean;
    FReadName: String;
    FTypeName: String;
    FWriteName: String;
  protected
    procedure WriteToStream(AStream: TStream); override;
  published
    property TypeName: String read FTypeName write FTypeName;
    property ReadName: String read FReadName write FReadName;
    property WriteName: String read FWriteName write FWriteName;
    property DefaultValue: String read FDefaultValue write FDefaultValue;
    property AliasName: String read FAliasName write FAliasName;
    property IsRequired: Boolean read FIsRequired write FIsRequired;
    property Index: String read FIndex write FIndex;
  end;

  { TCodeNode }

  TCodeNode = class(TPascalNode)
  private
    FLine: String;
  protected
    procedure WriteToStream(AStream: TStream); override;
  published
    property Line: String read FLine write FLine;
  end;


  { TVisibilityNode }

  TVisibilityNode = class(specialize TNamedWithList<TPascalNode>)
  private
    FVisibility: TVisibilityClass;
  protected
    function GetIndent: Integer; override;
    procedure WriteToStream(AStream: TStream); override;
    function VisToName: String;
    function GetClassNode: TClassNode;
  published
    property Visibility: TVisibilityClass read FVisibility write FVisibility;
  public
    constructor Create; override;
    function AddTypeSection(AMergeWithParentName: Boolean = True): TTypeSectionNode;
    function AddConstSection: TConstSectionNode;
    function AddVariable(AName: String; AType: String): TVariableNode;
    function AddProperty(AName: String; AType: String; ARead: String; AWriteUsesRead: Boolean = False; AWrite: String = ''; ADefault: String = ''): TPropertyNode;
    function AddPropertyRW(AName: String; AType: String; aAddPrivateVar: Boolean): TPropertyNode; // uses 'F'+AName as read and write
    function AddPropertyReadOnly(AName: String; AType: String; aAddPrivateVar: Boolean): TPropertyNode; // uses 'F'+AName as read and write
    function AddRoutine(AKind: TRoutineType; AName: String; AReturnType: String): TRoutineNode;
  end;

  [VisibilityAttribute(vcPublic)]
  TPublicSection = class(TVisibilityNode);

  [VisibilityAttribute(vcProtected)]
  TProtectedSection = class(TVisibilityNode);

  [VisibilityAttribute(vcPrivate)]
  TPrivateSection = class(TVisibilityNode);

  [VisibilityAttribute(vcPublished)]
  TPublishedSection = class(TVisibilityNode);

  { TDeclaredTypeNode }

  TDeclaredTypeNode= class(TDeclarationSectionNode)
    class function Pascalify(AName: String; ANeedsPrefix: Boolean; ACustomPrefix: String = 'T'): String;
    function FullPathName: String;
  end;

  { TAttributeNode }

  TAttributeNode = class(specialize TNamedWithList<TNamedNode>)
  public type

    { TList }

    TList = class(specialize TVendNodeList<TAttributeNode>)
      function AddAttribute(AName: String): TAttributeNode;
    end; //

  // note: The List property of TAttributeNode is TNamedNode and thses contain the parameters of the attribute
  private
    FIndentAdjust: Integer;
    FItemsAsArray: Boolean;
  protected
    function GetIndent: Integer; override;
    procedure WriteToStream(AStream: TStream); override;
  published
    property ItemsAsArray: Boolean read FItemsAsArray write FItemsAsArray;
    property List; // TNamedNode
  public
    property IndentAdjust: Integer read FIndentAdjust write FIndentAdjust;
  end;


  { TEnumNode }

  TEnumNode = class(specialize TNamedWithList<TNamedNode>)
  private
    FAttributes: TAttributeNode.TList;
    FHashValue: String;
  protected
    procedure WriteToStream(AStream: TStream); override;
    function GetHashValue: String;
  published
     property Attributes: TAttributeNode.TList read FAttributes write FAttributes;
  public
     function Prefixify(AValue: String): String;
     function AddAttribute(AName: String): TAttributeNode;
     function AddValue(AValue: String; AAddPrefix: Boolean = True): TNamedNode;
     procedure AddValues(AValues: TStringArray; AAddPrefix: Boolean = True);
     function SearchDuplicate: TEnumNode;
     function FullTypeName: String;

  end;


  { TClassNode }

  TClassNode = class(TDeclaredTypeNode)
  private
    FAncestorClass: TClassNode;
    FIsAlias: Boolean;
    FSections: TVisibilityNode.TListOfT;
  protected
    function GetRecordObjectClassKeyword: String; virtual;
    procedure WriteToStream(AStream: TStream); override;
  published
    property AncestorClass: TClassNode read FAncestorClass write FAncestorClass default nil; // don't create an instance automatically
    property IsAlias: Boolean read FIsAlias write FIsAlias;
    //property Sections: TVisibilityNode.TList read FSections write FSections;
  public
    function AddSection(AType: TVisibilityClass = vcPublic): TVisibilityNode;
    function FindFirstPublicType(AddIfNotExist: Boolean = False): TTypeSectionNode;
    function FindFirstPrivateSection(AddIfNotExist: Boolean = False; AddBeforeOtherSection: TVisibilityNode = nil): TPrivateSection;
    function WantVisibiltySection(AVisibility: TVisibilityClass;
      ACreateIfNotExists: Boolean): TVisibilityNode;
  end;

  { TRecordNode }

  TRecordNode = class(TClassNode)
  protected
    function GetRecordObjectClassKeyword: String; override;
  end;

  { TObjectNode }

  TObjectNode = class(TClassNode)
  protected
    function GetRecordObjectClassKeyword: String; override;
  end;

  { TInterfaceTypeNode }
  // Emits a Pascal interface type:
  //   IName = interface[(Ancestor)]
  //   ['IID']
  //     <method signatures>
  //   end;
  TInterfaceTypeNode = class(TClassNode)
  private
    FIID: String;
    FIsForward: Boolean;
  protected
    function GetRecordObjectClassKeyword: String; override;
    procedure WriteToStream(AStream: TStream); override;
  public
    property IID: String read FIID write FIID;
    // when True, emits just a forward decl: "IName = interface;"
    property IsForward: Boolean read FIsForward write FIsForward;
    function AddMethod(AKind: TRoutineType; AName: String; AReturnType: String = ''): TRoutineNode;
  end;

  { TImplementationNode }
  [NamedAttribute('implementation')]
  TImplementationNode = class(TNamedNode)
  private
    FDeclarations: TDeclarationSectionNode.TListOfT;
    FUsesNode: TUsesNode;
  protected
    function GetIndent: Integer; override;
    procedure WriteToStream(AStream: TStream); override;
  published
    property UsesNode: TUsesNode read FUsesNode write FUsesNode;
    property Declarations: TDeclarationSectionNode.TListOfT read FDeclarations write FDeclarations;
  public
    function AddRoutineImplementation(ADecl: TRoutineNode): TRoutineImplNode;
  end;



  { TModeSwitchList }

  TModeSwitchList = class(specialize TVendNodeList<TModeSwitchNode>)
    procedure AddModeSwitch(AString: String);
    procedure WriteToStream(const AStream: TStream);
  end;

  { TUnitNode }

  TUnitNode = class(TNamedNode)
  private
    FImplentationNode: TImplementationNode;
    FInterfaceNode: TInterfaceNode;
    FModeSwitches: TModeSwitchList;
    procedure SetImplentationNode(AValue: TImplementationNode);
    procedure SetInterfaceNode(AValue: TInterfaceNode);
    procedure SetName(AValue: String);
    procedure WriteModeSwitches(AStream: TStream);
    procedure WriteInterface(AStream: TStream);
    procedure WriteImplementation(AStream: TStream);
  published
    property Name: String read FName write SetName;
    property ModeSwitches: TModeSwitchList read FModeSwitches write FModeSwitches;
    property InterfaceNode: TInterfaceNode read FInterfaceNode write SetInterfaceNode;
    property ImplentationNode: TImplementationNode read FImplentationNode write SetImplentationNode;
  public
    procedure WriteToStream(AStream: TStream); override;
  end;





implementation

operator in(const Value: string; const Arr: TStringArray): Boolean;
var
  i: Integer;
begin
  Result := False; // Default result is false
  for i := Low(Arr) to High(Arr) do
  begin
    if Arr[i] = Value then
    begin
      Result := True; // Value found in array
      Exit;           // Exit early
    end;
  end;
end;

{ TVendNode }

constructor TVendNode.Create;
begin
  inherited Create;
  AutoCreateChildren;
end;

constructor TVendNode.CreateNew(AOwner: TVendNode);
begin
  Create;
  if AOwner <> nil then
    Owner := AOwner;
end;

destructor TVendNode.Destroy;
var
  PP: PPropList;
  cnt, i: Integer;
  obj: TObject;
begin
  // Free the published object children we own. Shared/list-owned nodes have a
  // different Owner and are skipped, so this never double-frees. (Not reached
  // during generation — the writer tree is intentionally leaked one-shot.)
  PP := nil;
  cnt := GetPropList(PTypeInfo(ClassInfo), PP);
  try
    for i := 0 to cnt - 1 do
      if PP^[i]^.PropType^.Kind = tkClass then
      begin
        obj := GetObjectProp(Self, PP^[i]);
        if (obj is TVendNode) and (TVendNode(obj).Owner = Self) then
        begin
          SetObjectProp(Self, PP^[i], nil);
          obj.Free;
        end;
      end;
  finally
    if PP <> nil then FreeMem(PP);
  end;
  inherited Destroy;
end;

procedure TVendNode.SetOwner(AValue: TVendNode);
begin
  FOwner := AValue;
end;

function TVendNode.GetParent: TVendNode;
begin
  // mirror tiOPF: a list is transparent in the parent chain
  if (FOwner is TVendList) and Assigned(FOwner.FOwner) then
    Result := FOwner.FOwner
  else
    Result := FOwner;
end;

procedure TVendNode.AutoCreateChildren;
var
  PP: PPropList;
  cnt, i: Integer;
  prop: PPropInfo;
  cls: TClass;
begin
  // Instantiate every published object property that is not `default nil`,
  // mirroring json_easy/TtiObject so child nodes (lists, sub-sections) exist
  // without the caller wiring them up.
  PP := nil;
  cnt := GetPropList(PTypeInfo(ClassInfo), PP);
  try
    for i := 0 to cnt - 1 do
    begin
      prop := PP^[i];
      if prop^.PropType^.Kind <> tkClass then Continue;
      if prop^.Default = 0 then Continue;              // `default nil` -> stay nil
      if GetObjectProp(Self, prop) <> nil then Continue;
      cls := GetTypeData(prop^.PropType)^.ClassType;
      if cls.InheritsFrom(TVendNode) then
        SetObjectProp(Self, prop, TVendNodeClass(cls).CreateNew(Self));
    end;
  finally
    if PP <> nil then FreeMem(PP);
  end;
end;

{ TVendList }

constructor TVendList.Create;
begin
  inherited Create;
  FList := TObjectList.Create(True);   // owns its items
  FItemOwner := Self;
  FAutoSetItemOwner := True;
end;

destructor TVendList.Destroy;
begin
  FList.Free;
  inherited Destroy;
end;

function TVendList.GetCount: Integer;
begin
  Result := FList.Count;
end;

function TVendList.GetItem(i: Integer): TVendNode;
begin
  Result := TVendNode(FList[i]);
end;

procedure TVendList.SetItem(i: Integer; AValue: TVendNode);
begin
  FList[i] := AValue;
end;

function TVendList.GetOwnsObjects: Boolean;
begin
  Result := FList.OwnsObjects;
end;

procedure TVendList.SetOwnsObjects(AValue: Boolean);
begin
  FList.OwnsObjects := AValue;
end;

function TVendList.GetInnerList: TList;
begin
  Result := FList;
end;

function TVendList.Add(AObject: TVendNode): Integer;
begin
  if FAutoSetItemOwner then
    AObject.Owner := FItemOwner;
  Result := FList.Add(AObject);
end;

procedure TVendList.Insert(AIndex: Integer; AObject: TVendNode);
begin
  if FAutoSetItemOwner then
    AObject.Owner := FItemOwner;
  FList.Insert(AIndex, AObject);
end;

procedure TVendList.Insert(AInsertBefore: TVendNode; AObject: TVendNode);
var
  idx: Integer;
begin
  idx := FList.IndexOf(AInsertBefore);
  if idx < 0 then idx := 0;
  Insert(idx, AObject);
end;

function TVendList.IndexOf(AObject: TVendNode): Integer;
begin
  Result := FList.IndexOf(AObject);
end;

function TVendList.Last: TVendNode;
begin
  if FList.Count > 0 then
    Result := TVendNode(FList[FList.Count - 1])
  else
    Result := nil;
end;

procedure TVendList.Clear;
begin
  FList.Clear;
end;

{ TVendNodeList }

function TVendNodeList.CreateItem: T;
begin
  Result := T(T.CreateNew(Self));
end;

function TVendNodeList.GetItemT(i: Integer): T;
begin
  Result := T(Items[i]);
end;

procedure TVendNodeList.SetItemT(i: Integer; AValue: T);
begin
  Items[i] := AValue;
end;

function TVendNodeList.AddItem: T;
begin
  Result := CreateItem;
  Add(Result);
end;

function TVendNodeList.GetEnumerator: TEnumerator;
begin
  Result := TEnumerator.Create(Self);
end;

function TVendNodeList.TEnumerator.GetCurrent: T;
begin
  Result := T(FList[FIndex]);
end;

function TVendNodeList.TEnumerator.MoveNext: Boolean;
begin
  Inc(FIndex);
  Result := FIndex < FList.Count;
end;

constructor TVendNodeList.TEnumerator.Create(AList: TVendList);
begin
  FList := AList;
  FIndex := -1;
end;

{ NamedAttribute }

constructor NamedAttribute.Create(AName: String);
begin
  FName:= AName;
end;

{ VisibilityAttribute }

constructor VisibilityAttribute.Create(AVisibliity: TVisibilityClass);
begin
  inherited Create;
  FVisibility:=AVisibliity;
end;

{ TPascalNode }

function TPascalNode.GetIndent: Integer;
var
  lIter: TPascalNode;
begin
 Result := 0;
 lIter := TPascalNode(Self.Parent);

 if Assigned(lIter) and not lIter.InheritsFrom(TUnitNode) and lIter.InheritsFrom(TPascalNode) then
   Result := lIter.GetIndent + 2;;

end;

procedure TPascalNode.WriteLine(const AStream: TStream; ALine: RawByteString;
  ALineEndings: Integer);
var
  lLine : RawByteString;
  lIndent: Integer;
  i: Integer;
begin
  lIndent := GetIndent;
  SetLength(lLine, lIndent);
  FillChar(lLine[1], lIndent, ' ');
  lLine := lLine + ALine;
  for i := 0 to ALineEndings-1 do
  begin
    lLine := lLine + LineEnding;
  end;

  AStream.Write(lLine[1], Length(lLine));
end;

function TPascalNode.IsAllowedParent(AParent: TPascalnode): Boolean;
begin
  Result := False;
end;

{ TNamedNode }



function TNamedNode.SanitizeName(AString: String): String;
begin
 if AString = 'type' then
   Write;
  Result := AString;
  if AString in CReservedKeywords then
    REsult := '&'+Result;
end;

procedure TNamedNode.WriteToStream(AStream: TStream);
begin
 if FName <> '' then
   WriteLine(AStream, FName);
end;

constructor TNamedNode.Create;
var
  Attribute: TCustomAttribute;
  Context: TRttiContext;
  AType: TRttiType;
begin
  inherited Create;
  try
    Context := TRttiContext.Create;
    AType := Context.GetType(Self.ClassInfo);
    for Attribute in  AType.GetAttributes do begin
      if Attribute is NamedAttribute then
         Name:=NamedAttribute(Attribute).Name;

    end;
  finally
    Context.Free;
  end;
end;

{ TNamedWithList }

procedure TNamedWithList.WriteToStream(AStream: TStream);
var
  i: Integer;
begin
  inherited WriteToStream(AStream);
  for i := 0 to List.Count-1 do
    List.Item[i].WriteToStream(AStream);
end;

{ TUsesNode }

function TUsesNode.GetIndent: Integer;
begin
  Result:=0
end;

procedure TUsesNode.WriteToStream(AStream: TStream);
var
  lLine: RawByteString;
  i: Integer;
begin
  // no inherited
  WriteLine(AStream, Name);
  lLine := '  ';
  for i := 0 to List.Count-1 do
  begin
    lLine := lLine +  List.Item[i].Name;
    if i < List.Count-1 then
       lLine += ', '
    else
        lLine += ';';
  end;

  WriteLine(AStream, lLine, 2);
end;

procedure TUsesNode.AddUnit(AName: String);
var
  lItem: TUsesItemNode;
begin
  lItem := TUsesItemNode.CreateNew(Self);
  lItem.Name:=AName;
  List.Add(lItem);
end;

procedure TUsesNode.AddUnit(ANames: array of String);
var
  lName: String;
begin
  for lName in ANames do
    AddUnit(lName);
end;

{ TTypeSectionNode }

function TTypeSectionNode.GetIndent: Integer;
begin
  Result:= TPascalNode(Parent).GetIndent;
end;

function TTypeSectionNode.AddClassOfNode(AClassname: String;
  AAddToStart: Boolean): TNamedNode;
begin
  Result := TClassOfNode.CreateNew(List);
  if AAddToStart then
    List.Insert(0, Result)
  else
    List.Add(Result);
  Result.Name:=AClassName
end;

function TTypeSectionNode.AddClassType(AClassName: String;
  AParentClass: String; AAddToStart: Boolean): TClassNode;
begin
  Result := TClassNode.CreateNew(Self);
  Result.Name:=AClassName;
  if AParentClass <> '' then
  begin
     Result.AncestorClass := TClassNode.CreateNew(Self);
     Result.AncestorClass.Name:=AParentClass;
  end;
  if AAddToStart then
    List.Insert(0, Result)
  else
    List.Add(Result);
end;

function TTypeSectionNode.AddClassType(AClassName: String;
  AParentClass: TClassNode): TClassNode;
begin
  Result := AddClassType(AClassName);
  Result.AncestorClass := AParentClass;
end;

function TTypeSectionNode.AddRecordType(ARecordName: String): TRecordNode;
begin
  Result := TRecordNode.CreateNew(List);
  List.Add(Result);
  REsult.Name:=ARecordName;
end;

function TTypeSectionNode.AddObjectType(AObjectName: String;
  AParentObject: String): TObjectNode;
begin
  Result := TObjectNode.CreateNew(List);
  Result.Name:=AObjectName;
  Result.AncestorClass:=TObjectNode.CreateNEw(Result);
  Result.AncestorClass.Name:=AParentObject;
  List.Add(Result);
end;

function TTypeSectionNode.AddInterfaceType(AName: String; AIID: String;
  AParent: String): TInterfaceTypeNode;
begin
  Result := TInterfaceTypeNode.CreateNew(Self);
  Result.Name := AName;
  Result.IID := AIID;
  if AParent <> '' then
  begin
    Result.AncestorClass := TClassNode.CreateNew(Result);
    Result.AncestorClass.Name := AParent;
  end;
  List.Add(Result);
end;

function TTypeSectionNode.AddProcedureType(AProcName: String;
  aRoutineType: TRoutineType; AOfObject: Boolean): TRoutineNode;
begin
  case aRoutineType of
    TRoutineType.rtProc: Result := TProcedureNode.CreateNew(List);
    TRoutineType.rtFunc: Result := TFunctionNode.CreateNew(List);
  else
    Raise Exception.Create('routine type can only be procedure or function');
  end;
  Result.Name:=AProcName;

  if AOfObject then
    Result.RoutineSpecialType:=rstMethod;
  Result.IsType:=True;
  List.Add(Result);
end;

function TTypeSectionNode.AddEnumType(AEnumName: String): TEnumNode;
begin
  Result := TEnumNode.CreateNew(Self);
  Result.Name:=AEnumName;
  List.Add(Result);
end;

{ TVarSectionNode }

procedure TVarSectionNode.WriteToStream(AStream: TStream);
var
  l: TParameterNode;
  lLine: String;
begin
  WriteLine(AStream, Name);
  for TNamedNode(l) in List do
  begin
    lLine := FOrmat('  %s: %s;', [l.Name, l.Value.Name]);
    WriteLine(AStream, lLine);
  end;

end;

{ TInterfaceNode }

procedure TInterfaceNode.WriteDeclarations(AStream: TStream);
var
  i: Integer;
begin
  for i := 0 to Declarations.Count-1 do
  begin
    Declarations.Item[i].WriteToStream(AStream);
  end;
end;

function TInterfaceNode.GetIndent: Integer;
begin
  Result:=0;
end;

procedure TInterfaceNode.WriteToStream(AStream: TStream);
begin
  inherited WriteToStream(AStream);
  UsesNode.WriteToStream(AStream);

  WriteDeclarations(AStream);
end;

function TInterfaceNode.AddTypeSection: TTypeSectionNode;
begin
  Result := TTypeSectionNode.CreateNew(Self);
  Declarations.Add(Result);
end;

function TInterfaceNode.WantTypeSection: TTypeSectionNode;
begin
  if (Declarations.Count = 0) or not(Declarations.Last.InheritsFrom(TTypeSectionNode)) then
  begin
    Result := TTypeSectionNode.CreateNew(Declarations);
    Declarations.Add(Result);
    Exit;
  end;
  Result := Declarations.Last as TTypeSectionNode;
end;

function TInterfaceNode.WantConstSection: TConstSectionNode;
begin
  if (Declarations.Count = 0) or not(Declarations.Last.InheritsFrom(TConstSectionNode)) then
  begin
    Result := TConstSectionNode.CreateNew(Declarations);
    Declarations.Add(Result);
    Exit;
  end;
  Result := Declarations.Last as TConstSectionNode;

end;

function TInterfaceNode.WantVarSection: TVarSectionNode;
begin
  if (Declarations.Count = 0) or not(Declarations.Last.InheritsFrom(TVarSectionNode)) then
  begin
    Result := TVarSectionNode.CreateNew(Declarations);
    Declarations.Add(Result);
    Exit;
  end;
  Result := Declarations.Last as TVarSectionNode;
end;

{ RoutineAttribute }

constructor RoutineAttribute.Create(AType: TRoutineType);
begin
  Create(AType, rstNone);
end;

constructor RoutineAttribute.Create(AType: TRoutineType;
  ASpecialType: TRoutineSpecialType);
begin
  FRoutineType := AType;
  FRoutineSpecialType := ASpecialType;
end;

{ TVariableNode }

procedure TVariableNode.WriteToStream(AStream: TStream);
var
  lLine: String;
begin
  lLine := Format('%s: %s;', [Name, Value.Name]);

  WriteLine(AStream, lLine);
end;

{ TParameterNode }

procedure TParameterNode.WriteToStream(AStream: TStream);
var
  lLine: String;
begin
  if not IsUntyped then
    lLine := Format('%s: %s', [Name, Value.Name])
  else
    lLine := Format('%', [Name]);

  AStream.Write(lLine[1], Length(lLine));
end;

{ TRoutineNode }

constructor TRoutineNode.Create;
var
  Attribute: TCustomAttribute;
  Context: TRttiContext;
  AType: TRttiType;
  lAttribute: RoutineAttribute;
begin
  inherited Create;
  try
    Context := TRttiContext.Create;
    AType := Context.GetType(Self.ClassInfo);
    for Attribute in  AType.GetAttributes do begin
      if Attribute is RoutineAttribute then
      begin
        lAttribute := RoutineAttribute(Attribute);
        RoutineType:=lAttribute.RoutineType;
        RoutineSpecialType:=lAttribute.RoutineSpecialType;
      end;

    end;
  finally
    Context.Free;
  end;
end;

procedure TRoutineNode.WriteToStream(AStream: TStream);
var
  lRoutineType, lParams, lPostfix, lPrefix, lReturnType, lLine,
    lRoutineName: String;
  lItem: TParameterNode;
  i: Integer;
begin
  case RoutineType of
    rtProc        : lRoutineType := 'procedure';
    rtFunc        : lRoutineType := 'function';
    rtDestructor  : lRoutineType := 'destructor';
    rtConstructor : lRoutineType := 'constructor';
  end;
  case RoutineSpecialType of
    rstNone,
    rstMethod: ; // nothing to do
    rstClassMethod : lPrefix := 'class ';
  end;

  if (FMessage <> '') and (FClassPrefix = '') then // dont write message for implementation
    lPostFix := ' message ' + FMessage+';';
  if FClassPrefix = '' then // only set during the implementation and these are not written there
  begin
    if IsVirtual then
      lPostfix += ' virtual;'
    else if IsAbstract then
      lPostfix += ' virtual; abstract;'
    else if IsOverride then
      lPostfix += ' override;';
  end;

  if IsType and (RoutineSpecialType = rstMethod) then
    lPostfix:=' of object';


  lParams := '';

  for i := 0 to List.Count-1 do
  begin
    lItem := List.Item[i];
    if not lItem.IsUntyped then
      lParams += Format('%s: %s; ', [litem.Name, lItem.Value.Name])
    else
      lParams += Format('%s; ', [litem.Name]);
  end;

  if lParams <> '' then
    lParams := Format('(%s)', [Copy(lParams, 1, Length(lParams)-2)]);

  if RoutineType = rtFunc then
    lReturnType :=': '+ ReturnValue.Name;

  lRoutineName := FClassPrefix+Name; // FClassPrefix is set during the implementation;

  if not IsType then
  begin                               { class   function      [TClass.]Foo  (a: b)   [: String] ; virtual; }
    lLine := Format('%s%s %s%s%s;%s', [lPrefix, lRoutineType, lRoutineName, lParams, lReturnType, lPostfix]);
  end
  else
  begin                             {typename      function      (a: b)   [: String ]  [of object] }
    lLine:= Format('%s = %s%s%s%s;', [lRoutineName, lRoutineType, lParams, lReturnType, lPostfix]);
  end;


  WriteLine(AStream, lLine);

end;

function TRoutineNode.GetImplClassNamePrefix: String;
var
  lParent: TVendNode;
begin
  Result := '';
  lParent := Parent;
  while Assigned(lParent)do
  begin
    //WriteLn(lParent.ClassName);
    if lParent.InheritsFrom(TClassNode) then
      Exit(TClassNode(lParent).FullPathName+'.');
    lParent := lParent.Parent;
  end;
  //WriteLn(Result);
end;

procedure TRoutineNode.SetClassPrefix(AValue: String);
begin
  FClassPrefix:=AValue;
end;


function TRoutineNode.AddParameter(AName, AType: String): TParameterNode;
begin
  Result := TParameterNode.CreateNew(Self);
  Result.Name:=AName;
  Result.Value := TNamedNode.CreateNew(Result);
  Result.Value.Name:=AType;
  List.Add(Result);
end;

procedure TRoutineNode.SetReturnValue(AValue: String);
begin
  if not Assigned(FReturnValue) then
    FReturnValue := TNamedNode.CreateNew(Self);
  FReturnValue.Name:=AValue;
end;

{ TClassOfNode }

procedure TClassOfNode.WriteToStream(AStream: TStream);
var
  lLine: String;
begin
  lLine := Format('%sClass = class of %s;',[Name, Name]);
  WriteLine(AStream, lLine);
end;

{ TBeginEndNode }

procedure TBeginEndNode.WriteToStream(AStream: TStream);
begin
  WriteLine(AStream, 'begin');
  inherited WriteToStream(AStream);
  WriteLine(AStream, 'end;');
end;

function TBeginEndNode.AddCodeLine(ACode: String = ''): TCodeNode;
begin
  Result := TCodeNode.CreateNew(List);
  List.Add(Result);
  Result.Line:=ACode;

end;

{ TRoutineImplNode }

function TRoutineImplNode.GetIndent: Integer;
begin
  Result := -2;
end;

procedure TRoutineImplNode.WriteToStream(AStream: TStream);
var
  lSaveparent: TVendNode;
  i: TNamedNode;
  lClassName: String;
begin
  lSaveparent := RoutineDeclaration.Parent;
  lClassName := RoutineDeclaration.GetImplClassNamePrefix;
  RoutineDeclaration.Owner := Self;
  RoutineDeclaration.SetClassPrefix(lClassName);
  RoutineDeclaration.WriteToStream(AStream);
  RoutineDeclaration.SetClassPrefix('');
  RoutineDeclaration.Owner := lSaveparent;
  for i in List do
  begin
    i.WriteToStream(AStream);
  end;
  if Assigned(FVarSection) and (FVarSection.List.Count> 0) then
    FVarSection.WriteToStream(AStream);

  FBeginEnd.WriteToStream(AStream);
  // add additional line ending
  AStream.WriteByte(10);

end;

function TRoutineImplNode.AddVariable(AName, AType: String): TVariableNode;
begin
  Result := TVariableNode.CreateNew(VarSection);
  Result.Name:=AName;
  Result.Value := TNamedNode.CreateNew(Result);
  Result.Value.Name:=AType;
  VarSection.List.Add(Result);
end;

{ TPropertyNode }

procedure TPropertyNode.WriteToStream(AStream: TStream);
var
  lLine, lActualPropName, lMaybeIndex: String;
begin
  if IsRequired then
    WriteLine(AStream, '[TRequiredAttr]');

  if FAliasName <> '' then
  begin
    // Alias is the name for the pascal type
    // so Name is the json propertry name
    WriteLine(AStream, Format('[TAliasAttr(''%s'')]', [Name]));
    lActualPropName := SanitizeName(FAliasName);
  end
  else
    lActualPropName:= SanitizeName(Name);

  if Index <> '' then
    lMaybeIndex := Format(' index %s ', [Index])
  else
    lMaybeIndex:='';

  if WriteName <> '' then
    lLine := Format('property %s: %s %sread %s write %s', [lActualPropName,  TypeName, lMaybeIndex, ReadName, WriteName])
  else
    lLine := Format('property %s: %s %sread %s', [lActualPropName, TypeName, lMaybeIndex, ReadName]);

  if DefaultValue <> ''then
    lLine:= lLine + Format(' default %s', [DefaultValue]);
  lLine+=';';
  WriteLine(AStream, lLine);
end;

{ TCodeNode }

procedure TCodeNode.WriteToStream(AStream: TStream);
begin
  WriteLine(AStream, FLine);
end;

{ TVisibilityNode }

function TVisibilityNode.GetIndent: Integer;
begin
  Result:= TPascalNode(Parent).GetIndent;
end;

procedure TVisibilityNode.WriteToStream(AStream: TStream);
begin
  if List.Count = 0 then
    Exit;

  if List[0].InheritsFrom(TTypeSectionNode) and (TTypeSectionNode(List[0]).List.Count = 0) then
    Exit;
  inherited WriteToStream(AStream);
end;

function TVisibilityNode.VisToName: String;
begin
  case Visibility of
    vcPublic: Result := 'public';
    vcPublished: Result := 'published';
    vcPrivate: Result := 'private';
    vcProtected: Result := 'protected';
  end;
end;

function TVisibilityNode.GetClassNode: TClassNode;
var
  lParent: TVendNode;
begin
  lParent:= Parent;
  while Assigned(lParent) do
  begin
    if lParent.InheritsFrom(TClassNode) then
      Exit(TClassNode(lParent));
    lParent := lParent.Parent;
  end;
  Result := nil;
end;

constructor TVisibilityNode.Create;
var
  Attribute: TCustomAttribute;
  Context: TRttiContext;
  AType: TRttiType;
  lAttribute: VisibilityAttribute;
begin
  inherited Create;
  try
    Context := TRttiContext.Create;
    AType := Context.GetType(Self.ClassInfo);
    for Attribute in  AType.GetAttributes do begin
      if Attribute is VisibilityAttribute then
      begin
        lAttribute := VisibilityAttribute(Attribute);
        Visibility:=lAttribute.Visibility;
        Name := VisToName;
      end;
    end;
  finally
    Context.Free;
  end;
end;

function TVisibilityNode.AddTypeSection(AMergeWithParentName: Boolean
  ): TTypeSectionNode;
begin
  Result := TTypeSectionNode.CreateNew(Self);
  List.Add(Result);

  if AMergeWithParentName then
  begin
    Name:=VisToName + ' type';
    Result.Name:='';
  end;
end;

function TVisibilityNode.AddConstSection: TConstSectionNode;
begin
  Result := TConstSectionNode.CreateNew(Self);
  List.Add(Result);
end;

function TVisibilityNode.AddVariable(AName: String; AType: String
  ): TVariableNode;
begin
  Result := TVariableNode.CreateNew(Self);
  Result.Name:=AName;
  Result.Value := TNamedNode.CreateNew(Result);
  Result.Value.Name:=AType;
  List.Add(Result);
end;

function TVisibilityNode.AddProperty(AName: String; AType: String;
  ARead: String; AWriteUsesRead: Boolean; AWrite: String; ADefault: String
  ): TPropertyNode;
begin
  Result := TPropertyNode.CreateNew(Self);
  Result.Name:=AName;
  Result.TypeName:=AType;
  Result.ReadName:=ARead;
  Result.WriteName:=AWrite;
  Result.DefaultValue:=ADefault;
  if AWriteUsesRead then
    Result.WriteName:=ARead;
  List.Add(Result);
end;

function TVisibilityNode.AddPropertyRW(AName: String; AType: String;
  aAddPrivateVar: Boolean): TPropertyNode;
var
  lClass: TClassNode;
begin
  Result := AddProperty(AName, AType, 'F'+AName+'Priv', True);

  if aAddPrivateVar then
  begin
    lClass := GetClassNode;
    if Assigned(lClass) then
      lClass.FindFirstPrivateSection(True, Self).AddVariable('F'+AName+'Priv', AType);
  end;
end;

function TVisibilityNode.AddPropertyReadOnly(AName: String; AType: String;
  aAddPrivateVar: Boolean): TPropertyNode;
var
  lClass: TClassNode;
begin
  Result := AddProperty(AName, AType, 'F'+AName+'Priv', False, '');

  if aAddPrivateVar then
  begin
    lClass := GetClassNode;
    if Assigned(lClass) then
      lClass.FindFirstPrivateSection(True, Self).AddVariable('F'+AName+'Priv', AType);
  end;


end;

function TVisibilityNode.AddRoutine(AKind: TRoutineType; AName: String;
  AReturnType: String): TRoutineNode;
begin
  case AKind of
    rtProc       : Result := TProcedureNode.CreateNew(Self);
    rtFunc       : begin
                     Result := TFunctionNode.CreateNew(Self);
                     Result.ReturnValue := TNamedNode.CreateNew(Result);
                     Result.ReturnValue.Name:=AReturnType;
                   end;
    rtDestructor : Result := TDestructorNode.CreateNew(Self);
    rtConstructor: Result := TConstructorNode.CreateNew(Self);
  end;
  List.Add(Result);
  Result.Name:=AName;
end;

{ TDeclaredTypeNode }

class function TDeclaredTypeNode.Pascalify(AName: String;
  ANeedsPrefix: Boolean; ACustomPrefix: String): String;
var
  i: SizeInt;
begin
  if not ANeedsPrefix then
    AName:=Copy(AName, 2, MaxInt);

  AName:=LowerCase(AName);
  AName[1] := UpperCase(AName[1])[1];
  i := Length(AName);
  while i > 1 do // > 1 because we already did the first char
  begin
    while AName[i] = '_' do
    begin
      Delete(AName, i, 1);
      AName[i] := UpperCase(AName[i])[1];
    end;
    Dec(i);
  end;

  Result := ACustomPrefix+AName;
end;

function TDeclaredTypeNode.FullPathName: String;
var
  lIter: TPascalNode;
begin
  Result := Name;

  lIter := Self;

  while Assigned(lIter) do
  begin
    lIter := TPascalNode(lIter.Parent);
    if Assigned(lIter) and lIter.InheritsFrom(TDeclaredTypeNode) then
      Result :=  TNamedNode(lIter).Name +'.'+Result;
  end;
end;

{ TAttributeNode }

function TAttributeNode.GetIndent: Integer;
begin
  Result:=inherited GetIndent-2+FIndentAdjust;
end;

procedure TAttributeNode.WriteToStream(AStream: TStream);
var
  lItem: TNamedNode;
  lLine: String;
begin
  for lItem in List do
  begin
    lLine+=lItem.Name+', ';
  end;

  if lLine <> '' then lLine:= Copy(lLine, 1, Length(lLine) -2);
  if ItemsAsArray then
    lLine:='['+lLine+']';
  WriteLine(AStream, Format('[%s(%s)]', [Name, lLine]));
end;

{ TAttributeNode.TList }

function TAttributeNode.TList.AddAttribute(AName: String): TAttributeNode;
begin
  Result := AddItem;
  Result.Name:=AName;
end;

{ TEnumNode }

procedure TEnumNode.WriteToStream(AStream: TStream);
var
  lAttr: TAttributeNode;
  lEnumName: TNamedNode;
  lLine: String ='';
begin
  for lAttr in FAttributes do
  begin
    lAttr.WriteToStream(AStream);
  end;
  for lEnumName in List do
  begin
    lLine+= lEnumName.Name+', ';
  end;
  WriteLine(AStream, Format('%s = (%s);', [Name, Copy(lLine, 1, Length(lLine)-2)]));
end;

function TEnumNode.GetHashValue: String;
var
  s: TStringStream;
  lData: RawByteString;
begin
  if FHashValue = '' then
  begin
    s := TStringStream.Create('');
    try
      WriteToStream(s);
      lData := RawByteString(StringReplace(s.DataString,' ', '', [rfReplaceAll] ));

      FHashValue:= MD5Print(MD5String(lData));
      //WriteLn(FHashValue);
    finally
      s.Free;
    end;
  end;
  Result := FHashValue;
end;

function TEnumNode.Prefixify(AValue: String): String;
var
  lEnumName: String;
  i: Integer;
  lPrefix: UnicodeString;
  lNext: Boolean;
begin
  lEnumName := Name;
    i := 3;
    lPrefix := lowercase(lEnumName[2]);
    lNext := False;
    while i < Length(lEnumName) do
    begin
      try
        if lEnumName[i] = '_' then
        begin
          lNext := True;
          continue;
        end;
        if lNext then
          lPrefix+=lowercase(lEnumName[i]);
        lNExt := False
      finally
        inc(i);
      end;
    end;
    if (Length(lPrefix) = 1) {and (lPrefix[1] in ['f', 'l', 's', 't'])} then
    begin
      // TType.tOne > TType.tyONE
      lPrefix:=lowercase(Copy(Name, 2, 2));
    end;

    AValue := AValue.ToLower;
    AValue[1] := (UpperCase(AValue[1])[1]);
    i := 2;
    while i < Length(Avalue) do
    begin
      try
        while AValue[i] = '_' do
        begin
          Delete(AValue, i, 1);
          lNext := True;
        end;
        if lNext then
          AValue[i] := Uppercase(AValue[i])[1];
        lNext := False;
      finally
        inc(i);
      end;
    end;
  REsult := lPrefix+AValue;
end;

function TEnumNode.AddAttribute(AName: String): TAttributeNode;
begin
  Result := Attributes.AddAttribute(AName);
end;

function TEnumNode.AddValue(AValue: String; AAddPrefix: Boolean): TNamedNode;
begin
  Result := List.AddItem;

  if AAddPrefix then
    Result.Name:=Prefixify(AValue)
  else
    Result.Name:=AValue;
end;

procedure TEnumNode.AddValues(AValues: TStringArray; AAddPrefix: Boolean);
var
  v: String;
begin
  for v in AValues do
    AddValue(v, AAddPrefix);
end;

type
  TIterateResult = (irNone, irFound, irStopped);
function IterateForHash(AObject: TVendNode; AHash: String; AStopAtItem: TEnumNode; var AFoundItem: TVendNode): TIterateResult;
var
  i: Integer;
  lItem, lNewObject: TVendNode;
  PI:PTypeInfo;
  PT: PTypeData;
  PP : PPropList;
  J: LongInt;
  lProp: PPropInfo;
begin
  Result := irNone;
   if (AObject.ClassType = AStopAtItem.ClassType) and (TEnumNode(AObject).GetHashValue = AHash) then
   begin
     AFoundItem := AObject;
     Exit(irFound);
   end;

  if AObject.InheritsFrom(TVendList) then
  begin
    for i := 0 to TVendList(AObject).Count-1 do
    begin
      lItem := TVendList(AObject).Items[i];
      if lITem = AStopAtItem then
        Exit(irStopped);

      if (lItem.ClassType = AStopAtItem.ClassType) and (TEnumNode(lItem).GetHashValue = AHash) then
      begin
        AFoundItem := lItem;
        Exit(irFound);
      end;
      Result := IterateForHash(lItem, AHash, AStopAtItem, AFoundItem);

      if Result <> irNone then
        Exit;
    end;
  end;

  // now the fun part. read all the properties and iterate

  PP:=nil;
  PI:=PTypeInfo(AObject.ClassInfo);
  PT:=GetTypeData(PI);
  GetMem (PP,PT^.PropCount*SizeOf(Pointer));
  J:=GetPropList(PI, [tkClass], PP);
  try
    For I:=0 to J-1 do
    begin
      lProp := PP^[i];
      lNewObject := TVendNode(GetObjectProp(AObject, lProp, TVendNode));
      if Assigned(lNewObject) then
        Result := IterateForHash(lNewObject, AHash, AStopAtItem, AFoundItem);
      if Result <> irNone then
        Exit;
    end;
  finally
    FreeMem(PP);
  end;

end;

function TEnumNode.SearchDuplicate: TEnumNode;
var
  lParent, lResult: TVendNode;
begin
  lParent := Parent;
  Result := nil;
  while Assigned(lParent) do
  begin
    if lParent.Parent = nil then
      Break;
    lParent := lParent.Parent;
  end;
  // ok we found the top level now iterate :(
  if IterateForHash(lParent, GetHashValue, Self, lResult) = irFound then
    Result := TEnumNode(lREsult);

end;

function TEnumNode.FullTypeName: String;
var
  lParent: TVendNode;
begin
  lParent := Parent;
  Result := Name;
  while Assigned(lParent) do
  begin
    if lParent.InheritsFrom(TClassNode) then
      Exit(TClassNode(lParent).FullPathName+'.'+Name);
    lPArent := lParent.Parent;
  end;
end;

{ TClassNode }

function TClassNode.GetRecordObjectClassKeyword: String;
begin
  Result := 'class';
end;

procedure TClassNode.WriteToStream(AStream: TStream);
var
  lItem: TPascalNode;
  lLine, lClassKeyword: String;
begin
   lClassKeyword := GetRecordObjectClassKeyword;
   WriteLine(AStream, '{ '+ FullPathName+ ' }');
   if IsAlias and (List.Count = 0) then
     lLine:= Format('%s = %s', [Name, AncestorClass.Name])
   else begin
     if Assigned(AncestorClass) then
       lLine := Format('%s = %s(%s)', [Name, lClassKeyword, AncestorClass.Name])
     else
       lLine := Format('%s = %s', [Name, lClassKeyword]);
   end;

   // don't write with "end;' just add a semicolon on the same line
   if List.Count = 0 then
   begin
     WriteLine(AStream, lLine+';', 2);
     Exit;
   end;

   WriteLine(AStream, lLine);

   for TVendNode(lItem) in List do
   begin
     lItem.WriteToStream(AStream);
   end;

   WriteLine(AStream, 'end;', 2);

end;

function TClassNode.AddSection(AType: TVisibilityClass): TVisibilityNode;
begin
  case AType of
    vcPublic   : Result := TPublicSection.CreateNew(Self);
    vcPublished: Result := TPublishedSection.CreateNew(Self);
    vcPrivate  : Result := TPrivateSection.CreateNew(Self);
    vcProtected: Result := TProtectedSection.CreateNew(Self);
  else
    raise Exception.Create('unknown visibility type');
  end;
  List.Add(Result);
end;

function TClassNode.FindFirstPublicType(AddIfNotExist: Boolean): TTypeSectionNode;
var
  lSection: TPascalNode;
  i: Integer;
begin
  for i := 0 to List.Count-1 do
  begin
    lSection := List.Item[i];
    if lSection.InheritsFrom(TPublicSection)
    and (TPublicSection(lSection).List.Count > 0)
    and (TPublicSection(lSection).List.Item[0].InheritsFrom(TTypeSectionNode)) then
      Exit(TTypeSectionNode(TPublicSection(lSection).List.Item[0]));
  end;
  Result := nil;

  if (Result = nil) and AddIfNotExist then
  begin
    lSection := TPublicSection.CreateNew(List);
    Result := TPublicSection(lSection).AddTypeSection(True);
    // make sure new types are before possible private sections that declare variables of the type
    //List.Extract(Result); // extract without free
    List.Insert(0, lSection);
  end;
end;

function TClassNode.FindFirstPrivateSection(AddIfNotExist: Boolean;
  AddBeforeOtherSection: TVisibilityNode): TPrivateSection;
var
  lSection: TPascalNode;
  i, lIndex: Integer;
begin
  for i := 0 to List.Count-1 do
  begin
    lSection := List.Item[i];
    if lSection.InheritsFrom(TPrivateSection) then
      Exit(TPrivateSection(lSection));
  end;
  Result := nil;

  if (Result = nil) and AddIfNotExist then
  begin
    lSection := TPrivateSection.CreateNew(List);
    if Assigned(AddBeforeOtherSection) then
    begin
      lIndex := List.IndexOf(AddBeforeOtherSection);
      if lIndex > -1 then
        List.Insert(lIndex, lSection)
      else
        raise Exception.CreateFmt('Attempted to add private section before "%s[%s]" but it''s not a sibling', [FullPathName, AddBeforeOtherSection.ClassName]);
    end
    else
      List.Add(lSection);
    Result := TPrivateSection(lSection);
  end;
end;

function TClassNode.WantVisibiltySection(AVisibility: TVisibilityClass;
  ACreateIfNotExists: Boolean): TVisibilityNode;
begin
  Result := nil;
  if (List.Count = 0) or
  not List.Item[List.Count-1].InheritsFrom(TVisibilityNode)
  or (TVisibilityNode(List.Item[List.Count-1]).Visibility <> AVisibility) then
  begin
    if not ACreateIfNotExists then
      Exit;
    case AVisibility of
      vcPrivate: Result := TPrivateSection.CreateNew(List);
      vcPublished: Result := TPublishedSection.CreateNew(List);
      vcProtected: Result := TProtectedSection.CreateNew(List);
      vcPublic: Result := TPublicSection.CreateNew(List);
    end;
    List.Add(Result);
  end
  else
    Result := TVisibilityNode(List.Item[List.Count-1]);

end;

{ TRecordNode }

function TRecordNode.GetRecordObjectClassKeyword: String;
begin
  Result := 'record'
end;

{ TObjectNode }

function TObjectNode.GetRecordObjectClassKeyword: String;
begin
  Result := 'object';
end;

{ TInterfaceTypeNode }

function TInterfaceTypeNode.GetRecordObjectClassKeyword: String;
begin
  Result := 'interface';
end;

function TInterfaceTypeNode.AddMethod(AKind: TRoutineType; AName: String;
  AReturnType: String): TRoutineNode;
begin
  if AKind = rtFunc then
  begin
    Result := TFunctionNode.CreateNew(Self);
    Result.ReturnValue := TNamedNode.CreateNew(Result);
    Result.ReturnValue.Name := AReturnType;
  end
  else
    Result := TProcedureNode.CreateNew(Self);
  List.Add(Result);
  Result.Name := AName;
end;

procedure TInterfaceTypeNode.WriteToStream(AStream: TStream);
var
  lItem: TPascalNode;
  lLine: String;
begin
  if FIsForward then
  begin
    WriteLine(AStream, Format('%s = interface;', [Name]), 2);
    Exit;
  end;
  if Assigned(AncestorClass) then
    lLine := Format('%s = interface(%s)', [Name, AncestorClass.Name])
  else
    lLine := Format('%s = interface', [Name]);
  WriteLine(AStream, lLine);
  if FIID <> '' then
    WriteLine(AStream, Format('[''%s'']', [FIID]));
  for TVendNode(lItem) in List do
    lItem.WriteToStream(AStream);
  WriteLine(AStream, 'end;', 2);
end;

{ TImplementationNode }

function TImplementationNode.GetIndent: Integer;
begin
  Result:=0;
end;

procedure TImplementationNode.WriteToStream(AStream: TStream);
var
  lItem: TNamedNode;
begin
  inherited WriteToStream(AStream);
  if UsesNode.List.Count > 0 then
     UsesNode.WriteToStream(AStream);

  for lItem in Declarations do
  begin
    lItem.WriteToStream(AStream);
  end;
end;

function TImplementationNode.AddRoutineImplementation(ADecl: TRoutineNode): TRoutineImplNode;
begin
  Result := TRoutineImplNode.CreateNew(Declarations);
  Result.RoutineDeclaration := ADecl;
  Declarations.List.Add(Result);
end;

{ TModeSwitchList }

procedure TModeSwitchList.AddModeSwitch(AString: String);
var
  lMode: TModeSwitchNode;
begin
  lMode := TModeSwitchNode.CreateNew(self);
  lMode.Name:=AString;
  List.Add(lMode);
end;

procedure TModeSwitchList.WriteToStream(const AStream: TStream);
var
  lMode: TModeSwitchNode;
  lLine: RawByteString;
begin
  if List.Count = 0 then
     Exit;
  for Pointer(lMode) in List do
  begin
    TPascalNode(Parent).WriteLine(AStream, lMode.Name);
  end;

  lLine:=LineEnding;
  AStream.Write(lLine[1], Length(lLine));
end;

{ TUnitNode }

procedure TUnitNode.SetInterfaceNode(AValue: TInterfaceNode);
begin
  if FInterfaceNode=AValue then Exit;
  FInterfaceNode:=AValue;
end;

procedure TUnitNode.SetImplentationNode(AValue: TImplementationNode);
begin
  if FImplentationNode=AValue then Exit;
  FImplentationNode:=AValue;
end;

procedure TUnitNode.SetName(AValue: String);
begin
  if FName=AValue then Exit;
  FName:=AValue;
end;

procedure TUnitNode.WriteModeSwitches(AStream: TStream);
begin
  ModeSwitches.WriteToStream(AStream);

end;

procedure TUnitNode.WriteInterface(AStream: TStream);
begin
  FInterfaceNode.WriteToStream(AStream);
end;

procedure TUnitNode.WriteImplementation(AStream: TStream);
begin
  FImplentationNode.WriteToStream(AStream);
end;

procedure TUnitNode.WriteToStream(AStream: TStream);
var
  lLine: RawByteString;
begin
  lLine := Format('unit %s;%s', [Name, LineEnding]);

  WriteLine(AStream, lLine);

  WriteModeSwitches(AStream);
  WriteInterface(AStream);
  WriteImplementation(AStream);


  lLine := Format('%send.', [LineEnding]);
  AStream.Write(lLine[1], Length(lLine));
end;

end.

