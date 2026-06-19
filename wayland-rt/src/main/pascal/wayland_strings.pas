// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

unit wayland_strings;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

resourcestring
  SErrWaylandNotFound = 'Couldn''t find the wayland server';
  SErrUnsupportedObjectForParam = 'Unsupported object[%s] for param %d. Must implement IWaylandBase';
  SErrInt64ParamNotSupported = 'Parameter is Int64[%d] and larger than MaxInt. Must be a 32bit value';
  SErrSizeTooLarge = 'Parameters exceed max size [%d of %d]';
  SErrUnsupportedParamType ='Unsupported parameter type [%d]';
  SErrInvalidInterface = 'Invalid Interface';
  SErrNilParam = 'Parameter [%s] cannot be nil';
  SErrSocketPathTooLong = 'Socket path [%s] is too long (%d bytes, max %d)';
  SErrSocketCreate = 'Failed to create unix socket (errno %d)';
  SErrSocketConnect = 'Failed to connect to [%s] (errno %d)';
  SErrStringTooShort = 'Wayland string length field is %d, must be at least 1 (includes null terminator)';
  SErrSendFdFailed = 'Failed to send file descriptor %d with request (errno %d)';


implementation

end.

