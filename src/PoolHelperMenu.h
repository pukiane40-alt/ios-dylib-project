/**
 * PoolHelperMenu.h
 *
 * Public header for PoolHelperMenu.dylib
 * iOS Dynamic Library — Pool Helper Menu (UI Demo)
 *
 * Import this header if you want to reference OverlayManager
 * from another Objective-C translation unit.
 *
 * In normal usage the library self-initialises via the
 * __attribute__((constructor)) in PoolHelperMenu.m — you do not
 * need to call anything manually.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * OverlayManager
 * Singleton that owns the entire overlay UI system.
 * Automatically launched when the dylib is loaded.
 */
@interface OverlayManager : NSObject

/// Returns the shared singleton instance.
+ (instancetype)sharedInstance;

/// Initialises and presents the floating button and menu.
/// Called automatically by the library constructor.
- (void)launch;

@end

NS_ASSUME_NONNULL_END
