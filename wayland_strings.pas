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


implementation

end.

