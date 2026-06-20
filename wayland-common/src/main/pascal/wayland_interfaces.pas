// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

unit wayland_interfaces;


{

only auto generated interfaces and methods/constants should be here
next step is cleanup and autogenerating interfaces

}

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, wayland_internal_interfaces;

//type

  {IWaylandRegistry = interface;
  //IWaylandDisplay = interface;

  IWaylandCallBack = interface(IWaylandBase)
  ['{C7C3884D-13E4-4A3A-AA71-310A39E83598}']
  end;

  { IWaylandRegistry }

  IWaylandRegistry = interface(IWaylandBase)
  ['{17B26648-2B81-4A77-A9F2-313C290B8F6A}']
    procedure Bind(ANameIndex: Integer; AInterfaceName: String; AVersion: Integer; AObjectID: Integer);
  end;
  }


 { IWaylandDisplay = interface(IWaylandDisplayCore)
  ['{583D9472-AFA0-40C8-BABF-AF112C87619F}']
    procedure Sync;
    function  GetRegistry: IWaylandRegistry;
  end;}

implementation



end.

