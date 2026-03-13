/**
 * FloatingMenu.m
 *
 * Minimal iOS Dynamic Library — Objective-C / UIKit
 *
 * Adds a small draggable "Menu" button to the app's key UIWindow
 * without blocking the game screen.
 *
 * Compile (ARM64):
 *   clang -arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
 *         -miphoneos-version-min=14.0 \
 *         -framework UIKit -framework Foundation \
 *         -dynamiclib -fobjc-arc \
 *         -install_name @rpath/FloatingMenu.dylib \
 *         -o FloatingMenu.dylib FloatingMenu.m
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

/* ── FloatingMenuButton ─────────────────────────────────────────────────── */

@interface FloatingMenuButton : NSObject
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, assign) CGPoint   dragStart;
@property (nonatomic, assign) CGPoint   buttonStart;
@property (nonatomic, assign) BOOL      dragged;
- (void)attachToWindow:(UIWindow *)window;
@end

@implementation FloatingMenuButton

- (void)attachToWindow:(UIWindow *)window {
    CGFloat size = 52.0;
    CGFloat margin = 12.0;
    CGSize  screen = window.bounds.size;

    _button = [UIButton buttonWithType:UIButtonTypeCustom];
    _button.frame = CGRectMake(screen.width - size - margin,
                               screen.height * 0.40,
                               size, size);

    /* Appearance */
    _button.layer.cornerRadius  = size / 2.0;
    _button.layer.masksToBounds = YES;
    _button.backgroundColor = [UIColor colorWithRed:0.10
                                              green:0.10
                                               blue:0.12
                                              alpha:0.88];
    _button.layer.borderColor = [UIColor colorWithWhite:1.0
                                                  alpha:0.25].CGColor;
    _button.layer.borderWidth = 1.0;

    [_button setTitle:@"Menu" forState:UIControlStateNormal];
    [_button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _button.titleLabel.font = [UIFont systemFontOfSize:13
                                                weight:UIFontWeightSemibold];

    /* Drop shadow (outside masksToBounds — apply on layer of a wrapper or
       set masksToBounds NO and clip manually; simplest: shadow on superview) */
    _button.layer.masksToBounds = NO;
    _button.layer.shadowColor   = [UIColor blackColor].CGColor;
    _button.layer.shadowOffset  = CGSizeMake(0, 3);
    _button.layer.shadowRadius  = 6.0;
    _button.layer.shadowOpacity = 0.45;

    /* Gestures */
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(onPan:)];
    [_button addGestureRecognizer:pan];

    [_button addTarget:self
                action:@selector(onTap:)
      forControlEvents:UIControlEventTouchUpInside];

    [window addSubview:_button];
    NSLog(@"[FloatingMenu] Button added to window");
}

- (void)onPan:(UIPanGestureRecognizer *)gr {
    UIView *v = gr.view;
    UIView *parent = v.superview;
    if (!parent) return;

    if (gr.state == UIGestureRecognizerStateBegan) {
        _dragStart   = [gr locationInView:parent];
        _buttonStart = v.center;
        _dragged     = NO;
    }

    CGPoint cur = [gr locationInView:parent];
    CGFloat dx  = cur.x - _dragStart.x;
    CGFloat dy  = cur.y - _dragStart.y;

    if (fabs(dx) > 3 || fabs(dy) > 3) _dragged = YES;

    if (_dragged) {
        CGFloat hw = v.bounds.size.width  / 2.0;
        CGFloat hh = v.bounds.size.height / 2.0;
        CGSize  sz = parent.bounds.size;

        CGFloat nx = MAX(hw, MIN(_buttonStart.x + dx, sz.width  - hw));
        CGFloat ny = MAX(hh, MIN(_buttonStart.y + dy, sz.height - hh));
        v.center = CGPointMake(nx, ny);
    }

    if (gr.state == UIGestureRecognizerStateEnded ||
        gr.state == UIGestureRecognizerStateCancelled) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(0.05 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            self->_dragged = NO;
        });
    }
}

- (void)onTap:(UIButton *)sender {
    if (_dragged) return;
    NSLog(@"[FloatingMenu] Menu button tapped");
}

@end

/* ── Library constructor ────────────────────────────────────────────────── */

static FloatingMenuButton *gMenuButton = nil;

__attribute__((constructor))
static void FloatingMenuInit(void) {
    NSLog(@"[FloatingMenu] Library loaded");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{

        UIWindow *win = nil;

        /* iOS 13+ — find the active foreground window */
        if (@available(iOS 13, *)) {
            for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive &&
                    [scene isKindOfClass:[UIWindowScene class]]) {
                    for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                        if (w.isKeyWindow) { win = w; break; }
                    }
                }
                if (win) break;
            }
        }

        /* Fallback */
        if (!win) win = UIApplication.sharedApplication.keyWindow;

        if (!win) {
            NSLog(@"[FloatingMenu] No key window found — aborting");
            return;
        }

        gMenuButton = [[FloatingMenuButton alloc] init];
        [gMenuButton attachToWindow:win];
    });
}
