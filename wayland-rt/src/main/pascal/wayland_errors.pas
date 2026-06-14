unit wayland_errors;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

type
  EWaylandError = class(Exception);
  EWaylandConnectionError = class(EWaylandError);
  EWaylandParamError = class(EWaylandError);

implementation

end.

