// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wayland_gl_canvas — the OpenGL implementation of TWaylandAccelCanvas.

  All the geometry has already happened by the time anything here runs:
  TWaylandAccelCanvas turned rectangles, arcs, strokes, glyphs and blits into
  triangles with device-space positions, surface-normalised UVs and
  premultiplied per-vertex colours. This unit only has to get those triangles
  onto the GPU, which it does with one shader, one streaming vertex buffer and
  a texture cache.

  BATCHING happens here rather than in the base class. Consecutive
  DeviceDrawTriangles calls that use the same texture and mode are concatenated
  into one buffer and issued as a single glDrawArrays; the batch is flushed only
  when the texture, the blend mode or the clip changes, or the frame ends. A
  window full of rectangles is therefore one draw call, and a paragraph of text
  is one more.

  ANTI-ALIASING is supersampling. The canvas renders into an offscreen target
  SuperSample times larger in each axis, then resolves it down to the
  presentation target. A GL 3.3 core context has no fixed-function AA worth
  using, and unlike multisampling this antialiases everything uniformly —
  polygon edges, glyph edges, and the interior of scaled-down images — because
  the whole scene really is rendered at a higher resolution. The cost is
  SuperSample^2 fill rate.

  The resolve is done by halving repeatedly rather than in one step, because
  bilinear filtering averages only a 2x2 neighbourhood: a single pass from 4x
  straight to 1x would read 4 of the 16 texels covered and alias. Each pass
  halves, so every source texel contributes exactly once.

  BLENDING assumes premultiplied alpha throughout (source-over is
  ONE, ONE_MINUS_SRC_ALPHA), which is what wayland_surface defines and what
  wl_shm and dma-buf ARGB8888 require.

  A canvas is itself an ITextureSurface, delegating to its presentation
  target's texture, so one canvas can be blitted into another with no readback. }
unit wayland_gl_canvas;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, ctypes,
  gl_fpc, gl_core_fpc,
  wayland_surface, wayland_accel_canvas,
  wayland_gl_context, wayland_gl_texture, wayland_gl_target;

type
  EGLCanvas = class(Exception);

  { TWaylandGLCanvas }

  TWaylandGLCanvas = class(TWaylandAccelCanvas, ITextureSurface)
  private
    type
      // 20 bytes: 2 floats position, 2 floats UV, 4 normalised bytes colour.
      TGLVertex = packed record
        X, Y: GLfloat;
        U, V: GLfloat;
        Color: DWord;
      end;

      TTextureCacheEntry = record
        SourceKey: Pointer;   // the ISurface implementor, compared never dereferenced
        Generation: QWord;
        Texture: TGLTexture;
      end;
  private
    FContext: TWaylandGLContext;
    FTarget: TGLRenderTarget;
    FSuperSample: Integer;

    // Offscreen supersample buffer and the halving chain down to 1x.
    FSSTarget: TGLRenderTarget;
    FResolveChain: array of TGLRenderTarget;

    // shader
    FProgram: GLuint;
    FUniViewport: GLint;
    FUniTexture: GLint;
    FUniMode: GLint;
    FVao: GLuint;
    FVbo: GLuint;
    FVboCapacity: Integer;

    // batch
    FBatch: array of TGLVertex;
    FBatchCount: Integer;
    FBatchTexture: GLuint;
    FBatchMode: Integer;
    FBatchValid: Boolean;

    FCache: array of TTextureCacheEntry;
    FCacheCount: Integer;

    procedure BuildProgram;
    procedure BuildBuffers;
    procedure BuildResolveChain;
    function  CompileShader(AKind: GLenum; const ASource: String): GLuint;

    // Find or upload a GL texture for ASurface. AAlphaOnly reports whether it
    // holds coverage rather than colour. Returns 0 if it cannot be textured.
    function  ResolveTexture(ASurface: ISurface; out AAlphaOnly: Boolean;
      out AU0, AV0, AU1, AV1: Single): GLuint;
    function  CacheLookup(ASurface: ISurface): TGLTexture;
    procedure CacheStore(ASurface: ISurface; ATexture: TGLTexture);
    procedure ClearCache;

    procedure FlushBatch;
    procedure SetBatchState(ATexture: GLuint; AMode: Integer);
    procedure PushGLVertex(const AVert: TCanvasVertex;
      const AU0, AV0, AU1, AV1: Single);

    // Draw ASource over the whole of ADest with linear filtering.
    procedure BlitFullscreen(ASource: TGLTexture; ADest: TGLRenderTarget);
    procedure SetProjection(AWidth, AHeight: Integer);
    function  RenderTarget: TGLRenderTarget;
  protected
    { TWaylandAccelCanvas device protocol }
    procedure DeviceBeginFrame; override;
    procedure DeviceEndFrame; override;
    procedure DeviceClear(AColor: TCanvasColor); override;
    procedure DeviceSetClip(const ARect: TRect; AEnabled: Boolean); override;
    procedure DeviceSetBlend(AMode: TCanvasBlendMode); override;
    procedure DeviceDrawTriangles(const AVerts: TCanvasVertexArray;
      ACount: Integer; ATexture: ISurface); override;

    { ITextureSurface — the canvas as a blit source }
    function GetTextureHandle: PtrUInt;
    procedure GetTextureUV(out AU0, AV0, AU1, AV1: Single);
  public
    // ASuperSample must be a power of two: 1 disables anti-aliasing, 2 is the
    // sensible default, 4 is noticeably better on thin diagonals and costs
    // sixteen times the fill rate.
    constructor Create(AContext: TWaylandGLContext; AWidth, AHeight: Integer;
      ASuperSample: Integer = 2);
    destructor Destroy; override;

    // Where EndFrame delivers the finished image. Must be set before
    // BeginFrame, and must match the canvas size.
    procedure SetTarget(ATarget: TGLRenderTarget);

    // Discard cached uploads of source surfaces. They are re-uploaded on next
    // use; call it if a lot of one-shot images have gone through the canvas.
    procedure PurgeTextureCache;

    property Context: TWaylandGLContext read FContext;
    property Target: TGLRenderTarget read FTarget;
    property SuperSample: Integer read FSuperSample;
  end;

implementation

const
  VertexShaderSource =
    '#version 330 core'#10 +
    'layout(location = 0) in vec2 aPos;'#10 +
    'layout(location = 1) in vec2 aUV;'#10 +
    'layout(location = 2) in vec4 aColor;'#10 +
    'uniform vec2 uViewport;'#10 +
    'out vec2 vUV;'#10 +
    'out vec4 vColor;'#10 +
    'void main() {'#10 +
    // Canvas space is pixels with the origin top-left and Y down. Y is mapped
    // to NDC WITHOUT a flip, on purpose: NDC -1 is window y 0, which is
    // framebuffer memory row 0. Not flipping therefore makes canvas row 0 land
    // in memory row 0 — which is what a wl_buffer means by its top row, and
    // what a CPU image upload puts in texel row 0. Flipping here instead would
    // store every render target upside down and present mirrored frames.
    '    vec2 ndc = vec2(aPos.x / uViewport.x * 2.0 - 1.0,'#10 +
    '                    aPos.y / uViewport.y * 2.0 - 1.0);'#10 +
    '    gl_Position = vec4(ndc, 0.0, 1.0);'#10 +
    '    vUV = aUV;'#10 +
    // The colour arrives as bytes B,G,R,A (a little-endian 0xAARRGGBB DWord),
    // so swizzle it back into RGBA.
    '    vColor = aColor.bgra;'#10 +
    '}'#10;

  FragmentShaderSource =
    '#version 330 core'#10 +
    'in vec2 vUV;'#10 +
    'in vec4 vColor;'#10 +
    'uniform sampler2D uTexture;'#10 +
    'uniform int uMode;'#10 +
    'out vec4 fragColor;'#10 +
    'void main() {'#10 +
    '    if (uMode == 0) {'#10 +
    '        fragColor = vColor;'#10 +          // flat
    '    } else if (uMode == 1) {'#10 +
    '        fragColor = texture(uTexture, vUV) * vColor;'#10 +   // colour texture
    '    } else {'#10 +
    // Coverage-only page (a glyph atlas): red is alpha. vColor is already
    // premultiplied, so scaling all four channels keeps it so.
    '        fragColor = vColor * texture(uTexture, vUV).r;'#10 +
    '    }'#10 +
    '}'#10;

  ModeFlat        = 0;
  ModeTextureRGBA = 1;
  ModeTextureA    = 2;

  InitialBatchVerts = 4096;

{ TWaylandGLCanvas }

constructor TWaylandGLCanvas.Create(AContext: TWaylandGLContext;
  AWidth, AHeight: Integer; ASuperSample: Integer);
begin
  inherited Create(AWidth, AHeight);
  if AContext = nil then
    raise EGLCanvas.Create('TWaylandGLCanvas: nil context');
  if (ASuperSample < 1) or ((ASuperSample and (ASuperSample - 1)) <> 0) then
    raise EGLCanvas.CreateFmt(
      'TWaylandGLCanvas: SuperSample must be a power of two, got %d', [ASuperSample]);

  FContext := AContext;
  FSuperSample := ASuperSample;
  FContext.MakeCurrent;

  BuildProgram;
  BuildBuffers;
  BuildResolveChain;
end;

destructor TWaylandGLCanvas.Destroy;
var
  i: Integer;
begin
  ClearCache;
  for i := 0 to High(FResolveChain) do
    FResolveChain[i].Free;
  SetLength(FResolveChain, 0);
  FSSTarget.Free;
  if FVbo <> 0 then
    glDeleteBuffers(1, @FVbo);
  if FVao <> 0 then
    glDeleteVertexArrays(1, @FVao);
  if FProgram <> 0 then
    glDeleteProgram(FProgram);
  SetLength(FBatch, 0);
  inherited Destroy;
end;

function TWaylandGLCanvas.CompileShader(AKind: GLenum; const ASource: String): GLuint;
var
  lSrc: PGLchar;
  lStatus, lLen: GLint;
  lLog: AnsiString;
begin
  Result := glCreateShader(AKind);
  lSrc := PGLchar(ASource);
  glShaderSource(Result, 1, @lSrc, nil);
  glCompileShader(Result);
  glGetShaderiv(Result, GL_COMPILE_STATUS, @lStatus);
  if lStatus = 0 then
  begin
    glGetShaderiv(Result, GL_INFO_LOG_LENGTH, @lLen);
    SetLength(lLog, Max(lLen, 1));
    glGetShaderInfoLog(Result, Length(lLog), nil, PGLchar(lLog));
    glDeleteShader(Result);
    raise EGLCanvas.CreateFmt('%s shader failed to compile: %s',
      [BoolToStr(AKind = GL_VERTEX_SHADER, 'vertex', 'fragment'), Trim(lLog)]);
  end;
end;

procedure TWaylandGLCanvas.BuildProgram;
var
  lVert, lFrag: GLuint;
  lStatus, lLen: GLint;
  lLog: AnsiString;
begin
  lVert := CompileShader(GL_VERTEX_SHADER, VertexShaderSource);
  try
    lFrag := CompileShader(GL_FRAGMENT_SHADER, FragmentShaderSource);
  except
    glDeleteShader(lVert);
    raise;
  end;

  // Parentheses required: these are function-pointer variables, not imports.
  FProgram := glCreateProgram();
  glAttachShader(FProgram, lVert);
  glAttachShader(FProgram, lFrag);
  glBindFragDataLocation(FProgram, 0, 'fragColor');
  glLinkProgram(FProgram);
  // The program holds its own references now.
  glDeleteShader(lVert);
  glDeleteShader(lFrag);

  glGetProgramiv(FProgram, GL_LINK_STATUS, @lStatus);
  if lStatus = 0 then
  begin
    glGetProgramiv(FProgram, GL_INFO_LOG_LENGTH, @lLen);
    SetLength(lLog, Max(lLen, 1));
    glGetProgramInfoLog(FProgram, Length(lLog), nil, PGLchar(lLog));
    glDeleteProgram(FProgram);
    FProgram := 0;
    raise EGLCanvas.CreateFmt('canvas shader program failed to link: %s', [Trim(lLog)]);
  end;

  FUniViewport := glGetUniformLocation(FProgram, 'uViewport');
  FUniTexture := glGetUniformLocation(FProgram, 'uTexture');
  FUniMode := glGetUniformLocation(FProgram, 'uMode');
end;

procedure TWaylandGLCanvas.BuildBuffers;
begin
  glGenVertexArrays(1, @FVao);
  glBindVertexArray(FVao);
  glGenBuffers(1, @FVbo);
  glBindBuffer(GL_ARRAY_BUFFER, FVbo);

  FVboCapacity := InitialBatchVerts;
  glBufferData(GL_ARRAY_BUFFER, FVboCapacity * SizeOf(TGLVertex), nil, GL_STREAM_DRAW);

  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, SizeOf(TGLVertex), Pointer(0));
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, SizeOf(TGLVertex), Pointer(8));
  glEnableVertexAttribArray(2);
  glVertexAttribPointer(2, 4, GL_UNSIGNED_BYTE, GL_TRUE, SizeOf(TGLVertex), Pointer(16));

  glBindVertexArray(0);
  SetLength(FBatch, InitialBatchVerts);
end;

procedure TWaylandGLCanvas.BuildResolveChain;
var
  lSize, lStages, i, lW, lH: Integer;
begin
  if FSuperSample = 1 then
    Exit;

  FSSTarget := TGLRenderTarget.Create(FContext,
    Width * FSuperSample, Height * FSuperSample, False);

  // One halving pass per power of two. The LAST halving writes straight into
  // the presentation target, so the chain holds the intermediates only:
  // log2(SuperSample) - 1 of them.
  lStages := 0;
  lSize := FSuperSample;
  while lSize > 1 do
  begin
    Inc(lStages);
    lSize := lSize div 2;
  end;
  SetLength(FResolveChain, lStages - 1);

  lSize := FSuperSample;
  for i := 0 to High(FResolveChain) do
  begin
    lSize := lSize div 2;
    lW := Width * lSize;
    lH := Height * lSize;
    FResolveChain[i] := TGLRenderTarget.Create(FContext, lW, lH, False);
  end;
end;

procedure TWaylandGLCanvas.SetTarget(ATarget: TGLRenderTarget);
begin
  if InFrame then
    raise EGLCanvas.Create('SetTarget called during a frame');
  if ATarget = nil then
    raise EGLCanvas.Create('TWaylandGLCanvas: nil target');
  if (ATarget.Width <> Width) or (ATarget.Height <> Height) then
    raise EGLCanvas.CreateFmt(
      'target is %dx%d but the canvas is %dx%d',
      [ATarget.Width, ATarget.Height, Width, Height]);
  FTarget := ATarget;
end;

function TWaylandGLCanvas.RenderTarget: TGLRenderTarget;
begin
  // Everything is drawn into the supersample buffer when there is one.
  if FSuperSample > 1 then
    Result := FSSTarget
  else
    Result := FTarget;
end;

procedure TWaylandGLCanvas.SetProjection(AWidth, AHeight: Integer);
begin
  glUniform2f(FUniViewport, AWidth, AHeight);
end;

{ --- texture cache --- }

function TWaylandGLCanvas.CacheLookup(ASurface: ISurface): TGLTexture;
var
  i: Integer;
  lKey: Pointer;
  lGen: QWord;
begin
  lKey := Pointer(ASurface);
  lGen := ASurface.Generation;
  for i := 0 to FCacheCount - 1 do
    if (FCache[i].SourceKey = lKey) and (FCache[i].Generation = lGen) then
      Exit(FCache[i].Texture);
  Result := nil;
end;

procedure TWaylandGLCanvas.CacheStore(ASurface: ISurface; ATexture: TGLTexture);
var
  i: Integer;
  lKey: Pointer;
begin
  lKey := Pointer(ASurface);
  // Replace a stale entry for the same source rather than accumulating one per
  // generation — an animated image would otherwise leak a texture per frame.
  for i := 0 to FCacheCount - 1 do
    if FCache[i].SourceKey = lKey then
    begin
      if FCache[i].Texture <> ATexture then
      begin
        // The pending batch may still be referencing the texture we are about
        // to delete, and FlushBatch would then bind a dead name. This is not
        // hypothetical: a second run of text rasterises new glyphs, which bumps
        // the atlas page's generation and lands here while the first run is
        // still batched.
        if FCache[i].Texture.Handle = FBatchTexture then
        begin
          FlushBatch;
          FBatchValid := False;
        end;
        FCache[i].Texture.Free;
      end;
      FCache[i].Texture := ATexture;
      FCache[i].Generation := ASurface.Generation;
      Exit;
    end;
  if FCacheCount = Length(FCache) then
    SetLength(FCache, Length(FCache) * 2 + 16);
  FCache[FCacheCount].SourceKey := lKey;
  FCache[FCacheCount].Generation := ASurface.Generation;
  FCache[FCacheCount].Texture := ATexture;
  Inc(FCacheCount);
end;

procedure TWaylandGLCanvas.ClearCache;
var
  i: Integer;
begin
  for i := 0 to FCacheCount - 1 do
    FCache[i].Texture.Free;
  FCacheCount := 0;
  SetLength(FCache, 0);
end;

procedure TWaylandGLCanvas.PurgeTextureCache;
begin
  FlushBatch;
  ClearCache;
end;

function TWaylandGLCanvas.ResolveTexture(ASurface: ISurface; out AAlphaOnly: Boolean;
  out AU0, AV0, AU1, AV1: Single): GLuint;
var
  lNative: ITextureSurface;
  lTex: TGLTexture;
begin
  AU0 := 0; AV0 := 0; AU1 := 1; AV1 := 1;
  Result := 0;
  AAlphaOnly := False;
  if ASurface = nil then
    Exit;
  // Decided once, for BOTH paths below. Deriving it per-path is how coverage
  // pages previously ended up drawn in colour mode, sampling GL_RED as
  // (r, 0, 0, 1) and rendering all text red.
  AAlphaOnly := ASurface.Format = sfA8;

  // Already on the GPU: use it directly, no upload, no cache entry.
  if Supports(ASurface, ITextureSurface, lNative) then
  begin
    lNative.GetTextureUV(AU0, AV0, AU1, AV1);
    Exit(GLuint(lNative.GetTextureHandle));
  end;

  lTex := CacheLookup(ASurface);
  if lTex = nil then
  begin
    // A coverage surface (a glyph atlas page from the text module) becomes an
    // R8 texture; anything else is colour. This is what lets one backend-
    // agnostic FreeType atlas feed the GPU path with no atlas-specific code.
    if ASurface.Format = sfA8 then
      lTex := TGLTexture.Create(ASurface.Width, ASurface.Height, tfR8, tflLinear)
    else
      lTex := TGLTexture.Create(ASurface.Width, ASurface.Height, tfRGBA8, tflLinear);
    if not lTex.UploadFromSurface(ASurface) then
    begin
      // Not CPU-readable and not a texture: nothing can be drawn from it.
      lTex.Free;
      Exit(0);
    end;
    CacheStore(ASurface, lTex);
  end;
  lTex.GetTextureUV(AU0, AV0, AU1, AV1);
  Result := lTex.Handle;
end;

{ --- batching --- }

procedure TWaylandGLCanvas.SetBatchState(ATexture: GLuint; AMode: Integer);
begin
  if FBatchValid and (FBatchTexture = ATexture) and (FBatchMode = AMode) then
    Exit;
  FlushBatch;
  FBatchTexture := ATexture;
  FBatchMode := AMode;
  FBatchValid := True;
end;

procedure TWaylandGLCanvas.PushGLVertex(const AVert: TCanvasVertex;
  const AU0, AV0, AU1, AV1: Single);
begin
  if FBatchCount = Length(FBatch) then
    SetLength(FBatch, Length(FBatch) * 2);
  with FBatch[FBatchCount] do
  begin
    X := AVert.X;
    Y := AVert.Y;
    // The base class emits UVs normalised over the SOURCE SURFACE; map them
    // into the region the surface actually occupies in its backing texture.
    U := AU0 + AVert.U * (AU1 - AU0);
    V := AV0 + AVert.V * (AV1 - AV0);
    Color := DWord(AVert.Color);
  end;
  Inc(FBatchCount);
end;

procedure TWaylandGLCanvas.FlushBatch;
begin
  if (FBatchCount = 0) or (FProgram = 0) then
  begin
    FBatchCount := 0;
    Exit;
  end;

  glBindVertexArray(FVao);
  glBindBuffer(GL_ARRAY_BUFFER, FVbo);
  if FBatchCount > FVboCapacity then
  begin
    // Grow and reallocate; orphaning with a nil upload first lets the driver
    // hand back fresh storage instead of stalling on the in-flight buffer.
    FVboCapacity := FBatchCount * 2;
    glBufferData(GL_ARRAY_BUFFER, FVboCapacity * SizeOf(TGLVertex), nil, GL_STREAM_DRAW);
  end
  else
    glBufferData(GL_ARRAY_BUFFER, FVboCapacity * SizeOf(TGLVertex), nil, GL_STREAM_DRAW);
  glBufferSubData(GL_ARRAY_BUFFER, 0, FBatchCount * SizeOf(TGLVertex), @FBatch[0]);

  glUseProgram(FProgram);
  glUniform1i(FUniMode, FBatchMode);
  if FBatchMode <> ModeFlat then
  begin
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, FBatchTexture);
    glUniform1i(FUniTexture, 0);
  end;

  glDrawArrays(GL_TRIANGLES, 0, FBatchCount);
  glBindVertexArray(0);
  FBatchCount := 0;
end;

{ --- device protocol --- }

procedure TWaylandGLCanvas.DeviceBeginFrame;
var
  lRT: TGLRenderTarget;
begin
  if FTarget = nil then
    raise EGLCanvas.Create('BeginFrame without a target; call SetTarget first');
  FContext.MakeCurrent;

  lRT := RenderTarget;
  lRT.Bind;

  glUseProgram(FProgram);
  // Draw in canvas coordinates regardless of the supersample factor: the
  // viewport is SS times larger, the projection is not.
  SetProjection(Width, Height);

  glDisable(GL_SCISSOR_TEST);
  glEnable(GL_BLEND);
  glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

  FBatchCount := 0;
  FBatchValid := False;
end;

procedure TWaylandGLCanvas.DeviceEndFrame;
var
  i: Integer;
  lSrc: TGLRenderTarget;
begin
  FlushBatch;

  if FSuperSample > 1 then
  begin
    // Scissor must not survive into the resolve, or it would crop the blit.
    glDisable(GL_SCISSOR_TEST);
    // Straight source copy: the supersample buffer is already composited.
    glBlendFuncSeparate(GL_ONE, GL_ZERO, GL_ONE, GL_ZERO);
    lSrc := FSSTarget;
    for i := 0 to High(FResolveChain) do
    begin
      BlitFullscreen(lSrc.Texture, FResolveChain[i]);
      lSrc := FResolveChain[i];
    end;
    BlitFullscreen(lSrc.Texture, FTarget);
  end;

  // The compositor is about to read this memory directly out of the dmabuf, so
  // the GPU must genuinely be done — not merely have the commands queued.
  glFinish;
  FBatchValid := False;
end;

procedure TWaylandGLCanvas.BlitFullscreen(ASource: TGLTexture; ADest: TGLRenderTarget);
var
  lVerts: array[0..5] of TCanvasVertex;
  lU0, lV0, lU1, lV1: Single;
  i: Integer;

  procedure Corner(AIndex: Integer; AX, AY, AU, AV: Single);
  begin
    lVerts[AIndex].X := AX;
    lVerts[AIndex].Y := AY;
    lVerts[AIndex].U := AU;
    lVerts[AIndex].V := AV;
    lVerts[AIndex].Color := clWhiteOpaque;
  end;

begin
  // Anything still batched belongs to the PREVIOUS target and projection; it
  // must be issued before we rebind, not after.
  FlushBatch;
  FBatchValid := False;

  ADest.Bind;
  glUseProgram(FProgram);
  // Project in destination pixels; the quad below spans exactly that, so each
  // destination texel samples the source at the centre of the block it covers.
  SetProjection(ADest.Width, ADest.Height);

  // Surface-normalised UVs (0..1 over the quad); PushGLVertex maps them through
  // the source's own UV extent, which for a render target inverts V.
  Corner(0, 0, 0, 0, 0);
  Corner(1, ADest.Width, 0, 1, 0);
  Corner(2, ADest.Width, ADest.Height, 1, 1);
  Corner(3, 0, 0, 0, 0);
  Corner(4, ADest.Width, ADest.Height, 1, 1);
  Corner(5, 0, ADest.Height, 0, 1);

  ASource.GetTextureUV(lU0, lV0, lU1, lV1);
  SetBatchState(ASource.Handle, ModeTextureRGBA);
  for i := 0 to 5 do
    PushGLVertex(lVerts[i], lU0, lV0, lU1, lV1);
  FlushBatch;
end;

procedure TWaylandGLCanvas.DeviceClear(AColor: TCanvasColor);
var
  lWasScissor: Boolean;
begin
  FlushBatch;
  // Clear covers the whole target by definition, so the scissor must be off.
  lWasScissor := glIsEnabled(GL_SCISSOR_TEST) <> 0;
  if lWasScissor then
    glDisable(GL_SCISSOR_TEST);
  glClearColor(
    RedOf(AColor) / 255.0,
    GreenOf(AColor) / 255.0,
    BlueOf(AColor) / 255.0,
    AlphaOf(AColor) / 255.0);
  glClear(GL_COLOR_BUFFER_BIT);
  if lWasScissor then
    glEnable(GL_SCISSOR_TEST);
end;

procedure TWaylandGLCanvas.DeviceSetClip(const ARect: TRect; AEnabled: Boolean);
var
  lX, lY, lW, lH: Integer;
begin
  FlushBatch;
  if not AEnabled then
  begin
    glDisable(GL_SCISSOR_TEST);
    Exit;
  end;
  lW := ARect.Right - ARect.Left;
  lH := ARect.Bottom - ARect.Top;
  if (lW <= 0) or (lH <= 0) then
  begin
    // An empty clip: scissor nothing at all rather than everything.
    glEnable(GL_SCISSOR_TEST);
    glScissor(0, 0, 0, 0);
    Exit;
  end;
  // Scissor is in framebuffer pixels. Because the projection does not flip Y,
  // canvas Y and window Y run the same way, so this is a plain scale by the
  // supersample factor with no inversion.
  lX := ARect.Left * FSuperSample;
  lY := ARect.Top * FSuperSample;
  glEnable(GL_SCISSOR_TEST);
  glScissor(lX, lY, lW * FSuperSample, lH * FSuperSample);
end;

procedure TWaylandGLCanvas.DeviceSetBlend(AMode: TCanvasBlendMode);
begin
  FlushBatch;
  glEnable(GL_BLEND);
  case AMode of
    cbmSource:
      glBlendFuncSeparate(GL_ONE, GL_ZERO, GL_ONE, GL_ZERO);
    cbmAdd:
      glBlendFuncSeparate(GL_ONE, GL_ONE, GL_ONE, GL_ONE);
    cbmMultiply:
      glBlendFuncSeparate(GL_DST_COLOR, GL_ZERO, GL_DST_ALPHA, GL_ZERO);
    else
      // cbmSourceOver, on premultiplied colours.
      glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  end;
end;

procedure TWaylandGLCanvas.DeviceDrawTriangles(const AVerts: TCanvasVertexArray;
  ACount: Integer; ATexture: ISurface);
var
  i, lMode: Integer;
  lHandle: GLuint;
  lAlphaOnly: Boolean;
  lU0, lV0, lU1, lV1: Single;
begin
  if ACount <= 0 then
    Exit;

  if ATexture = nil then
  begin
    lHandle := 0;
    lMode := ModeFlat;
    lU0 := 0; lV0 := 0; lU1 := 1; lV1 := 1;
  end
  else
  begin
    lHandle := ResolveTexture(ATexture, lAlphaOnly, lU0, lV0, lU1, lV1);
    if lHandle = 0 then
      Exit;  // nothing usable to sample from
    if lAlphaOnly then
      lMode := ModeTextureA
    else
      lMode := ModeTextureRGBA;
  end;

  SetBatchState(lHandle, lMode);
  for i := 0 to ACount - 1 do
    PushGLVertex(AVerts[i], lU0, lV0, lU1, lV1);
end;

{ --- ITextureSurface --- }

function TWaylandGLCanvas.GetTextureHandle: PtrUInt;
begin
  if FTarget <> nil then
    Result := FTarget.Texture.Handle
  else
    Result := 0;
end;

procedure TWaylandGLCanvas.GetTextureUV(out AU0, AV0, AU1, AV1: Single);
begin
  if FTarget <> nil then
    FTarget.Texture.GetTextureUV(AU0, AV0, AU1, AV1)
  else
  begin
    AU0 := 0; AV0 := 0; AU1 := 1; AV1 := 1;
  end;
end;

end.
