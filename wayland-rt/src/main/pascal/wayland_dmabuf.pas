{ wayland_dmabuf — a minimal CPU-mapped dma-buf via udmabuf.

  Wraps the udmabuf machinery used to obtain a dma-buf whose pages are also
  CPU-addressable, with no GPU and no external library: a sealed memfd is
  exposed as a dma-buf through /dev/udmabuf, and the memfd's mmap'd memory IS
  the pixel buffer. Present the resulting fd with zwp_linux_dmabuf_v1 using the
  LINEAR modifier; draw into Data (e.g. with TWaylandCanvas).

  This unit is protocol-agnostic (it only knows syscalls), so both the runtime
  classes layer and standalone examples can share it.

  Requirements: the udmabuf kernel module and access to /dev/udmabuf (typically
  the 'kvm' group). Call Available first to decide whether to use this path.

  Import gotchas (a compositor's EGL/GPU import rejects otherwise):
    - the memfd size must be page-aligned (Alloc rounds up to 4096);
    - the LINEAR stride should be 256-byte aligned (the caller picks the stride
      and sizes the buffer accordingly — see RoundStride);
    - bracket CPU writes with BeginCpuAccess/EndCpuAccess for cache coherency. }
unit wayland_dmabuf;

{$mode objfpc}{$H+}
{$PackRecords c}

interface

uses
  BaseUnix, ctypes;

const
  // DRM fourcc pixel formats matching wl_shm ARGB8888 / XRGB8888.
  DRM_FORMAT_ARGB8888   = $34325241; // 'AR24'
  DRM_FORMAT_XRGB8888   = $34325258; // 'XR24'
  DRM_FORMAT_MOD_LINEAR = 0;

type
  { TWaylandUdmabuf — one CPU-mapped dma-buf. Owns the memfd, the dma-buf fd and
    the mmap; freeing the object releases all three (the dma-buf fd should be
    handed to the compositor before then; the compositor dups it). }
  TWaylandUdmabuf = class
  private
    FMemFd: cint;
    FDmabufFd: cint;
    FData: Pointer;
    FSize: csize_t;
  public
    constructor Create;
    destructor Destroy; override;

    // Allocate (rounding ASize up to a page) a CPU-mapped dma-buf. Replaces any
    // previous allocation. Returns False (and leaves the object empty) on error.
    function Alloc(ASize: csize_t): Boolean;
    // Release the mapping and fds (idempotent).
    procedure Release;

    // Cache-coherency bracketing for CPU writes into Data.
    procedure BeginCpuAccess;
    procedure EndCpuAccess;

    // Round a tightly-packed row width up to the alignment GPU import wants.
    class function RoundStride(AWidthBytes: Integer): Integer;
    // True when /dev/udmabuf can be opened (module present and permitted).
    class function Available: Boolean;

    property DmabufFd: cint read FDmabufFd;
    property Data: Pointer read FData;
    property Size: csize_t read FSize;
  end;

implementation

const
  MFD_CLOEXEC       = $0001;
  MFD_ALLOW_SEALING = $0002;
  F_ADD_SEALS       = 1033;
  F_SEAL_SHRINK     = $0002;

  // _IOC(dir,type,nr,size): dir<<30 | size<<16 | type<<8 | nr
  UDMABUF_CREATE     = (1 shl 30) or (24 shl 16) or (Ord('u') shl 8) or $42; // _IOW('u',0x42, udmabuf_create)
  DMA_BUF_IOCTL_SYNC = (1 shl 30) or (8  shl 16) or (Ord('b') shl 8) or 0;   // _IOW('b',0, __u64)
  DMA_BUF_SYNC_RW    = 3;
  DMA_BUF_SYNC_START = 0;
  DMA_BUF_SYNC_END   = 4;

  PAGE = 4096;

type
  Tudmabuf_create = record
    memfd: cuint32;
    flags: cuint32;
    offset: cuint64;
    size: cuint64;
  end;
  Tdma_buf_sync = record
    flags: cuint64;
  end;

function memfd_create(name: PChar; flags: cuint): cint; cdecl; external 'c' name 'memfd_create';

constructor TWaylandUdmabuf.Create;
begin
  FMemFd := -1;
  FDmabufFd := -1;
  FData := nil;
  FSize := 0;
end;

destructor TWaylandUdmabuf.Destroy;
begin
  Release;
  inherited Destroy;
end;

procedure TWaylandUdmabuf.Release;
begin
  if (FData <> nil) and (FData <> MAP_FAILED) then
    Fpmunmap(FData, FSize);
  FData := nil;
  if FDmabufFd >= 0 then
    FpClose(FDmabufFd);
  FDmabufFd := -1;
  if FMemFd >= 0 then
    FpClose(FMemFd);
  FMemFd := -1;
  FSize := 0;
end;

class function TWaylandUdmabuf.RoundStride(AWidthBytes: Integer): Integer;
begin
  Result := ((AWidthBytes + 255) div 256) * 256;
end;

class function TWaylandUdmabuf.Available: Boolean;
var
  fd: cint;
begin
  fd := FpOpen('/dev/udmabuf', O_RDWR);
  Result := fd >= 0;
  if Result then
    FpClose(fd);
end;

function TWaylandUdmabuf.Alloc(ASize: csize_t): Boolean;
var
  lCreate: Tudmabuf_create;
  lUdmabuf: cint;
  p: Pointer;
begin
  Release;
  Result := False;
  // udmabuf requires a page-aligned memfd size.
  FSize := ((ASize + PAGE - 1) div PAGE) * PAGE;

  FMemFd := memfd_create('wayl-dmabuf', MFD_CLOEXEC or MFD_ALLOW_SEALING);
  if FMemFd < 0 then Exit;
  if fpftruncate(FMemFd, FSize) <> 0 then Exit;
  // udmabuf requires the memfd be sealed against shrinking.
  if FpFcntl(FMemFd, F_ADD_SEALS, F_SEAL_SHRINK) <> 0 then Exit;

  lUdmabuf := FpOpen('/dev/udmabuf', O_RDWR);
  if lUdmabuf < 0 then Exit;
  FillChar(lCreate, SizeOf(lCreate), 0);
  lCreate.memfd := FMemFd;
  lCreate.size := FSize;
  FDmabufFd := FpIOCtl(lUdmabuf, UDMABUF_CREATE, @lCreate);
  FpClose(lUdmabuf);
  if FDmabufFd < 0 then Exit;

  // CPU access via the memfd mapping (the same pages as the dma-buf).
  p := Fpmmap(nil, FSize, PROT_READ or PROT_WRITE, MAP_SHARED, FMemFd, 0);
  if p = MAP_FAILED then
  begin
    FData := nil;
    Exit;
  end;
  FData := p;
  Result := True;
end;

procedure TWaylandUdmabuf.BeginCpuAccess;
var
  lSync: Tdma_buf_sync;
begin
  if FDmabufFd < 0 then Exit;
  lSync.flags := DMA_BUF_SYNC_START or DMA_BUF_SYNC_RW;
  FpIOCtl(FDmabufFd, DMA_BUF_IOCTL_SYNC, @lSync);
end;

procedure TWaylandUdmabuf.EndCpuAccess;
var
  lSync: Tdma_buf_sync;
begin
  if FDmabufFd < 0 then Exit;
  lSync.flags := DMA_BUF_SYNC_END or DMA_BUF_SYNC_RW;
  FpIOCtl(FDmabufFd, DMA_BUF_IOCTL_SYNC, @lSync);
end;

end.
