#ifndef VirtualDisplayBridge_h
#define VirtualDisplayBridge_h

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// CGVirtualDisplay private API bridge for Swift
// These classes are private CoreGraphics API, available macOS 11+

NS_ASSUME_NONNULL_BEGIN

/// Creates a virtual display that macOS treats as a real second monitor.
/// Returns the CGDirectDisplayID of the created display, or 0 on failure.
CGDirectDisplayID VDBCreateVirtualDisplay(
    unsigned int width,
    unsigned int height,
    unsigned int hiDPI,
    const char *name
);

/// Destroys a previously created virtual display.
void VDBDestroyVirtualDisplay(void);

/// Returns YES if virtual display is currently active.
BOOL VDBIsVirtualDisplayActive(void);

/// Returns the display ID of the active virtual display, or 0 if none.
CGDirectDisplayID VDBGetDisplayID(void);

/// Gets the bounds (origin + size) of the virtual display in global coordinates.
CGRect VDBGetDisplayBounds(void);

NS_ASSUME_NONNULL_END

#endif /* VirtualDisplayBridge_h */
