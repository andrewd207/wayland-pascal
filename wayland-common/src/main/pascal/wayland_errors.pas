// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

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

