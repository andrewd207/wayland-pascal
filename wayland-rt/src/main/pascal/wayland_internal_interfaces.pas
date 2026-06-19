// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

unit wayland_internal_interfaces;
{

  these are internal interfaces that are useful to this implementation but not
  part of the official wayland.

  These exist to keep circular dependancies from happening

  Fair warning: The reference counting is disabled, the interfaces won't free themselves!

}

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, wayland_queue;

type
  IWaylandEventQueue = interface; // forward
  IWaylandBase = interface
  ['{6E976C30-026E-4C84-A725-F50DC6188E8E}']
    function GetObjectId: Integer;
    procedure SetObjectId(AValue: Integer);
    procedure SetQueue(AQueue: IWaylandEventQueue); //
    procedure SetProtocolVersion(AValue: Integer);
    function GetQueue: IWaylandEventQueue; //
    //function GetInterfaceName: String;
    //function GetInterfaceVersion: Integer;
  end;

  // this event queue can be internal and doesn't need to be an interface
  IWaylandEventQueue = interface
  ['{EE7065A6-EF13-45A2-824D-1674F3927D19}']
   // procedure SetSocket(ASocket: TUnixSocket);
    procedure AssignObject(AObject: IWaylandBase); // events recieved for this object will come to this queue
    procedure RemoveObject(AObject: IWaylandBase);
    procedure Flush; //send all messages
    //procedure SendEvents(AValue: Boolean); // use a thread to dispatch messages as they arrive
    // outgoing
    procedure Enqueue(const AData: TWaylandEventMessage; AForObject: IWaylandBase);
    function  Dequeue(var Data: TWaylandEventMessage; var ADestObject: IWaylandBase; ATimeout: Integer = INFINITE): Boolean;
    function DispatchEvent(ATimeout: Integer = 0): Boolean; // calls dequeue and sends the event
  end;

  // this whole interface should just be private/protected and part of display base
  IWaylandDisplayCore = interface(IWaylandBase)
  ['{57BCD8D8-50B1-4C65-B7A8-CFA6D36F77DC}']
    procedure RegisterObject(AObject: IWaylandBase; AUseID: Integer = -1);
    procedure ObjectDestroying(AObjectID: Integer; AFromDestructor: Boolean);
    function GetObject(AObjectID: DWord): IWaylandBase;
    procedure SendRequest(AObjectID: DWord; ARequest: Word; Data: Array of Const; AFdIndex: Integer = -1); // again, should be protected
    function WaitMessage(ATimeOut: Integer): Boolean; // this is flawed or at least it should not be exposed?
  end;


implementation

end.

