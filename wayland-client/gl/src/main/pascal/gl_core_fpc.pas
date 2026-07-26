// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ gl_core_fpc — the OpenGL 3.3 core entry points that gl_fpc does not declare.

  gl_fpc is generated from /usr/include/GL/gl.h, which stops at GL 1.3: it has
  the textures, blending, scissor and draw calls we need, but nothing from the
  programmable pipeline (shaders, VBOs, VAOs) or the framebuffer object
  extension. libGL.so does not export those as ordinary symbols on every
  driver either — they are meant to be resolved through the platform's
  get-proc-address hook — so they are declared here as function-pointer
  VARIABLES and populated by LoadGLCore.

  Because they are variables, `uses gl_fpc, gl_core_fpc;` (in that order) makes
  a call like glCreateShader(...) resolve to the pointer declared here while
  glTexImage2D(...) still resolves to the real import in gl_fpc.

  LoadGLCore must be called with a current GL context. Pass it whatever
  get-proc-address function the platform provides — eglGetProcAddress for
  our EGL contexts. It raises EGLCoreLoad naming the first entry point the
  driver could not supply, rather than leaving a nil pointer to crash later. }
unit gl_core_fpc;

{$mode ObjFPC}{$H+}
{$PACKRECORDS C}

interface

uses
  SysUtils, ctypes, gl_fpc;

type
  EGLCoreLoad = class(Exception);

  // GL 3.x scalar types absent from the 1.3 header.
  GLchar = AnsiChar;
  PGLchar = ^GLchar;
  PPGLchar = ^PGLchar;
  GLsizeiptr = PtrInt;
  GLintptr = PtrInt;
  PGLsizei = ^GLsizei;

  // Signature of the platform's get-proc-address hook (eglGetProcAddress).
  TGLGetProcAddress = function(const AName: String): Pointer of object;

const
  // --- shader objects (GL 2.0) ---
  GL_FRAGMENT_SHADER  = $8B30;
  GL_VERTEX_SHADER    = $8B31;
  GL_COMPILE_STATUS   = $8B81;
  GL_LINK_STATUS      = $8B82;
  GL_INFO_LOG_LENGTH  = $8B84;

  // --- buffer objects (GL 1.5) ---
  GL_ARRAY_BUFFER         = $8892;
  GL_ELEMENT_ARRAY_BUFFER = $8893;
  GL_STREAM_DRAW          = $88E0;
  GL_STATIC_DRAW          = $88E4;
  GL_DYNAMIC_DRAW         = $88E8;

  // --- framebuffer objects (GL 3.0 / EXT_framebuffer_object) ---
  GL_FRAMEBUFFER          = $8D40;
  GL_COLOR_ATTACHMENT0    = $8CE0;
  GL_FRAMEBUFFER_COMPLETE = $8CD5;
  GL_FRAMEBUFFER_BINDING  = $8CA6;

  // --- sized single-channel format (GL 3.0), used for the glyph atlas ---
  GL_R8 = $8229;

type
  // --- buffer objects ---
  TglGenBuffers    = procedure(n: GLsizei; buffers: PGLuint); cdecl;
  TglDeleteBuffers = procedure(n: GLsizei; buffers: PGLuint); cdecl;
  TglBindBuffer    = procedure(target: GLenum; buffer: GLuint); cdecl;
  TglBufferData    = procedure(target: GLenum; size: GLsizeiptr; data: Pointer; usage: GLenum); cdecl;
  TglBufferSubData = procedure(target: GLenum; offset: GLintptr; size: GLsizeiptr; data: Pointer); cdecl;

  // --- vertex array objects ---
  TglGenVertexArrays    = procedure(n: GLsizei; arrays: PGLuint); cdecl;
  TglDeleteVertexArrays = procedure(n: GLsizei; arrays: PGLuint); cdecl;
  TglBindVertexArray    = procedure(arr: GLuint); cdecl;

  // --- vertex attributes ---
  TglEnableVertexAttribArray  = procedure(index: GLuint); cdecl;
  TglDisableVertexAttribArray = procedure(index: GLuint); cdecl;
  TglVertexAttribPointer      = procedure(index: GLuint; size: GLint; atype: GLenum;
    normalized: GLboolean; stride: GLsizei; offset: Pointer); cdecl;

  // --- shaders ---
  TglCreateShader     = function(shaderType: GLenum): GLuint; cdecl;
  TglDeleteShader     = procedure(shader: GLuint); cdecl;
  TglShaderSource     = procedure(shader: GLuint; count: GLsizei; str: PPGLchar; length: PGLint); cdecl;
  TglCompileShader    = procedure(shader: GLuint); cdecl;
  TglGetShaderiv      = procedure(shader: GLuint; pname: GLenum; params: PGLint); cdecl;
  TglGetShaderInfoLog = procedure(shader: GLuint; maxLength: GLsizei; length: PGLsizei; infoLog: PGLchar); cdecl;

  // --- programs ---
  TglCreateProgram      = function: GLuint; cdecl;
  TglDeleteProgram      = procedure(program_: GLuint); cdecl;
  TglAttachShader       = procedure(program_, shader: GLuint); cdecl;
  TglLinkProgram        = procedure(program_: GLuint); cdecl;
  TglUseProgram         = procedure(program_: GLuint); cdecl;
  TglGetProgramiv       = procedure(program_: GLuint; pname: GLenum; params: PGLint); cdecl;
  TglGetProgramInfoLog  = procedure(program_: GLuint; maxLength: GLsizei; length: PGLsizei; infoLog: PGLchar); cdecl;
  TglBindAttribLocation = procedure(program_: GLuint; index: GLuint; name: PGLchar); cdecl;
  TglGetUniformLocation = function(program_: GLuint; name: PGLchar): GLint; cdecl;
  TglBindFragDataLocation = procedure(program_: GLuint; colorNumber: GLuint; name: PGLchar); cdecl;

  // --- uniforms ---
  TglUniform1i        = procedure(location: GLint; v0: GLint); cdecl;
  TglUniform1f        = procedure(location: GLint; v0: GLfloat); cdecl;
  TglUniform2f        = procedure(location: GLint; v0, v1: GLfloat); cdecl;
  TglUniform4f        = procedure(location: GLint; v0, v1, v2, v3: GLfloat); cdecl;
  TglUniformMatrix4fv = procedure(location: GLint; count: GLsizei; transpose: GLboolean; value: PGLfloat); cdecl;

  // --- framebuffer objects ---
  TglGenFramebuffers        = procedure(n: GLsizei; framebuffers: PGLuint); cdecl;
  TglDeleteFramebuffers     = procedure(n: GLsizei; framebuffers: PGLuint); cdecl;
  TglBindFramebuffer        = procedure(target: GLenum; framebuffer: GLuint); cdecl;
  TglFramebufferTexture2D   = procedure(target, attachment, textarget: GLenum; texture: GLuint; level: GLint); cdecl;
  TglCheckFramebufferStatus = function(target: GLenum): GLenum; cdecl;

  // --- separate blend function (GL 1.4) ---
  TglBlendFuncSeparate = procedure(srcRGB, dstRGB, srcAlpha, dstAlpha: GLenum); cdecl;

var
  glGenBuffers:    TglGenBuffers;
  glDeleteBuffers: TglDeleteBuffers;
  glBindBuffer:    TglBindBuffer;
  glBufferData:    TglBufferData;
  glBufferSubData: TglBufferSubData;

  glGenVertexArrays:    TglGenVertexArrays;
  glDeleteVertexArrays: TglDeleteVertexArrays;
  glBindVertexArray:    TglBindVertexArray;

  glEnableVertexAttribArray:  TglEnableVertexAttribArray;
  glDisableVertexAttribArray: TglDisableVertexAttribArray;
  glVertexAttribPointer:      TglVertexAttribPointer;

  glCreateShader:     TglCreateShader;
  glDeleteShader:     TglDeleteShader;
  glShaderSource:     TglShaderSource;
  glCompileShader:    TglCompileShader;
  glGetShaderiv:      TglGetShaderiv;
  glGetShaderInfoLog: TglGetShaderInfoLog;

  glCreateProgram:         TglCreateProgram;
  glDeleteProgram:         TglDeleteProgram;
  glAttachShader:          TglAttachShader;
  glLinkProgram:           TglLinkProgram;
  glUseProgram:            TglUseProgram;
  glGetProgramiv:          TglGetProgramiv;
  glGetProgramInfoLog:     TglGetProgramInfoLog;
  glBindAttribLocation:    TglBindAttribLocation;
  glGetUniformLocation:    TglGetUniformLocation;
  glBindFragDataLocation:  TglBindFragDataLocation;

  glUniform1i:        TglUniform1i;
  glUniform1f:        TglUniform1f;
  glUniform2f:        TglUniform2f;
  glUniform4f:        TglUniform4f;
  glUniformMatrix4fv: TglUniformMatrix4fv;

  glGenFramebuffers:        TglGenFramebuffers;
  glDeleteFramebuffers:     TglDeleteFramebuffers;
  glBindFramebuffer:        TglBindFramebuffer;
  glFramebufferTexture2D:   TglFramebufferTexture2D;
  glCheckFramebufferStatus: TglCheckFramebufferStatus;

  glBlendFuncSeparate: TglBlendFuncSeparate;

// Populate every pointer above. Requires a current context. Raises EGLCoreLoad
// naming the first entry point the driver did not supply. Idempotent.
procedure LoadGLCore(AGetProc: TGLGetProcAddress);
// True once LoadGLCore has completed successfully.
function GLCoreLoaded: Boolean;

implementation

var
  FLoaded: Boolean = False;

function GLCoreLoaded: Boolean;
begin
  Result := FLoaded;
end;

procedure LoadGLCore(AGetProc: TGLGetProcAddress);

  function Req(const AName: String): Pointer;
  begin
    Result := AGetProc(AName);
    if Result = nil then
      raise EGLCoreLoad.CreateFmt(
        'OpenGL entry point "%s" is not available; a GL 3.3 core context is required', [AName]);
  end;

begin
  if FLoaded then
    Exit;

  glGenBuffers    := TglGenBuffers(Req('glGenBuffers'));
  glDeleteBuffers := TglDeleteBuffers(Req('glDeleteBuffers'));
  glBindBuffer    := TglBindBuffer(Req('glBindBuffer'));
  glBufferData    := TglBufferData(Req('glBufferData'));
  glBufferSubData := TglBufferSubData(Req('glBufferSubData'));

  glGenVertexArrays    := TglGenVertexArrays(Req('glGenVertexArrays'));
  glDeleteVertexArrays := TglDeleteVertexArrays(Req('glDeleteVertexArrays'));
  glBindVertexArray    := TglBindVertexArray(Req('glBindVertexArray'));

  glEnableVertexAttribArray  := TglEnableVertexAttribArray(Req('glEnableVertexAttribArray'));
  glDisableVertexAttribArray := TglDisableVertexAttribArray(Req('glDisableVertexAttribArray'));
  glVertexAttribPointer      := TglVertexAttribPointer(Req('glVertexAttribPointer'));

  glCreateShader     := TglCreateShader(Req('glCreateShader'));
  glDeleteShader     := TglDeleteShader(Req('glDeleteShader'));
  glShaderSource     := TglShaderSource(Req('glShaderSource'));
  glCompileShader    := TglCompileShader(Req('glCompileShader'));
  glGetShaderiv      := TglGetShaderiv(Req('glGetShaderiv'));
  glGetShaderInfoLog := TglGetShaderInfoLog(Req('glGetShaderInfoLog'));

  glCreateProgram        := TglCreateProgram(Req('glCreateProgram'));
  glDeleteProgram        := TglDeleteProgram(Req('glDeleteProgram'));
  glAttachShader         := TglAttachShader(Req('glAttachShader'));
  glLinkProgram          := TglLinkProgram(Req('glLinkProgram'));
  glUseProgram           := TglUseProgram(Req('glUseProgram'));
  glGetProgramiv         := TglGetProgramiv(Req('glGetProgramiv'));
  glGetProgramInfoLog    := TglGetProgramInfoLog(Req('glGetProgramInfoLog'));
  glBindAttribLocation   := TglBindAttribLocation(Req('glBindAttribLocation'));
  glGetUniformLocation   := TglGetUniformLocation(Req('glGetUniformLocation'));
  glBindFragDataLocation := TglBindFragDataLocation(Req('glBindFragDataLocation'));

  glUniform1i        := TglUniform1i(Req('glUniform1i'));
  glUniform1f        := TglUniform1f(Req('glUniform1f'));
  glUniform2f        := TglUniform2f(Req('glUniform2f'));
  glUniform4f        := TglUniform4f(Req('glUniform4f'));
  glUniformMatrix4fv := TglUniformMatrix4fv(Req('glUniformMatrix4fv'));

  glGenFramebuffers        := TglGenFramebuffers(Req('glGenFramebuffers'));
  glDeleteFramebuffers     := TglDeleteFramebuffers(Req('glDeleteFramebuffers'));
  glBindFramebuffer        := TglBindFramebuffer(Req('glBindFramebuffer'));
  glFramebufferTexture2D   := TglFramebufferTexture2D(Req('glFramebufferTexture2D'));
  glCheckFramebufferStatus := TglCheckFramebufferStatus(Req('glCheckFramebufferStatus'));

  glBlendFuncSeparate := TglBlendFuncSeparate(Req('glBlendFuncSeparate'));

  FLoaded := True;
end;

end.
