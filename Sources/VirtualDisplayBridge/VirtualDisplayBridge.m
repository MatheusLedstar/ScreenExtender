#import "VirtualDisplayBridge.h"
#import <objc/runtime.h>
#import <dlfcn.h>

// Private CoreGraphics API declarations (class-dumped from macOS headers)
// Stable from macOS 11 through macOS 15

@interface CGVirtualDisplayDescriptor : NSObject
@property (retain, nonatomic) NSString *name;
@property (nonatomic) unsigned int vendorID;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) CGSize sizeInMillimeters;
@property (retain, nonatomic) dispatch_queue_t queue;
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width
                       height:(unsigned int)height
                  refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (nonatomic) unsigned int hiDPI;
@property (retain, nonatomic) NSArray *modes;
@end

@interface CGVirtualDisplay : NSObject
@property (readonly, nonatomic) unsigned int displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

// SkyLight function types (loaded dynamically via dlsym)
typedef CGError (*SLSBeginDisplayConfigurationFunc)(CGDisplayConfigRef *config);
typedef CGError (*SLSConfigureDisplayEnabledFunc)(CGDisplayConfigRef config,
                                                  CGDirectDisplayID display,
                                                  bool enabled);
typedef CGError (*SLSCompleteDisplayConfigurationFunc)(CGDisplayConfigRef config,
                                                       CGConfigureOption option,
                                                       uint32_t reserved);

static SLSBeginDisplayConfigurationFunc _slsBegin = NULL;
static SLSConfigureDisplayEnabledFunc _slsEnable = NULL;
static SLSCompleteDisplayConfigurationFunc _slsComplete = NULL;
static BOOL _slsLoaded = NO;

static void _loadSkyLight(void) {
    if (_slsLoaded) return;
    _slsLoaded = YES;

    void *handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    if (!handle) {
        NSLog(@"[VDB] Could not load SkyLight framework");
        return;
    }

    _slsBegin = (SLSBeginDisplayConfigurationFunc)dlsym(handle, "SLSBeginDisplayConfiguration");
    _slsEnable = (SLSConfigureDisplayEnabledFunc)dlsym(handle, "SLSConfigureDisplayEnabled");
    _slsComplete = (SLSCompleteDisplayConfigurationFunc)dlsym(handle, "SLSCompleteDisplayConfiguration");

    if (!_slsBegin || !_slsEnable || !_slsComplete) {
        NSLog(@"[VDB] Warning: Some SkyLight functions not found (begin=%p, enable=%p, complete=%p)",
              _slsBegin, _slsEnable, _slsComplete);
    }
}

// Static storage
static CGVirtualDisplay *_activeDisplay = nil;

static BOOL _isAPIAvailable(void) {
    return NSClassFromString(@"CGVirtualDisplay") != nil
        && NSClassFromString(@"CGVirtualDisplayDescriptor") != nil
        && NSClassFromString(@"CGVirtualDisplaySettings") != nil
        && NSClassFromString(@"CGVirtualDisplayMode") != nil;
}

CGDirectDisplayID VDBCreateVirtualDisplay(unsigned int width,
                                          unsigned int height,
                                          unsigned int hiDPI,
                                          const char *name) {
    if (_activeDisplay) {
        VDBDestroyVirtualDisplay();
    }

    if (!_isAPIAvailable()) {
        NSLog(@"[VDB] CGVirtualDisplay API not available on this macOS version");
        return 0;
    }

    _loadSkyLight();

    @try {
        // Create descriptor
        CGVirtualDisplayDescriptor *desc = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
        desc.name = [NSString stringWithUTF8String:name];
        desc.vendorID = 0x1234;
        desc.productID = 0x5678;
        desc.serialNum = 0x0001;
        desc.maxPixelsWide = width;
        desc.maxPixelsHigh = height;
        // Realistic physical size (27" proportions) to pass WindowServer validation
        desc.sizeInMillimeters = CGSizeMake(597, 336);
        desc.queue = dispatch_queue_create("com.screenextender.vd", DISPATCH_QUEUE_SERIAL);

        // Create display modes
        NSMutableArray *modes = [NSMutableArray array];
        CGVirtualDisplayMode *nativeMode =
            [[NSClassFromString(@"CGVirtualDisplayMode") alloc]
                initWithWidth:width height:height refreshRate:30.0];
        [modes addObject:nativeMode];

        if (hiDPI) {
            CGVirtualDisplayMode *halfMode =
                [[NSClassFromString(@"CGVirtualDisplayMode") alloc]
                    initWithWidth:width / 2 height:height / 2 refreshRate:30.0];
            [modes addObject:halfMode];
        }

        // Create settings
        CGVirtualDisplaySettings *settings =
            [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
        settings.hiDPI = hiDPI;
        settings.modes = modes;

        // Create the virtual display
        CGVirtualDisplay *display =
            [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:desc];

        if (!display) {
            NSLog(@"[VDB] Failed to create CGVirtualDisplay instance");
            return 0;
        }

        BOOL success = [display applySettings:settings];
        if (!success) {
            NSLog(@"[VDB] Failed to apply display settings");
            return 0;
        }

        CGDirectDisplayID displayID = display.displayID;
        if (displayID == 0) {
            NSLog(@"[VDB] Virtual display created but has displayID 0");
            return 0;
        }

        // Enable the display via SkyLight (if available)
        if (_slsBegin && _slsEnable && _slsComplete) {
            CGDisplayConfigRef configRef;
            CGError err = _slsBegin(&configRef);
            if (err == kCGErrorSuccess) {
                _slsEnable(configRef, displayID, true);
                CGConfigureDisplayMirrorOfDisplay(configRef, displayID, kCGNullDirectDisplay);
                _slsComplete(configRef, kCGConfigurePermanently, 0);
            } else {
                NSLog(@"[VDB] Warning: SkyLight config failed (error %d)", err);
            }
        } else {
            NSLog(@"[VDB] SkyLight functions not available, display may still work without explicit enable");
        }

        _activeDisplay = display;
        NSLog(@"[VDB] Virtual display created: ID=%u, %ux%u, HiDPI=%u",
              displayID, width, height, hiDPI);

        return displayID;

    } @catch (NSException *exception) {
        NSLog(@"[VDB] Exception: %@", exception.reason);
        return 0;
    }
}

void VDBDestroyVirtualDisplay(void) {
    if (_activeDisplay) {
        CGDirectDisplayID displayID = _activeDisplay.displayID;
        NSLog(@"[VDB] Destroying virtual display ID=%u", displayID);
        _activeDisplay = nil;
    }
}

BOOL VDBIsVirtualDisplayActive(void) {
    return _activeDisplay != nil;
}

CGDirectDisplayID VDBGetDisplayID(void) {
    return _activeDisplay ? _activeDisplay.displayID : 0;
}

CGRect VDBGetDisplayBounds(void) {
    if (!_activeDisplay) return CGRectZero;
    return CGDisplayBounds(_activeDisplay.displayID);
}
