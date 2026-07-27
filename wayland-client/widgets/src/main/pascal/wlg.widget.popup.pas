// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.widget.popup — transient content that escapes the window.

  A popup is the one thing the one-surface widget design cannot express. Every
  widget lives in the window's single wl_surface and is clipped by it, which is
  exactly wrong for a menu, a combo list or a tooltip: those have to be able to
  sit wherever they fit, including outside the window.

  TWO BACKENDS, CHOSEN PER POPUP, AT THE MOMENT IT OPENS.

  OVERLAY. The content is parented into the window's overlay layer, painted
  after everything else and hit-tested before it. No compositor objects, no
  configure round trip, no protocol: it is an ordinary widget in a layer that
  paints late, so it costs nothing beyond the pixels. It cannot leave the
  window.

  SURFACE. A real xdg_popup: its own wl_surface, its own buffers, positioned by
  the compositor relative to an anchor rectangle. It can go anywhere on screen,
  the compositor keeps it on the output, and with a grab it dismisses itself on
  an outside click. It costs a surface, a buffer pair and a round trip.

  THE RULE: use the overlay when the popup fits inside the window, a surface
  when it does not. That is not a compromise between the two — it is the
  correct answer in each case. A dropdown in the middle of a large window has
  no business allocating a surface; the same dropdown forty pixels from the
  bottom edge would be cut in half by the overlay, and a clipped menu is a
  broken menu. Since the answer depends on where the window happens to be and
  how big the content turned out, it can only be decided at open time.

  Backend can be forced with the Backend property when an application knows
  better — a menu that must be a surface for grab semantics, say. }
unit wlg.widget.popup;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Types, Math,
  wlg.surface, wlg.canvas.base,
  wlg.widget.types, wlg.widget.core, wlg.widget.input, wlg.widget.theme,
  wlg.widget.controls, wlg.widget.window;

type
  { Which backend to use. pbAuto is the fit rule and the sensible default. }
  TwgPopupBackend = (pbAuto, pbOverlay, pbSurface);

  { Where to put the popup relative to its anchor rectangle. A preference, not
    a promise: the overlay path nudges to stay inside the window, and the
    surface path lets the compositor flip or slide it. }
  TwgPopupSide = (psBelow, psAbove, psRight, psLeft);

  TwgPopup = class;

  { The full-window catcher that sits UNDER an overlay popup and above
    everything else, so a press anywhere outside the popup dismisses it. This
    is what a compositor grab does for a surface popup; the overlay has to do
    it itself. }
  TwgPopupCatcher = class(TwgControl)
  private
    FPopup: TwgPopup;
  public
    procedure PointerDown(var AEvent: TwgPointerEvent); override;
    function  CanFocus: Boolean; override;
  end;

  { TwgPopup }

  TwgPopup = class(TwgControl)
  private
    FContent: TwgWidget;
    FHostWindow: TwgWindow;
    FSurface: TwgWindow;          // non-nil when shown as an xdg_popup
    FCatcher: TwgPopupCatcher;    // non-nil when shown as an overlay
    FOpen: Boolean;
    FBackend: TwgPopupBackend;
    FUsedSurface: Boolean;        // which backend actually got used
    FSide: TwgPopupSide;
    FGrab: Boolean;
    FOnClose: TNotifyEvent;
    FRequestedRect: TRect;
    procedure ShowAsOverlay(const ARect: TRect);
    procedure ShowAsSurface(const ARect: TRect);
    procedure SurfaceCloseQuery(Sender: TObject; var ACanClose: Boolean);
    // Where the popup wants to be, in the host window's coordinates.
    function  PlaceAt(const AAnchorRoot: TRect; const ASize: TSize): TRect;
  protected
    procedure Paint(ACanvas: TwgCanvas); override;
    procedure BoundsChanged; override;
    function  MeasureSize(AAvailW, AAvailH: Integer): TSize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Open, anchored to AAnchor's rectangle (in AAnchor's own coordinates).
      Pass an empty rect to anchor to the whole widget. }
    procedure ShowFor(AAnchor: TwgWidget; const AAnchorRect: TRect);
    procedure Close;

    procedure KeyDown(var AEvent: TwgKeyEvent); override;
    function  CanFocus: Boolean; override;

    // The popup's single child. Setting it re-parents.
    procedure SetContent(AWidget: TwgWidget);
    property Content: TwgWidget read FContent;
    property IsOpen: Boolean read FOpen;
    // The popup's own window when the surface backend was used, else nil.
    property SurfaceWindow: TwgWindow read FSurface;
    // Where ShowFor asked for it to go, in host-window coordinates.
    property RequestedRect: TRect read FRequestedRect;
    // True when the last ShowFor used an xdg_popup rather than the overlay.
    property UsedSurface: Boolean read FUsedSurface;
    property Backend: TwgPopupBackend read FBackend write FBackend;
    property Side: TwgPopupSide read FSide write FSide;
    { Ask the compositor for an input grab (surface backend only). Menus want
      one; a tooltip must NOT have one, or it takes the pointer away from the
      widget it is describing. }
    property Grab: Boolean read FGrab write FGrab;
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
  end;

  { TwgTooltip — a hint.

    Same two backends and the same fit rule, which matters more here than for
    menus: a tooltip is anchored to a widget that is often at the very edge of
    the window, so the overlay would clip it exactly when it is most needed.

    Never grabs. A tooltip that took the pointer grab would prevent the user
    from clicking the thing it is describing. }
  TwgTooltip = class(TwgPopup)
  private
    FLabel: TwgLabel;
    procedure SetText(const AValue: String);
    function  GetText: String;
  public
    constructor Create(AOwner: TComponent); override;
    property Text: String read GetText write SetText;
  end;

implementation

{ TwgPopupCatcher }

function TwgPopupCatcher.CanFocus: Boolean;
begin
  Result := False;
end;

procedure TwgPopupCatcher.PointerDown(var AEvent: TwgPointerEvent);
begin
  // Anything that reaches the catcher is by definition outside the popup: the
  // popup is its sibling and is hit-tested first.
  AEvent.Handled := True;
  if FPopup <> nil then
    FPopup.Close;
end;

{ TwgPopup }

constructor TwgPopup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBackend := pbAuto;
  FSide := psBelow;
  Visible := False;
  ClipChildren := True;
end;

destructor TwgPopup.Destroy;
begin
  if FOpen then
    Close;
  inherited Destroy;
end;

function TwgPopup.CanFocus: Boolean;
begin
  Result := False;
end;

procedure TwgPopup.SetContent(AWidget: TwgWidget);
begin
  FContent := AWidget;
  if FContent <> nil then
    FContent.Parent := Self;
  InvalidateLayout;
end;

function TwgPopup.MeasureSize(AAvailW, AAvailH: Integer): TSize;
var
  lTheme: TwgTheme;
  lPad: Integer;
begin
  lTheme := Theme;
  if lTheme <> nil then
    lPad := lTheme.Metrics.Padding
  else
    lPad := 6;
  if FContent <> nil then
  begin
    Result := FContent.PreferredSize(AAvailW - lPad * 2, AAvailH - lPad * 2);
    Inc(Result.cx, lPad * 2);
    Inc(Result.cy, lPad * 2);
  end
  else
  begin
    Result.cx := 80;
    Result.cy := 24;
  end;
end;

procedure TwgPopup.BoundsChanged;
var
  lTheme: TwgTheme;
  lPad: Integer;
begin
  inherited BoundsChanged;
  if FContent = nil then
    Exit;
  lTheme := Theme;
  if lTheme <> nil then
    lPad := lTheme.Metrics.Padding
  else
    lPad := 6;
  FContent.SetBounds(lPad, lPad, Width - lPad * 2, Height - lPad * 2);
end;

function TwgPopup.PlaceAt(const AAnchorRoot: TRect; const ASize: TSize): TRect;
begin
  case FSide of
    psAbove: Result := Rect(AAnchorRoot.Left, AAnchorRoot.Top - ASize.cy,
                            AAnchorRoot.Left + ASize.cx, AAnchorRoot.Top);
    psRight: Result := Rect(AAnchorRoot.Right, AAnchorRoot.Top,
                            AAnchorRoot.Right + ASize.cx,
                            AAnchorRoot.Top + ASize.cy);
    psLeft:  Result := Rect(AAnchorRoot.Left - ASize.cx, AAnchorRoot.Top,
                            AAnchorRoot.Left, AAnchorRoot.Top + ASize.cy);
    else     Result := Rect(AAnchorRoot.Left, AAnchorRoot.Bottom,
                            AAnchorRoot.Left + ASize.cx,
                            AAnchorRoot.Bottom + ASize.cy);
  end;
end;

procedure TwgPopup.ShowFor(AAnchor: TwgWidget; const AAnchorRect: TRect);
var
  lAnchor, lRect: TRect;
  lSize: TSize;
  lHost: IwgWidgetHost;
  lWindowHost: IwgWindowHost;
  p: TPoint;
  lFits: Boolean;
begin
  if FOpen then
    Close;
  if AAnchor = nil then
    Exit;

  { The host window is found through the anchor rather than being passed in:
    a popup belongs to whatever window its anchor is in, and asking the caller
    to know that is asking them to get it wrong. }
  FHostWindow := nil;
  lHost := AAnchor.Host;
  if (lHost <> nil) and Supports(lHost, IwgWindowHost, lWindowHost) then
    FHostWindow := TwgWindow(lWindowHost.HostWindow);
  if FHostWindow = nil then
    Exit;   // headless, or not attached to a window: nothing to pop up over

  // Inherit the theme from the anchor, since a popup is not in the tree yet
  // and cannot walk up to find one.
  if (Theme = nil) and (AAnchor is TwgControl) then
    SetTheme(TwgControl(AAnchor).Theme);

  lAnchor := AAnchorRect;
  if wgRectEmpty(lAnchor) then
    lAnchor := Rect(0, 0, AAnchor.Width, AAnchor.Height);
  p := AAnchor.LocalToRoot(lAnchor.Left, lAnchor.Top);
  lAnchor := Rect(p.X, p.Y, p.X + (lAnchor.Right - lAnchor.Left),
                  p.Y + (lAnchor.Bottom - lAnchor.Top));

  { Attach to the overlay BEFORE measuring, even if this turns out to be a
    surface popup. Measurement needs a font, a font is resolved through the
    host, and the host is resolved through the parent chain — so a popup
    measured while detached has no font, every caption comes out zero wide and
    the popup collapses to a few pixels. Parenting first costs nothing and the
    surface path re-parents a moment later. }
  Visible := False;
  Parent := FHostWindow.OverlayLayer;
  lSize := PreferredSize(FHostWindow.ClientWidth, FHostWindow.ClientHeight);
  lRect := PlaceAt(lAnchor, lSize);

  { THE RULE. Does the popup fit inside the window as placed? If it does the
    overlay is free and correct. If it does not, the overlay would clip it, so
    it has to be a real surface — which is also the only backend that can ask
    the compositor to keep it on screen. }
  lFits := (lRect.Left >= 0) and (lRect.Top >= 0) and
           (lRect.Right <= FHostWindow.ClientWidth) and
           (lRect.Bottom <= FHostWindow.ClientHeight);

  case FBackend of
    pbOverlay: FUsedSurface := False;
    pbSurface: FUsedSurface := True;
    else       FUsedSurface := not lFits;
  end;

  FOpen := True;
  FRequestedRect := lRect;
  if FUsedSurface then
    ShowAsSurface(lRect)
  else
    ShowAsOverlay(lRect);
end;

procedure TwgPopup.ShowAsOverlay(const ARect: TRect);
var
  lRect: TRect;
begin
  { Nudge back inside. The fit test already said it fits as placed, unless the
    application forced pbOverlay — in which case clamping is better than
    drawing half a menu. }
  lRect := ARect;
  if lRect.Right > FHostWindow.ClientWidth then
    OffsetRect(lRect, FHostWindow.ClientWidth - lRect.Right, 0);
  if lRect.Bottom > FHostWindow.ClientHeight then
    OffsetRect(lRect, 0, FHostWindow.ClientHeight - lRect.Bottom);
  if lRect.Left < 0 then
    OffsetRect(lRect, -lRect.Left, 0);
  if lRect.Top < 0 then
    OffsetRect(lRect, 0, -lRect.Top);

  { The catcher must be the EARLIER sibling so the popup is hit-tested before
    it and painted after it. ShowFor already parented us for measurement, so
    re-parent to move to the end of the child list. }
  FCatcher := TwgPopupCatcher.Create(FHostWindow);
  FCatcher.FPopup := Self;
  FCatcher.Parent := FHostWindow.OverlayLayer;
  FCatcher.SetBounds(0, 0, FHostWindow.ClientWidth, FHostWindow.ClientHeight);

  Parent := nil;
  Parent := FHostWindow.OverlayLayer;
  SetBounds(lRect.Left, lRect.Top, lRect.Right - lRect.Left,
            lRect.Bottom - lRect.Top);
  Visible := True;
  PerformLayout;
  Invalidate;
end;

procedure TwgPopup.ShowAsSurface(const ARect: TRect);
begin
  FSurface := TwgWindow.CreatePopup(FHostWindow, ARect.Left, ARect.Top,
    ARect.Right - ARect.Left, ARect.Bottom - ARect.Top, FGrab);
  FSurface.OnCloseQuery := @SurfaceCloseQuery;
  // Move into the popup window's own tree. Everything below — layout, damage,
  // input — then works exactly as it does in the toplevel, because it IS a
  // toplevel as far as the widget layer is concerned.
  Parent := FSurface.Root;
  SetBounds(0, 0, FSurface.ClientWidth, FSurface.ClientHeight);
  Visible := True;
  PerformLayout;
  Invalidate;
end;

procedure TwgPopup.SurfaceCloseQuery(Sender: TObject; var ACanClose: Boolean);
begin
  // The compositor dismissed the popup (an outside click under a grab, or the
  // parent losing focus). Unwind our side too.
  ACanClose := True;
  if FOpen then
    Close;
end;

procedure TwgPopup.Close;
var
  lSurface: TwgWindow;
begin
  if not FOpen then
    Exit;
  FOpen := False;
  Visible := False;
  Parent := nil;

  FreeAndNil(FCatcher);

  if FSurface <> nil then
  begin
    // Detach before freeing: the surface owns a tree we have just left, and
    // its destructor must not try to free content that belongs to us.
    lSurface := FSurface;
    FSurface := nil;
    lSurface.OnCloseQuery := nil;
    lSurface.Free;
  end
  else if FHostWindow <> nil then
    // The overlay left a hole; the window has to repaint what was under it.
    FHostWindow.Invalidate;

  if Assigned(FOnClose) then
    FOnClose(Self);
end;

procedure TwgPopup.KeyDown(var AEvent: TwgKeyEvent);
begin
  if AEvent.KeySym = wgKeyEscape then
  begin
    AEvent.Handled := True;
    Close;
  end;
end;

procedure TwgPopup.Paint(ACanvas: TwgCanvas);
var
  lTheme: TwgTheme;
begin
  lTheme := Theme;
  if lTheme = nil then
    Exit;
  // A popup is a raised surface over arbitrary content, so it must be opaque
  // and outlined — there is no guarantee about what is behind it.
  lTheme.DrawPanel(ACanvas, Rect(0, 0, Width, Height));
  lTheme.DrawBorder(ACanvas, Rect(0, 0, Width, Height), lTheme.Palette.Border);
end;

{ TwgTooltip }

constructor TwgTooltip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Never: see the class comment.
  Grab := False;
  FLabel := TwgLabel.Create(Self);
  FLabel.Align := chLeft;
  SetContent(FLabel);
end;

procedure TwgTooltip.SetText(const AValue: String);
begin
  FLabel.Caption := AValue;
end;

function TwgTooltip.GetText: String;
begin
  Result := FLabel.Caption;
end;

end.
