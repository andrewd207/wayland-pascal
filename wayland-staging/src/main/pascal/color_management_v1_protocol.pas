unit color_management_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TWpImageDescriptionInfoV1Class = class of TWpImageDescriptionInfoV1;
  { TWpImageDescriptionInfoV1 }
  TWpImageDescriptionInfoV1 = class;

  TWpImageDescriptionV1Class = class of TWpImageDescriptionV1;
  { TWpImageDescriptionV1 }
  TWpImageDescriptionV1 = class;

  TWpImageDescriptionCreatorParamsV1Class = class of TWpImageDescriptionCreatorParamsV1;
  { TWpImageDescriptionCreatorParamsV1 }
  TWpImageDescriptionCreatorParamsV1 = class;

  TWpImageDescriptionCreatorIccV1Class = class of TWpImageDescriptionCreatorIccV1;
  { TWpImageDescriptionCreatorIccV1 }
  TWpImageDescriptionCreatorIccV1 = class;

  TWpColorManagementSurfaceFeedbackV1Class = class of TWpColorManagementSurfaceFeedbackV1;
  { TWpColorManagementSurfaceFeedbackV1 }
  TWpColorManagementSurfaceFeedbackV1 = class;

  TWpColorManagementSurfaceV1Class = class of TWpColorManagementSurfaceV1;
  { TWpColorManagementSurfaceV1 }
  TWpColorManagementSurfaceV1 = class;

  TWpColorManagementOutputV1Class = class of TWpColorManagementOutputV1;
  { TWpColorManagementOutputV1 }
  TWpColorManagementOutputV1 = class;

  TWpColorManagerV1Class = class of TWpColorManagerV1;
  { TWpColorManagerV1 }
  TWpColorManagerV1 = class;

  IWpColorManagerV1Listener = interface;

  [TWLIntfAttribute('destroy(),get_output(no),get_surface(no),get_surface_feedback(no),create_icc_creator(n),create_parametric_creator(n),create_windows_scrgb(n)', 'supported_intent(u),supported_feature(u),supported_tf_named(u),supported_primaries_named(u),done()')]
  { TWpColorManagerV1 }
  TWpColorManagerV1 = class(TWaylandBase)
  public type
    TError = (erUnsupportedfeature = 0, erSurfaceexists = 1);
    TRenderIntent = (rePerceptual = 0, reRelative = 1, reSaturation = 2, reAbsolute = 3, reRelativebpc = 4);
    TFeature = (feIccv2v4 = 0, feParametric = 1, feSetprimaries = 2, feSettfpower = 3, feSetluminances = 4, feSetmasteringdisplayprimaries = 5, feExtendedtargetvolume = 6, feWindowsscrgb = 7);
    TPrimaries = (prSrgb = 1, prPalm = 2, prPal = 3, prNtsc = 4, prGenericfilm = 5, prBt2020 = 6, prCie1931xyz = 7, prDcip3 = 8, prDisplayp3 = 9, prAdobergb = 10);
    TTransferFunction = (trBt1886 = 1, trGamma22 = 2, trGamma28 = 3, trSt240 = 4, trExtlinear = 5, trLog100 = 6, trLog316 = 7, trXvycc = 8, trSrgb = 9, trExtsrgb = 10, trSt2084pq = 11, trSt428 = 12, trHlg = 13);
    TSupportedIntentEvent = procedure(Sender: TWpColorManagerV1; aRenderIntent: TRenderIntent) of object;
    TSupportedFeatureEvent = procedure(Sender: TWpColorManagerV1; aFeature: TFeature) of object;
    TSupportedTfNamedEvent = procedure(Sender: TWpColorManagerV1; aTf: TTransferFunction) of object;
    TSupportedPrimariesNamedEvent = procedure(Sender: TWpColorManagerV1; aPrimaries: TPrimaries) of object;
    TDoneEvent = procedure(Sender: TWpColorManagerV1) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_OUTPUT = 1, _GET_SURFACE = 2, _GET_SURFACE_FEEDBACK = 3, _CREATE_ICC_CREATOR = 4, _CREATE_PARAMETRIC_CREATOR = 5, _CREATE_WINDOWS_SCRGB = 6);
    TEvents = (EV_SUPPORTED_INTENT = 0, EV_SUPPORTED_FEATURE = 1, EV_SUPPORTED_TF_NAMED = 2, EV_SUPPORTED_PRIMARIES_NAMED = 3, EV_DONE = 4);
  private
    FOnSupportedIntentPriv: TSupportedIntentEvent;
    FOnSupportedFeaturePriv: TSupportedFeatureEvent;
    FOnSupportedTfNamedPriv: TSupportedTfNamedEvent;
    FOnSupportedPrimariesNamedPriv: TSupportedPrimariesNamedEvent;
    FOnDonePriv: TDoneEvent;
  protected
    procedure HandleSupportedIntent(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_SUPPORTED_INTENT); virtual;
    procedure HandleSupportedFeature(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_SUPPORTED_FEATURE); virtual;
    procedure HandleSupportedTfNamed(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_SUPPORTED_TF_NAMED); virtual;
    procedure HandleSupportedPrimariesNamed(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_SUPPORTED_PRIMARIES_NAMED); virtual;
    procedure HandleDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DONE); virtual;
  published
    property OnSupportedIntent: TSupportedIntentEvent read FOnSupportedIntentPriv write FOnSupportedIntentPriv;
    property OnSupportedFeature: TSupportedFeatureEvent read FOnSupportedFeaturePriv write FOnSupportedFeaturePriv;
    property OnSupportedTfNamed: TSupportedTfNamedEvent read FOnSupportedTfNamedPriv write FOnSupportedTfNamedPriv;
    property OnSupportedPrimariesNamed: TSupportedPrimariesNamedEvent read FOnSupportedPrimariesNamedPriv write FOnSupportedPrimariesNamedPriv;
    property OnDone: TDoneEvent read FOnDonePriv write FOnDonePriv;
  public
    destructor Destroy; override;
    function GetOutput(aOutput: TWlOutput; aClassType: TWpColorManagementOutputV1Class = nil): TWpColorManagementOutputV1;
    function GetSurface(aSurface: TWlSurface; aClassType: TWpColorManagementSurfaceV1Class = nil): TWpColorManagementSurfaceV1;
    function GetSurfaceFeedback(aSurface: TWlSurface; aClassType: TWpColorManagementSurfaceFeedbackV1Class = nil): TWpColorManagementSurfaceFeedbackV1;
    function CreateIccCreator(aClassType: TWpImageDescriptionCreatorIccV1Class = nil): TWpImageDescriptionCreatorIccV1;
    function CreateParametricCreator(aClassType: TWpImageDescriptionCreatorParamsV1Class = nil): TWpImageDescriptionCreatorParamsV1;
    function CreateWindowsScrgb(aClassType: TWpImageDescriptionV1Class = nil): TWpImageDescriptionV1;
  private
    FListeners: array of IWpColorManagerV1Listener;
  public
    function AddListener(AIntf: IWpColorManagerV1Listener): LongInt;
  end;

  IWpColorManagerV1Listener = interface
  ['IWpColorManagerV1Listener']
    procedure wp_color_manager_v1_supported_intent(AWpColorManagerV1: TWpColorManagerV1; aRenderIntent: TWpColorManagerV1.TRenderIntent);
    procedure wp_color_manager_v1_supported_feature(AWpColorManagerV1: TWpColorManagerV1; aFeature: TWpColorManagerV1.TFeature);
    procedure wp_color_manager_v1_supported_tf_named(AWpColorManagerV1: TWpColorManagerV1; aTf: TWpColorManagerV1.TTransferFunction);
    procedure wp_color_manager_v1_supported_primaries_named(AWpColorManagerV1: TWpColorManagerV1; aPrimaries: TWpColorManagerV1.TPrimaries);
    procedure wp_color_manager_v1_done(AWpColorManagerV1: TWpColorManagerV1);
  end;

  IWpColorManagementOutputV1Listener = interface;

  [TWLIntfAttribute('destroy(),get_image_description(n)', 'image_description_changed()')]
  { TWpColorManagementOutputV1 }
  TWpColorManagementOutputV1 = class(TWaylandBase)
  public type
    TImageDescriptionChangedEvent = procedure(Sender: TWpColorManagementOutputV1) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_IMAGE_DESCRIPTION = 1);
    TEvents = (EV_IMAGE_DESCRIPTION_CHANGED = 0);
  private
    FOnImageDescriptionChangedPriv: TImageDescriptionChangedEvent;
  protected
    procedure HandleImageDescriptionChanged(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_IMAGE_DESCRIPTION_CHANGED); virtual;
  published
    property OnImageDescriptionChanged: TImageDescriptionChangedEvent read FOnImageDescriptionChangedPriv write FOnImageDescriptionChangedPriv;
  public
    destructor Destroy; override;
    function GetImageDescription(aClassType: TWpImageDescriptionV1Class = nil): TWpImageDescriptionV1;
  private
    FListeners: array of IWpColorManagementOutputV1Listener;
  public
    function AddListener(AIntf: IWpColorManagementOutputV1Listener): LongInt;
  end;

  IWpColorManagementOutputV1Listener = interface
  ['IWpColorManagementOutputV1Listener']
    procedure wp_color_management_output_v1_image_description_changed(AWpColorManagementOutputV1: TWpColorManagementOutputV1);
  end;

  IWpColorManagementSurfaceV1Listener = interface;

  [TWLIntfAttribute('destroy(),set_image_description(ou),unset_image_description()', '')]
  { TWpColorManagementSurfaceV1 }
  TWpColorManagementSurfaceV1 = class(TWaylandBase)
  public type
    TError = (erRenderintent = 0, erImagedescription = 1, erInert = 2);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _SET_IMAGE_DESCRIPTION = 1, _UNSET_IMAGE_DESCRIPTION = 2);
  public
    destructor Destroy; override;
    procedure SetImageDescription(aImageDescription: TWpImageDescriptionV1; aRenderIntent: TWpColorManagerV1.TRenderIntent);
    procedure UnsetImageDescription;
  private
    FListeners: array of IWpColorManagementSurfaceV1Listener;
  public
    function AddListener(AIntf: IWpColorManagementSurfaceV1Listener): LongInt;
  end;

  IWpColorManagementSurfaceV1Listener = interface
  ['IWpColorManagementSurfaceV1Listener']
  end;

  IWpColorManagementSurfaceFeedbackV1Listener = interface;

  [TWLIntfAttribute('destroy(),get_preferred(n),get_preferred_parametric(n)', 'preferred_changed(u)')]
  { TWpColorManagementSurfaceFeedbackV1 }
  TWpColorManagementSurfaceFeedbackV1 = class(TWaylandBase)
  public type
    TError = (erInert = 0, erUnsupportedfeature = 1);
    TPreferredChangedEvent = procedure(Sender: TWpColorManagementSurfaceFeedbackV1; aIdentity: DWord) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_PREFERRED = 1, _GET_PREFERRED_PARAMETRIC = 2);
    TEvents = (EV_PREFERRED_CHANGED = 0);
  private
    FOnPreferredChangedPriv: TPreferredChangedEvent;
  protected
    procedure HandlePreferredChanged(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_PREFERRED_CHANGED); virtual;
  published
    property OnPreferredChanged: TPreferredChangedEvent read FOnPreferredChangedPriv write FOnPreferredChangedPriv;
  public
    destructor Destroy; override;
    function GetPreferred(aClassType: TWpImageDescriptionV1Class = nil): TWpImageDescriptionV1;
    function GetPreferredParametric(aClassType: TWpImageDescriptionV1Class = nil): TWpImageDescriptionV1;
  private
    FListeners: array of IWpColorManagementSurfaceFeedbackV1Listener;
  public
    function AddListener(AIntf: IWpColorManagementSurfaceFeedbackV1Listener): LongInt;
  end;

  IWpColorManagementSurfaceFeedbackV1Listener = interface
  ['IWpColorManagementSurfaceFeedbackV1Listener']
    procedure wp_color_management_surface_feedback_v1_preferred_changed(AWpColorManagementSurfaceFeedbackV1: TWpColorManagementSurfaceFeedbackV1; aIdentity: DWord);
  end;

  IWpImageDescriptionCreatorIccV1Listener = interface;

  [TWLIntfAttribute('create(n),set_icc_file(huu)', '')]
  { TWpImageDescriptionCreatorIccV1 }
  TWpImageDescriptionCreatorIccV1 = class(TWaylandBase)
  public type
    TError = (erIncompleteset = 0, erAlreadyset = 1, erBadfd = 2, erBadsize = 3, erOutoffile = 4);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_CREATE = 0, _SET_ICC_FILE = 1);
  public
    function Create_(aClassType: TWpImageDescriptionV1Class = nil): TWpImageDescriptionV1;
    procedure SetIccFile(aIccProfile: Integer; aOffset: DWord; aLength: DWord);
  private
    FListeners: array of IWpImageDescriptionCreatorIccV1Listener;
  public
    function AddListener(AIntf: IWpImageDescriptionCreatorIccV1Listener): LongInt;
  end;

  IWpImageDescriptionCreatorIccV1Listener = interface
  ['IWpImageDescriptionCreatorIccV1Listener']
  end;

  IWpImageDescriptionCreatorParamsV1Listener = interface;

  [TWLIntfAttribute('create(n),set_tf_named(u),set_tf_power(u),set_primaries_named(u),set_primaries(iiiiiiii),set_luminances(uuu),set_mastering_display_primaries(iiiiiiii),set_mastering_luminance(uu),set_max_cll(u),set_max_fall(u)', '')]
  { TWpImageDescriptionCreatorParamsV1 }
  TWpImageDescriptionCreatorParamsV1 = class(TWaylandBase)
  public type
    TError = (erIncompleteset = 0, erAlreadyset = 1, erUnsupportedfeature = 2, erInvalidtf = 3, erInvalidprimariesnamed = 4, erInvalidluminance = 5);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_CREATE = 0, _SET_TF_NAMED = 1, _SET_TF_POWER = 2, _SET_PRIMARIES_NAMED = 3, _SET_PRIMARIES = 4, _SET_LUMINANCES = 5, _SET_MASTERING_DISPLAY_PRIMARIES = 6, _SET_MASTERING_LUMINANCE = 7, _SET_MAX_CLL = 8, _SET_MAX_FALL = 9);
  public
    function Create_(aClassType: TWpImageDescriptionV1Class = nil): TWpImageDescriptionV1;
    procedure SetTfNamed(aTf: TWpColorManagerV1.TTransferFunction);
    procedure SetTfPower(aEexp: DWord);
    procedure SetPrimariesNamed(aPrimaries: TWpColorManagerV1.TPrimaries);
    procedure SetPrimaries(aRX: Integer; aRY: Integer; aGX: Integer; aGY: Integer; aBX: Integer; aBY: Integer; aWX: Integer; aWY: Integer);
    procedure SetLuminances(aMinLum: DWord; aMaxLum: DWord; aReferenceLum: DWord);
    procedure SetMasteringDisplayPrimaries(aRX: Integer; aRY: Integer; aGX: Integer; aGY: Integer; aBX: Integer; aBY: Integer; aWX: Integer; aWY: Integer);
    procedure SetMasteringLuminance(aMinLum: DWord; aMaxLum: DWord);
    procedure SetMaxCll(aMaxCll: DWord);
    procedure SetMaxFall(aMaxFall: DWord);
  private
    FListeners: array of IWpImageDescriptionCreatorParamsV1Listener;
  public
    function AddListener(AIntf: IWpImageDescriptionCreatorParamsV1Listener): LongInt;
  end;

  IWpImageDescriptionCreatorParamsV1Listener = interface
  ['IWpImageDescriptionCreatorParamsV1Listener']
  end;

  IWpImageDescriptionV1Listener = interface;

  [TWLIntfAttribute('destroy(),get_information(n)', 'failed(us),ready(u)')]
  { TWpImageDescriptionV1 }
  TWpImageDescriptionV1 = class(TWaylandBase)
  public type
    TError = (erNotready = 0, erNoinformation = 1);
    TCause = (caLowversion = 0, caUnsupported = 1, caOperatingsystem = 2, caNooutput = 3);
    TFailedEvent = procedure(Sender: TWpImageDescriptionV1; aCause: TCause; aMsg: String) of object;
    TReadyEvent = procedure(Sender: TWpImageDescriptionV1; aIdentity: DWord) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_INFORMATION = 1);
    TEvents = (EV_FAILED = 0, EV_READY = 1);
  private
    FOnFailedPriv: TFailedEvent;
    FOnReadyPriv: TReadyEvent;
  protected
    procedure HandleFailed(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FAILED); virtual;
    procedure HandleReady(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_READY); virtual;
  published
    property OnFailed: TFailedEvent read FOnFailedPriv write FOnFailedPriv;
    property OnReady: TReadyEvent read FOnReadyPriv write FOnReadyPriv;
  public
    destructor Destroy; override;
    function GetInformation(aClassType: TWpImageDescriptionInfoV1Class = nil): TWpImageDescriptionInfoV1;
  private
    FListeners: array of IWpImageDescriptionV1Listener;
  public
    function AddListener(AIntf: IWpImageDescriptionV1Listener): LongInt;
  end;

  IWpImageDescriptionV1Listener = interface
  ['IWpImageDescriptionV1Listener']
    procedure wp_image_description_v1_failed(AWpImageDescriptionV1: TWpImageDescriptionV1; aCause: TWpImageDescriptionV1.TCause; aMsg: String);
    procedure wp_image_description_v1_ready(AWpImageDescriptionV1: TWpImageDescriptionV1; aIdentity: DWord);
  end;

  IWpImageDescriptionInfoV1Listener = interface;

  [TWLIntfAttribute('', 'done(),icc_file(hu),primaries(iiiiiiii),primaries_named(u),tf_power(u),tf_named(u),luminances(uuu),target_primaries(iiiiiiii),target_luminance(uu),target_max_cll(u),target_max_fall(u)')]
  { TWpImageDescriptionInfoV1 }
  TWpImageDescriptionInfoV1 = class(TWaylandBase)
  public type
    TDoneEvent = procedure(Sender: TWpImageDescriptionInfoV1) of object;
    TIccFileEvent = procedure(Sender: TWpImageDescriptionInfoV1; aIcc: Integer; aIccSize: DWord) of object;
    TPrimariesEvent = procedure(Sender: TWpImageDescriptionInfoV1; aRX: Integer; aRY: Integer; aGX: Integer; aGY: Integer; aBX: Integer; aBY: Integer; aWX: Integer; aWY: Integer) of object;
    TPrimariesNamedEvent = procedure(Sender: TWpImageDescriptionInfoV1; aPrimaries: TWpColorManagerV1.TPrimaries) of object;
    TTfPowerEvent = procedure(Sender: TWpImageDescriptionInfoV1; aEexp: DWord) of object;
    TTfNamedEvent = procedure(Sender: TWpImageDescriptionInfoV1; aTf: TWpColorManagerV1.TTransferFunction) of object;
    TLuminancesEvent = procedure(Sender: TWpImageDescriptionInfoV1; aMinLum: DWord; aMaxLum: DWord; aReferenceLum: DWord) of object;
    TTargetPrimariesEvent = procedure(Sender: TWpImageDescriptionInfoV1; aRX: Integer; aRY: Integer; aGX: Integer; aGY: Integer; aBX: Integer; aBY: Integer; aWX: Integer; aWY: Integer) of object;
    TTargetLuminanceEvent = procedure(Sender: TWpImageDescriptionInfoV1; aMinLum: DWord; aMaxLum: DWord) of object;
    TTargetMaxCllEvent = procedure(Sender: TWpImageDescriptionInfoV1; aMaxCll: DWord) of object;
    TTargetMaxFallEvent = procedure(Sender: TWpImageDescriptionInfoV1; aMaxFall: DWord) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TEvents = (EV_DONE = 0, EV_ICC_FILE = 1, EV_PRIMARIES = 2, EV_PRIMARIES_NAMED = 3, EV_TF_POWER = 4, EV_TF_NAMED = 5, EV_LUMINANCES = 6, EV_TARGET_PRIMARIES = 7, EV_TARGET_LUMINANCE = 8, EV_TARGET_MAX_CLL = 9, EV_TARGET_MAX_FALL = 10);
  private
    FOnDonePriv: TDoneEvent;
    FOnIccFilePriv: TIccFileEvent;
    FOnPrimariesPriv: TPrimariesEvent;
    FOnPrimariesNamedPriv: TPrimariesNamedEvent;
    FOnTfPowerPriv: TTfPowerEvent;
    FOnTfNamedPriv: TTfNamedEvent;
    FOnLuminancesPriv: TLuminancesEvent;
    FOnTargetPrimariesPriv: TTargetPrimariesEvent;
    FOnTargetLuminancePriv: TTargetLuminanceEvent;
    FOnTargetMaxCllPriv: TTargetMaxCllEvent;
    FOnTargetMaxFallPriv: TTargetMaxFallEvent;
  protected
    procedure HandleDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DONE); virtual;
    procedure HandleIccFile(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ICC_FILE); virtual;
    procedure HandlePrimaries(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_PRIMARIES); virtual;
    procedure HandlePrimariesNamed(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_PRIMARIES_NAMED); virtual;
    procedure HandleTfPower(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TF_POWER); virtual;
    procedure HandleTfNamed(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TF_NAMED); virtual;
    procedure HandleLuminances(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_LUMINANCES); virtual;
    procedure HandleTargetPrimaries(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TARGET_PRIMARIES); virtual;
    procedure HandleTargetLuminance(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TARGET_LUMINANCE); virtual;
    procedure HandleTargetMaxCll(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TARGET_MAX_CLL); virtual;
    procedure HandleTargetMaxFall(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TARGET_MAX_FALL); virtual;
  published
    property OnDone: TDoneEvent read FOnDonePriv write FOnDonePriv;
    property OnIccFile: TIccFileEvent read FOnIccFilePriv write FOnIccFilePriv;
    property OnPrimaries: TPrimariesEvent read FOnPrimariesPriv write FOnPrimariesPriv;
    property OnPrimariesNamed: TPrimariesNamedEvent read FOnPrimariesNamedPriv write FOnPrimariesNamedPriv;
    property OnTfPower: TTfPowerEvent read FOnTfPowerPriv write FOnTfPowerPriv;
    property OnTfNamed: TTfNamedEvent read FOnTfNamedPriv write FOnTfNamedPriv;
    property OnLuminances: TLuminancesEvent read FOnLuminancesPriv write FOnLuminancesPriv;
    property OnTargetPrimaries: TTargetPrimariesEvent read FOnTargetPrimariesPriv write FOnTargetPrimariesPriv;
    property OnTargetLuminance: TTargetLuminanceEvent read FOnTargetLuminancePriv write FOnTargetLuminancePriv;
    property OnTargetMaxCll: TTargetMaxCllEvent read FOnTargetMaxCllPriv write FOnTargetMaxCllPriv;
    property OnTargetMaxFall: TTargetMaxFallEvent read FOnTargetMaxFallPriv write FOnTargetMaxFallPriv;
  private
    FListeners: array of IWpImageDescriptionInfoV1Listener;
  public
    function AddListener(AIntf: IWpImageDescriptionInfoV1Listener): LongInt;
  end;

  IWpImageDescriptionInfoV1Listener = interface
  ['IWpImageDescriptionInfoV1Listener']
    procedure wp_image_description_info_v1_done(AWpImageDescriptionInfoV1: TWpImageDescriptionInfoV1);
    procedure wp_image_description_info_v1_icc_file(AWpImageDescriptionInfoV1: TWpImageDescriptionInfoV1; aIcc: Integer; aIccSize: DWord);
    procedure wp_image_description_info_v1_primaries(AWpImageDescriptionInfoV1: TWpImageDescriptionInfoV1; aRX: Integer; aRY: Integer; aGX: Integer; aGY: Integer; aBX: Integer; aBY: Integer; aWX: Integer; aWY: Integer);
    procedure wp_image_description_info_v1_primaries_named(AWpImageDescriptionInfoV1: TWpImageDescriptionInfoV1; aPrimaries: TWpColorManagerV1.TPrimaries);
    procedure wp_image_description_info_v1_tf_power(AWpImageDescriptionInfoV1: TWpImageDescriptionInfoV1; aEexp: DWord);
    procedure wp_image_description_info_v1_tf_named(AWpImageDescriptionInfoV1: TWpImageDescriptionInfoV1; aTf: TWpColorManagerV1.TTransferFunction);
    procedure wp_image_description_info_v1_luminances(AWpImageDescriptionInfoV1: TWpImageDescriptionInfoV1; aMinLum: DWord; aMaxLum: DWord; aReferenceLum: DWord);
    procedure wp_image_description_info_v1_target_primaries(AWpImageDescriptionInfoV1: TWpImageDescriptionInfoV1; aRX: Integer; aRY: Integer; aGX: Integer; aGY: Integer; aBX: Integer; aBY: Integer; aWX: Integer; aWY: Integer);
    procedure wp_image_description_info_v1_target_luminance(AWpImageDescriptionInfoV1: TWpImageDescriptionInfoV1; aMinLum: DWord; aMaxLum: DWord);
    procedure wp_image_description_info_v1_target_max_cll(AWpImageDescriptionInfoV1: TWpImageDescriptionInfoV1; aMaxCll: DWord);
    procedure wp_image_description_info_v1_target_max_fall(AWpImageDescriptionInfoV1: TWpImageDescriptionInfoV1; aMaxFall: DWord);
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TWpColorManagerV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpColorManagerV1.GetInterfaceName: String;
begin
  Result := 'wp_color_manager_v1';
end;

procedure TWpColorManagerV1.HandleSupportedIntent(var AMsg: TWaylandEventMessage);
var
  lRenderIntent: TRenderIntent;
  lListenerIdx: Integer;
begin
  lRenderIntent := TRenderIntent(AMsg.Args.ReadDWord);
  if Assigned(OnSupportedIntent) then OnSupportedIntent(Self,lRenderIntent);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_color_manager_v1_supported_intent(Self,lRenderIntent);
  AMsg.SetHandled;
end;

procedure TWpColorManagerV1.HandleSupportedFeature(var AMsg: TWaylandEventMessage);
var
  lFeature: TFeature;
  lListenerIdx: Integer;
begin
  lFeature := TFeature(AMsg.Args.ReadDWord);
  if Assigned(OnSupportedFeature) then OnSupportedFeature(Self,lFeature);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_color_manager_v1_supported_feature(Self,lFeature);
  AMsg.SetHandled;
end;

procedure TWpColorManagerV1.HandleSupportedTfNamed(var AMsg: TWaylandEventMessage);
var
  lTf: TTransferFunction;
  lListenerIdx: Integer;
begin
  lTf := TTransferFunction(AMsg.Args.ReadDWord);
  if Assigned(OnSupportedTfNamed) then OnSupportedTfNamed(Self,lTf);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_color_manager_v1_supported_tf_named(Self,lTf);
  AMsg.SetHandled;
end;

procedure TWpColorManagerV1.HandleSupportedPrimariesNamed(var AMsg: TWaylandEventMessage);
var
  lPrimaries: TPrimaries;
  lListenerIdx: Integer;
begin
  lPrimaries := TPrimaries(AMsg.Args.ReadDWord);
  if Assigned(OnSupportedPrimariesNamed) then OnSupportedPrimariesNamed(Self,lPrimaries);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_color_manager_v1_supported_primaries_named(Self,lPrimaries);
  AMsg.SetHandled;
end;

procedure TWpColorManagerV1.HandleDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDone) then OnDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_color_manager_v1_done(Self);
  AMsg.SetHandled;
end;

destructor TWpColorManagerV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpColorManagerV1.GetOutput(aOutput: TWlOutput; aClassType: TWpColorManagementOutputV1Class = nil): TWpColorManagementOutputV1;
begin
  if aClassType = nil then aClassType := TWpColorManagementOutputV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_OUTPUT), [Result.GetObjectId,aOutput.GetObjectId]);
end;

function TWpColorManagerV1.GetSurface(aSurface: TWlSurface; aClassType: TWpColorManagementSurfaceV1Class = nil): TWpColorManagementSurfaceV1;
begin
  if aClassType = nil then aClassType := TWpColorManagementSurfaceV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_SURFACE), [Result.GetObjectId,aSurface.GetObjectId]);
end;

function TWpColorManagerV1.GetSurfaceFeedback(aSurface: TWlSurface; aClassType: TWpColorManagementSurfaceFeedbackV1Class = nil): TWpColorManagementSurfaceFeedbackV1;
begin
  if aClassType = nil then aClassType := TWpColorManagementSurfaceFeedbackV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_SURFACE_FEEDBACK), [Result.GetObjectId,aSurface.GetObjectId]);
end;

function TWpColorManagerV1.CreateIccCreator(aClassType: TWpImageDescriptionCreatorIccV1Class = nil): TWpImageDescriptionCreatorIccV1;
begin
  if aClassType = nil then aClassType := TWpImageDescriptionCreatorIccV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_ICC_CREATOR), [Result.GetObjectId]);
end;

function TWpColorManagerV1.CreateParametricCreator(aClassType: TWpImageDescriptionCreatorParamsV1Class = nil): TWpImageDescriptionCreatorParamsV1;
begin
  if aClassType = nil then aClassType := TWpImageDescriptionCreatorParamsV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_PARAMETRIC_CREATOR), [Result.GetObjectId]);
end;

function TWpColorManagerV1.CreateWindowsScrgb(aClassType: TWpImageDescriptionV1Class = nil): TWpImageDescriptionV1;
begin
  if aClassType = nil then aClassType := TWpImageDescriptionV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_WINDOWS_SCRGB), [Result.GetObjectId]);
end;

function TWpColorManagerV1.AddListener(AIntf: IWpColorManagerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpColorManagementOutputV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpColorManagementOutputV1.GetInterfaceName: String;
begin
  Result := 'wp_color_management_output_v1';
end;

procedure TWpColorManagementOutputV1.HandleImageDescriptionChanged(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnImageDescriptionChanged) then OnImageDescriptionChanged(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_color_management_output_v1_image_description_changed(Self);
  AMsg.SetHandled;
end;

destructor TWpColorManagementOutputV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpColorManagementOutputV1.GetImageDescription(aClassType: TWpImageDescriptionV1Class = nil): TWpImageDescriptionV1;
begin
  if aClassType = nil then aClassType := TWpImageDescriptionV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_IMAGE_DESCRIPTION), [Result.GetObjectId]);
end;

function TWpColorManagementOutputV1.AddListener(AIntf: IWpColorManagementOutputV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpColorManagementSurfaceV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpColorManagementSurfaceV1.GetInterfaceName: String;
begin
  Result := 'wp_color_management_surface_v1';
end;

destructor TWpColorManagementSurfaceV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TWpColorManagementSurfaceV1.SetImageDescription(aImageDescription: TWpImageDescriptionV1; aRenderIntent: TWpColorManagerV1.TRenderIntent);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_IMAGE_DESCRIPTION), [aImageDescription.GetObjectId,DWord(aRenderIntent)]);
end;

procedure TWpColorManagementSurfaceV1.UnsetImageDescription;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._UNSET_IMAGE_DESCRIPTION), []);
end;

function TWpColorManagementSurfaceV1.AddListener(AIntf: IWpColorManagementSurfaceV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpColorManagementSurfaceFeedbackV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpColorManagementSurfaceFeedbackV1.GetInterfaceName: String;
begin
  Result := 'wp_color_management_surface_feedback_v1';
end;

procedure TWpColorManagementSurfaceFeedbackV1.HandlePreferredChanged(var AMsg: TWaylandEventMessage);
var
  lIdentity: DWord;
  lListenerIdx: Integer;
begin
  lIdentity := AMsg.Args.ReadDWord;
  if Assigned(OnPreferredChanged) then OnPreferredChanged(Self,lIdentity);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_color_management_surface_feedback_v1_preferred_changed(Self,lIdentity);
  AMsg.SetHandled;
end;

destructor TWpColorManagementSurfaceFeedbackV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpColorManagementSurfaceFeedbackV1.GetPreferred(aClassType: TWpImageDescriptionV1Class = nil): TWpImageDescriptionV1;
begin
  if aClassType = nil then aClassType := TWpImageDescriptionV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_PREFERRED), [Result.GetObjectId]);
end;

function TWpColorManagementSurfaceFeedbackV1.GetPreferredParametric(aClassType: TWpImageDescriptionV1Class = nil): TWpImageDescriptionV1;
begin
  if aClassType = nil then aClassType := TWpImageDescriptionV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_PREFERRED_PARAMETRIC), [Result.GetObjectId]);
end;

function TWpColorManagementSurfaceFeedbackV1.AddListener(AIntf: IWpColorManagementSurfaceFeedbackV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpImageDescriptionCreatorIccV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpImageDescriptionCreatorIccV1.GetInterfaceName: String;
begin
  Result := 'wp_image_description_creator_icc_v1';
end;

function TWpImageDescriptionCreatorIccV1.Create_(aClassType: TWpImageDescriptionV1Class = nil): TWpImageDescriptionV1;
begin
  if aClassType = nil then aClassType := TWpImageDescriptionV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE), [Result.GetObjectId]);
end;

procedure TWpImageDescriptionCreatorIccV1.SetIccFile(aIccProfile: Integer; aOffset: DWord; aLength: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_ICC_FILE), [aIccProfile,aOffset,aLength], 0);
end;

function TWpImageDescriptionCreatorIccV1.AddListener(AIntf: IWpImageDescriptionCreatorIccV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpImageDescriptionCreatorParamsV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpImageDescriptionCreatorParamsV1.GetInterfaceName: String;
begin
  Result := 'wp_image_description_creator_params_v1';
end;

function TWpImageDescriptionCreatorParamsV1.Create_(aClassType: TWpImageDescriptionV1Class = nil): TWpImageDescriptionV1;
begin
  if aClassType = nil then aClassType := TWpImageDescriptionV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE), [Result.GetObjectId]);
end;

procedure TWpImageDescriptionCreatorParamsV1.SetTfNamed(aTf: TWpColorManagerV1.TTransferFunction);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_TF_NAMED), [DWord(aTf)]);
end;

procedure TWpImageDescriptionCreatorParamsV1.SetTfPower(aEexp: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_TF_POWER), [aEexp]);
end;

procedure TWpImageDescriptionCreatorParamsV1.SetPrimariesNamed(aPrimaries: TWpColorManagerV1.TPrimaries);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_PRIMARIES_NAMED), [DWord(aPrimaries)]);
end;

procedure TWpImageDescriptionCreatorParamsV1.SetPrimaries(aRX: Integer; aRY: Integer; aGX: Integer; aGY: Integer; aBX: Integer; aBY: Integer; aWX: Integer; aWY: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_PRIMARIES), [aRX,aRY,aGX,aGY,aBX,aBY,aWX,aWY]);
end;

procedure TWpImageDescriptionCreatorParamsV1.SetLuminances(aMinLum: DWord; aMaxLum: DWord; aReferenceLum: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_LUMINANCES), [aMinLum,aMaxLum,aReferenceLum]);
end;

procedure TWpImageDescriptionCreatorParamsV1.SetMasteringDisplayPrimaries(aRX: Integer; aRY: Integer; aGX: Integer; aGY: Integer; aBX: Integer; aBY: Integer; aWX: Integer; aWY: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_MASTERING_DISPLAY_PRIMARIES), [aRX,aRY,aGX,aGY,aBX,aBY,aWX,aWY]);
end;

procedure TWpImageDescriptionCreatorParamsV1.SetMasteringLuminance(aMinLum: DWord; aMaxLum: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_MASTERING_LUMINANCE), [aMinLum,aMaxLum]);
end;

procedure TWpImageDescriptionCreatorParamsV1.SetMaxCll(aMaxCll: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_MAX_CLL), [aMaxCll]);
end;

procedure TWpImageDescriptionCreatorParamsV1.SetMaxFall(aMaxFall: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_MAX_FALL), [aMaxFall]);
end;

function TWpImageDescriptionCreatorParamsV1.AddListener(AIntf: IWpImageDescriptionCreatorParamsV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpImageDescriptionV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpImageDescriptionV1.GetInterfaceName: String;
begin
  Result := 'wp_image_description_v1';
end;

procedure TWpImageDescriptionV1.HandleFailed(var AMsg: TWaylandEventMessage);
var
  lCause: TCause;
  lMsg: String;
  lListenerIdx: Integer;
begin
  lCause := TCause(AMsg.Args.ReadDWord);
  lMsg := AMsg.Args.ReadString;
  if Assigned(OnFailed) then OnFailed(Self,lCause,lMsg);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_image_description_v1_failed(Self,lCause,lMsg);
  AMsg.SetHandled;
end;

procedure TWpImageDescriptionV1.HandleReady(var AMsg: TWaylandEventMessage);
var
  lIdentity: DWord;
  lListenerIdx: Integer;
begin
  lIdentity := AMsg.Args.ReadDWord;
  if Assigned(OnReady) then OnReady(Self,lIdentity);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_image_description_v1_ready(Self,lIdentity);
  AMsg.SetHandled;
end;

destructor TWpImageDescriptionV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpImageDescriptionV1.GetInformation(aClassType: TWpImageDescriptionInfoV1Class = nil): TWpImageDescriptionInfoV1;
begin
  if aClassType = nil then aClassType := TWpImageDescriptionInfoV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_INFORMATION), [Result.GetObjectId]);
end;

function TWpImageDescriptionV1.AddListener(AIntf: IWpImageDescriptionV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpImageDescriptionInfoV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpImageDescriptionInfoV1.GetInterfaceName: String;
begin
  Result := 'wp_image_description_info_v1';
end;

procedure TWpImageDescriptionInfoV1.HandleDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDone) then OnDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_image_description_info_v1_done(Self);
  AMsg.SetHandled;
end;

procedure TWpImageDescriptionInfoV1.HandleIccFile(var AMsg: TWaylandEventMessage);
var
  lIcc: Integer;
  lIccSize: DWord;
  lListenerIdx: Integer;
begin
  lIcc := AMsg.NextFd;
  lIccSize := AMsg.Args.ReadDWord;
  if Assigned(OnIccFile) then OnIccFile(Self,lIcc,lIccSize);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_image_description_info_v1_icc_file(Self,lIcc,lIccSize);
  AMsg.SetHandled;
end;

procedure TWpImageDescriptionInfoV1.HandlePrimaries(var AMsg: TWaylandEventMessage);
var
  lRX: Integer;
  lRY: Integer;
  lGX: Integer;
  lGY: Integer;
  lBX: Integer;
  lBY: Integer;
  lWX: Integer;
  lWY: Integer;
  lListenerIdx: Integer;
begin
  lRX := AMsg.Args.ReadInteger;
  lRY := AMsg.Args.ReadInteger;
  lGX := AMsg.Args.ReadInteger;
  lGY := AMsg.Args.ReadInteger;
  lBX := AMsg.Args.ReadInteger;
  lBY := AMsg.Args.ReadInteger;
  lWX := AMsg.Args.ReadInteger;
  lWY := AMsg.Args.ReadInteger;
  if Assigned(OnPrimaries) then OnPrimaries(Self,lRX,lRY,lGX,lGY,lBX,lBY,lWX,lWY);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_image_description_info_v1_primaries(Self,lRX,lRY,lGX,lGY,lBX,lBY,lWX,lWY);
  AMsg.SetHandled;
end;

procedure TWpImageDescriptionInfoV1.HandlePrimariesNamed(var AMsg: TWaylandEventMessage);
var
  lPrimaries: TWpColorManagerV1.TPrimaries;
  lListenerIdx: Integer;
begin
  lPrimaries := TWpColorManagerV1.TPrimaries(AMsg.Args.ReadDWord);
  if Assigned(OnPrimariesNamed) then OnPrimariesNamed(Self,lPrimaries);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_image_description_info_v1_primaries_named(Self,lPrimaries);
  AMsg.SetHandled;
end;

procedure TWpImageDescriptionInfoV1.HandleTfPower(var AMsg: TWaylandEventMessage);
var
  lEexp: DWord;
  lListenerIdx: Integer;
begin
  lEexp := AMsg.Args.ReadDWord;
  if Assigned(OnTfPower) then OnTfPower(Self,lEexp);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_image_description_info_v1_tf_power(Self,lEexp);
  AMsg.SetHandled;
end;

procedure TWpImageDescriptionInfoV1.HandleTfNamed(var AMsg: TWaylandEventMessage);
var
  lTf: TWpColorManagerV1.TTransferFunction;
  lListenerIdx: Integer;
begin
  lTf := TWpColorManagerV1.TTransferFunction(AMsg.Args.ReadDWord);
  if Assigned(OnTfNamed) then OnTfNamed(Self,lTf);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_image_description_info_v1_tf_named(Self,lTf);
  AMsg.SetHandled;
end;

procedure TWpImageDescriptionInfoV1.HandleLuminances(var AMsg: TWaylandEventMessage);
var
  lMinLum: DWord;
  lMaxLum: DWord;
  lReferenceLum: DWord;
  lListenerIdx: Integer;
begin
  lMinLum := AMsg.Args.ReadDWord;
  lMaxLum := AMsg.Args.ReadDWord;
  lReferenceLum := AMsg.Args.ReadDWord;
  if Assigned(OnLuminances) then OnLuminances(Self,lMinLum,lMaxLum,lReferenceLum);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_image_description_info_v1_luminances(Self,lMinLum,lMaxLum,lReferenceLum);
  AMsg.SetHandled;
end;

procedure TWpImageDescriptionInfoV1.HandleTargetPrimaries(var AMsg: TWaylandEventMessage);
var
  lRX: Integer;
  lRY: Integer;
  lGX: Integer;
  lGY: Integer;
  lBX: Integer;
  lBY: Integer;
  lWX: Integer;
  lWY: Integer;
  lListenerIdx: Integer;
begin
  lRX := AMsg.Args.ReadInteger;
  lRY := AMsg.Args.ReadInteger;
  lGX := AMsg.Args.ReadInteger;
  lGY := AMsg.Args.ReadInteger;
  lBX := AMsg.Args.ReadInteger;
  lBY := AMsg.Args.ReadInteger;
  lWX := AMsg.Args.ReadInteger;
  lWY := AMsg.Args.ReadInteger;
  if Assigned(OnTargetPrimaries) then OnTargetPrimaries(Self,lRX,lRY,lGX,lGY,lBX,lBY,lWX,lWY);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_image_description_info_v1_target_primaries(Self,lRX,lRY,lGX,lGY,lBX,lBY,lWX,lWY);
  AMsg.SetHandled;
end;

procedure TWpImageDescriptionInfoV1.HandleTargetLuminance(var AMsg: TWaylandEventMessage);
var
  lMinLum: DWord;
  lMaxLum: DWord;
  lListenerIdx: Integer;
begin
  lMinLum := AMsg.Args.ReadDWord;
  lMaxLum := AMsg.Args.ReadDWord;
  if Assigned(OnTargetLuminance) then OnTargetLuminance(Self,lMinLum,lMaxLum);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_image_description_info_v1_target_luminance(Self,lMinLum,lMaxLum);
  AMsg.SetHandled;
end;

procedure TWpImageDescriptionInfoV1.HandleTargetMaxCll(var AMsg: TWaylandEventMessage);
var
  lMaxCll: DWord;
  lListenerIdx: Integer;
begin
  lMaxCll := AMsg.Args.ReadDWord;
  if Assigned(OnTargetMaxCll) then OnTargetMaxCll(Self,lMaxCll);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_image_description_info_v1_target_max_cll(Self,lMaxCll);
  AMsg.SetHandled;
end;

procedure TWpImageDescriptionInfoV1.HandleTargetMaxFall(var AMsg: TWaylandEventMessage);
var
  lMaxFall: DWord;
  lListenerIdx: Integer;
begin
  lMaxFall := AMsg.Args.ReadDWord;
  if Assigned(OnTargetMaxFall) then OnTargetMaxFall(Self,lMaxFall);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_image_description_info_v1_target_max_fall(Self,lMaxFall);
  AMsg.SetHandled;
end;

function TWpImageDescriptionInfoV1.AddListener(AIntf: IWpImageDescriptionInfoV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.