{ bindgen_helpers — small portable utility unit for code that
  consumes pascal_bindgen output.

  Lives outside the generator on purpose: every binding ships its
  own self-contained .pas, and this unit handles the awkward bits
  that don't belong in machine-generated code:

  * MaskCFpuExceptions — call once at program start before driving
    any C library that does IEEE-754 math (GTK/Cairo/most game
    code). FPC defaults to all-unmasked, which raises EZeroDivide
    on entirely-legal C float math like 1.0/0.0.

  * CStrToString / StringToCStr — convert between FPC AnsiString
    and a NUL-terminated PAnsiChar without surprises around
    lifetime or encoding.

  * CharArrayToString — pull a Pascal string out of a fixed-size
    C-style char array field (VkPhysicalDeviceProperties.deviceName,
    struct utsname, ...). Stops at the first NUL or end-of-array.

  * MakeVaList / VaListToPointer — interop with the C va_list type
    the emitter generates. SysV x86_64 needs a 24-byte stack-allocated
    struct; other targets are pointer-sized. These wrappers hide the
    target-specific knowledge so user code stays portable.

  The unit is dependency-light: only ctypes + the user's generated
  binding unit (passed as a generic-style include path). It compiles
  in objfpc and delphi modes and should also work under Blaise. }
unit bindgen_helpers;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

interface

uses
  ctypes, SysUtils, Math;

{ Mask every FPC-default-unmasked FPU exception so the host C
  library can do unguarded float math. Idempotent. }
procedure MaskCFpuExceptions;

{ Copy a NUL-terminated C string into a Pascal AnsiString. Empty
  result for nil. Safe to call on freshly-returned PAnsiChar — the
  copy means you can dispose of the C buffer afterwards. }
function CStrToString(P: PAnsiChar): string;

{ Reverse direction — returns a PAnsiChar that points at S's
  internal buffer. The pointer is valid until S goes out of scope
  or is mutated; if you need a longer-lived buffer, use
  StringToCStrDup which malloc's a fresh copy. }
function StringToCStr(const S: string): PAnsiChar;
function StringToCStrDup(const S: string): PAnsiChar;
procedure FreeCStrDup(P: PAnsiChar);

{ Pull a Pascal string out of a fixed-size cchar array field. Stops
  at the first NUL byte. Works for any array length. }
function CharArrayToString(const Arr; ArrLen: Integer): string;

{ va_list helpers — only meaningful when the generated binding
  pulled in the `va_list` typedef. The target-aware switch matches
  bindgen.emit.fpc's emitted definition. }
type
  { Mirrors what the emitter generates. Duplicated here so user
    code doesn't have to import the binding unit just for the type. }
{$IFDEF CPUX86_64}{$IFDEF UNIX}
  T__va_list_tag = record
    gp_offset, fp_offset: cuint;
    overflow_arg_area, reg_save_area: Pointer;
  end;
  Tva_list = array[0..0] of T__va_list_tag;
{$ELSE}
  Tva_list = PAnsiChar;
{$ENDIF}{$ELSE}
  Tva_list = PAnsiChar;
{$ENDIF}

{ Take the address of a va_list local and hand it to a C function
  expecting `va_list` (which is the [1]-array decay form on SysV).
  On non-SysV platforms va_list is already pointer-sized and this
  reduces to a pass-through. }
function VaListPtr(var V: Tva_list): Pointer;

implementation

procedure MaskCFpuExceptions;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
                    exOverflow, exUnderflow, exPrecision]);
end;

function CStrToString(P: PAnsiChar): string;
begin
  if P = nil then Result := '' else Result := string(P);
end;

function StringToCStr(const S: string): PAnsiChar;
begin
  if S = '' then Result := nil else Result := PAnsiChar(S);
end;

function StringToCStrDup(const S: string): PAnsiChar;
var
  n: PtrUInt;
begin
  n := Length(S);
  Result := GetMem(n + 1);
  if n > 0 then Move(S[1], Result^, n);
  Result[n] := #0;
end;

procedure FreeCStrDup(P: PAnsiChar);
begin
  if P <> nil then FreeMem(P);
end;

function CharArrayToString(const Arr; ArrLen: Integer): string;
var
  P: PAnsiChar;
  n: Integer;
begin
  P := PAnsiChar(@Arr);
  n := 0;
  while (n < ArrLen) and (P[n] <> #0) do Inc(n);
  SetLength(Result, n);
  if n > 0 then Move(P^, Result[1], n);
end;

function VaListPtr(var V: Tva_list): Pointer;
begin
{$IFDEF CPUX86_64}{$IFDEF UNIX}
  Result := @V[0];
{$ELSE}
  Result := @V;
{$ENDIF}{$ELSE}
  Result := @V;
{$ENDIF}
end;

end.
