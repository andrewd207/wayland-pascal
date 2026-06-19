// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{

This unit should be able to read all elements and attributes of a Wayland XML
protocol file.

The root node and starting point is TWIProtocolNode.
}
unit wayland_interface_reader;

{$mode ObjFPC}{$H+}
{$ModeSwitch typehelpers on}

interface

uses
  Classes, SysUtils, XMLRead, DOM, fgl;

type


  { TWIBaseNode }

  TWIBaseNode = class
  protected
    FNode: TDOMElement;
    procedure ReadElements; virtual;
    function HandleNode(ANode: TDOMElement): Boolean; virtual;
  public
    constructor Create(ANode: TDOMElement);
  end;

  { TWITextContentNode }

  TWITextContentNode = class(TWIBaseNode)
  private
    function GetValue: String;
  published
    property Value: String read GetValue;
  end;

  TWICopyrightNode = class(TWITextContentNode);


  { TWIDescriptionNode }

  TWIDescriptionNode = class(TWITextContentNode)
  private
    function GetSummary: String;
  public
    property Summary: String read GetSummary;
  end;

  { TWiNamedNode }

  TWiNamedNode = class(TWIBaseNode)
  private
    function GetName: String;
  public
    property Name: String read GetName;
  end;

  { TWiNamedWithDescNode }

  TWiNamedWithDescNode = class(TWiNamedNode)
  private
    FDescription: TWIDescriptionNode;
  protected
    function HandleNode(ANode: TDOMElement): Boolean; override;
  published
    property Description: TWIDescriptionNode read FDescription;
  end;

  { TWIArgNode }

  TWIArgNode = class(TWiNamedNode)
  private
    function GetAllow_Null: Boolean;
    function GetEnum: String;
    function GetInterface: String;
    function GetSummary: String;
    function GetType: String;
  published
    property Name;
    property Type_: String read GetType;
    property Summary: String read GetSummary;
    property Interface_: String read GetInterface;
    property Enum: String read GetEnum;
    property Allow_Null: Boolean read GetAllow_Null;
  end;

  TWIArgList = specialize TFPGObjectList<TWIArgNode>;

  { TWIArgListHelper }

  TWIArgListHelper = class helper for TWIArgList
    function Signature: String;
  end;

  { TWIRequestNode }

  TWIRequestNode = class(TWiNamedWithDescNode)
  private
    FArgs: TWIArgList;
    function GetType: String;
  protected
    procedure ReadElements; override;
    function HandleNode(ANode: TDOMElement): Boolean; override;
  public
    property Name;
    property Description;
    property Type_: String read GetType;
    property Args: TWIArgList read FArgs;
    destructor Destroy; override;
  end;

  TWIRequestList = specialize TFPGObjectList<TWIRequestNode>;

  { TWIEventNode }

  TWIEventNode = class(TWiNamedWithDescNode)
  private
    FArgs: TWIArgList;
  protected
    procedure ReadElements; override;
    function HandleNode(ANode: TDOMElement): Boolean; override;
  public
    property Name;
    property Description;
    property Args: TWIArgList read FArgs;
  end;

  TWIEventList = specialize TFPGObjectList<TWIEventNode>;

  { TWIEntry }

  TWIEntry = class(TWiNamedWithDescNode)
  private
    function GetSummary: String;
    function GetValue: Integer;
  public
    property Name;
    property Summary: String read GetSummary;
    property Value: Integer read GetValue;
  end;

  TWIEntryList = specialize TFPGObjectList<TWIEntry>;


  { TWIEnumNode }

  TWIEnumNode = class(TWiNamedWithDescNode)
  private
    FEntries: TWIEntryList;
    function GetIsBitfield: Boolean;
  protected
    procedure ReadElements; override;
    function HandleNode(ANode: TDOMElement): Boolean; override;
  public
    property Name;
    property Description;
    property IsBitfield: Boolean read GetIsBitfield;
    property Entries: TWIEntryList read FEntries;
    destructor Destroy; override;
  end;

  TWIEnumList = specialize TFPGObjectList<TWIEnumNode>;

  { TWInterfaceNode }

  TWInterfaceNode = class(TWiNamedWithDescNode)
  private
    FRequests : TWIRequestList;
    FEvents   : TWIEventList;
    FEnums    : TWIEnumList;
    function GetVersion: Integer;
  protected
    FId: Integer; // a registered interface
    procedure ReadElements; override;
    function HandleNode(ANode: TDOMElement): Boolean; override;

  public
    property Name;
    property Description;
    property Version: Integer read GetVersion;
    property Requests: TWIRequestList read FRequests;
    property Events: TWIEventList read FEvents;
    property Enums: TWIEnumList read FEnums;
    destructor Destroy; override;
    procedure SetObjectId(AValue: Integer);
    procedure ReadEvent(AOpcode: Word; AData: TMemoryStream);
  end;

  TWInterfaceNodeList = specialize TFPGObjectList<TWInterfaceNode>;

  { TWInterfaceNodeListHelper }

  TWInterfaceNodeListHelper = class helper for TWInterfaceNodeList
    function ObjectFromId(AId: Integer): TWInterfaceNode;
    function ObjectFromName(AName: String): TWInterfaceNode;
  end;


  { TWIProtocolNode }

  TWIProtocolNode = class(TWIBaseNode)
  private
    FDoc: TXMLDocument;
    FCopyright: TWICopyrightNode;
    FDescription: TWIDescriptionNode;
    FInterfaces: TWInterfaceNodeList;
    function GetName: String;
  protected
    procedure ReadElements; override;
    function HandleNode(ANode: TDOMElement): Boolean; override;
  public
    property Copyright: TWICopyrightNode read FCopyright;
    property Description: TWIDescriptionNode read FDescription;
    property Interfaces: TWInterfaceNodeList read FInterfaces;
    property Name: String read GetName;
    constructor Create(AFileName: String);
    destructor Destroy; override;

  end;


implementation

{ TWInterfaceNodeListHelper }

function TWInterfaceNodeListHelper.ObjectFromId(AId: Integer): TWInterfaceNode;
var
  lItem: TWInterfaceNode;
begin
  for lItem in Self do
    begin
      if lItem.FId = AId then
        Exit(lItem);
    end;
  Result := nil;
end;

function TWInterfaceNodeListHelper.ObjectFromName(AName: String
  ): TWInterfaceNode;
var
  lItem: TWInterfaceNode;
begin
  for lItem in Self do
    begin
      if lItem.Name = AName then
        Exit(lItem);
    end;
  Result := nil;
end;

{ TWIArgListHelper }

function TWIArgListHelper.Signature: String;
var
  lArg: TWIArgNode;
begin
  Result := '';
  for lArg in Self do
  begin
    if lArg.Allow_Null then Result += '?';
    case lArg.Type_ of
      'int': Result += 'i';
      'uint': Result += 'u';
      'fixed': Result += 'f';
      'object': Result += 'o';
      'new_id': Result += 'n';
      'string': Result += 's';
      'array': Result += 'a';
      'fd': Result +='h';
      'enum': Result += 'e';
    end;
  end;


end;

{ TWIEnumNode }

function TWIEnumNode.GetIsBitfield: Boolean;
begin
  Result := FNode.GetAttribute('bitfield') = 'true';
end;

procedure TWIEnumNode.ReadElements;
begin
  FEntries := TWIEntryList.Create(True);
  inherited ReadElements;
end;

function TWIEnumNode.HandleNode(ANode: TDOMElement): Boolean;
begin
  Result:=inherited HandleNode(ANode);
  if not Result then
    case ANode.NodeName of
      'entry' : FEntries.Add(TWIEntry.Create(ANode));
    else
      Exit(False);
    end;
  Result := True;
end;

destructor TWIEnumNode.Destroy;
begin
  FreeAndNil(FEntries);
  inherited Destroy;
end;

{ TWIEntry }

function TWIEntry.GetSummary: String;
begin
  Result := FNode.GetAttribute('summary');
end;

function TWIEntry.GetValue: Integer;
var
  lValue: DOMString;
begin
  lValue := FNode.GetAttribute('value');
  Result := StrToInt(lValue);
end;

{ TWIEventNode }

procedure TWIEventNode.ReadElements;
begin
  FArgs := TWIArgList.Create(True);
  inherited ReadElements;
end;

function TWIEventNode.HandleNode(ANode: TDOMElement): Boolean;
begin
  Result:=inherited HandleNode(ANode);
  if not Result then
    case ANode.NodeName of
      'arg': FArgs.Add(TWIArgNode.Create(ANode));
    else
      Exit(False);
    end;
  Result := True;
end;

{ TWiNamedWithDescNode }

function TWiNamedWithDescNode.HandleNode(ANode: TDOMElement): Boolean;
begin
  Result:=inherited HandleNode(ANode);
  if not Result and (ANode.NodeName = 'description') then
  begin
    FDescription := TWIDescriptionNode.Create(ANode);
    Result := True;
  end;
end;

{ TWIRequestNode }

function TWIRequestNode.GetType: String;
begin
  Result := FNode.GetAttribute('type');
end;

procedure TWIRequestNode.ReadElements;
begin
  FArgs := TWIArgList.Create(True);
  inherited ReadElements;
end;

function TWIRequestNode.HandleNode(ANode: TDOMElement): Boolean;
begin
  Result:=inherited HandleNode(ANode);
  if not Result then
    case ANode.NodeName of
      'arg': FArgs.Add(TWIArgNode.Create(ANode));
    else
      Exit(False);
    end;
  Result := True;
end;

destructor TWIRequestNode.Destroy;
begin
  FreeAndNil(FArgs);
  FreeAndNil(FDescription);
  inherited Destroy;
end;

{ TWIArgNode }

function TWIArgNode.GetAllow_Null: Boolean;
begin
  Result := FNode.GetAttribute('allow-null') = 'true'
end;

function TWIArgNode.GetEnum: String;
begin
  Result := FNode.AttribStrings['enum'];
end;

function TWIArgNode.GetInterface: String;
begin
  Result := FNode.GetAttribute('interface');
end;

function TWIArgNode.GetSummary: String;
begin
  Result := FNode.GetAttribute('summary');
end;

function TWIArgNode.GetType: String;
begin
  Result := FNode.GetAttribute('type');
end;

{ TWiNamedNode }

function TWiNamedNode.GetName: String;
begin
  Result := FNode.GetAttribute('name');
end;

{ TWInterfaceNode }

function TWInterfaceNode.GetVersion: Integer;
var
  lValue: DOMString;
begin
  lValue := FNode.GetAttribute('version');
  Result := StrToInt(lValue);
end;

procedure TWInterfaceNode.ReadElements;
begin
  FRequests := TWIRequestList.Create(True);
  FEvents := TWIEventList.Create(True);
  FEnums := TWIEnumList.Create(True);
  inherited ReadElements;
end;

function TWInterfaceNode.HandleNode(ANode: TDOMElement): Boolean;
begin
  Result:=inherited HandleNode(ANode);
  if not Result then
    case ANode.NodeName of
      'request': FRequests.Add(TWIRequestNode.Create(ANode));
      'event'  : FEvents.Add(TWIEventNode.Create(ANode));
      'enum'   : FEnums.Add(TWIEnumNode.Create(ANode));
    else
      Exit(False);
    end;
  Result := True;
end;

procedure TWInterfaceNode.ReadEvent(AOpcode: Word; AData: TMemoryStream);
var
  lEvent: TWIEventNode;
  lArg: TWIArgNode;
  lLength: Cardinal;
  i: Integer;
  lMessage: String;
begin


  lEvent := FEvents.Items[AOpcode];
  WriteLn(lEvent.Name, ' called with opcode ', AOpcode);
  for lArg in lEvent.Args do
  begin
    case lArg.Type_ of
      'object': {WriteLn(lArg.Name,'=',}( AData.ReadDWord);
      'uint': {WriteLn(lArg.Name,'=',}( AData.ReadDWord);
      'string':
         begin
           lLength := AData.ReadDWord;
           SetLength(lMessage, lLength-1);
           AData.Read(lMessage[1], lLength-1);
           WriteLN(lArg.Name,'=',lMessage);
           for i := 0 to 3-((lLength-1) mod 4) do
            AData.ReadByte;
          end;
      end;
    end;
end;

destructor TWInterfaceNode.Destroy;
begin
  FreeAndNil(FRequests);
  FreeAndNil(FEvents);
  FreeAndNil(FEnums);
  inherited Destroy;
end;

procedure TWInterfaceNode.SetObjectId(AValue: Integer);
begin
  FId:=AValue;
end;

{ TWIProtocolNode }

function TWIProtocolNode.GetName: String;
begin
  Result := FNode.GetAttribute('name');
end;

procedure TWIProtocolNode.ReadElements;
var
  lChild: TDOMElement;
begin
  FInterfaces := TWInterfaceNodeList.Create(True);
  inherited ReadElements;
end;

function TWIProtocolNode.HandleNode(ANode: TDOMElement): Boolean;
begin
  Result:=inherited HandleNode(ANode);
  if not Result then
    case ANode.NodeName of
      'copyright'   : FCopyright := TWICopyrightNode.Create(ANode);
      'description' : FDescription := TWIDescriptionNode.Create(ANode);
      'interface'   : FInterfaces.Add(TWInterfaceNode.Create(ANode));
    else
      Exit(False);
    end;
  Result := True;
end;

constructor TWIProtocolNode.Create(AFileName: String);
begin
  ReadXMLFile(FDoc, AFileName);
  // Make sure this is actually a Wayland protocol file before parsing. The
  // root element of a Wayland protocol XML is <protocol>; anything else (e.g.
  // an FPDoc <package> doc) would otherwise crash deep in element handling
  // with a confusing "unhandled node" error.
  if FDoc.DocumentElement = nil then
    raise Exception.CreateFmt('Not a Wayland protocol XML: %s (no root element)', [AFileName]);
  if FDoc.DocumentElement.NodeName <> 'protocol' then
    raise Exception.CreateFmt(
      'Not a Wayland protocol XML: %s (root element is <%s>, expected <protocol>)',
      [AFileName, FDoc.DocumentElement.NodeName]);
  inherited Create(FDoc.DocumentElement);
end;

destructor TWIProtocolNode.Destroy;
begin
  FreeAndNil(FCopyright);
  FreeAndNil(FDescription);
  FreeAndNil(FInterfaces);
  FreeAndNil(FDoc);
  inherited Destroy;
end;

{ TWITextContentNode }

function TWITextContentNode.GetValue: String;
begin
  Result := FNode.TextContent;
end;

{ TWIBaseNode }

procedure TWIBaseNode.ReadElements;
var
  lChild: TDOMElement;
begin
  lChild := TDOMElement(FNode.FirstChild);
  while Assigned(lChild) do
  begin
    if lChild.NodeType = ELEMENT_NODE then
      if not HandleNode(lChild) then
        raise Exception.CreateFmt('%s: unhandled node type: %s', [ClassName, lChild.NodeName]);
    lChild := TDOMElement(lChild.NextSibling);
  end;
end;

function TWIBaseNode.HandleNode(ANode: TDOMElement): Boolean;
begin
  Result := False;
end;

constructor TWIBaseNode.Create(ANode: TDOMElement);
begin
  FNode := ANode;
  ReadElements;
end;

{ TWIDescriptionNode }
function TWIDescriptionNode.GetSummary: String;
begin
  Result := FNode.GetAttribute('summary');
end;

end.

