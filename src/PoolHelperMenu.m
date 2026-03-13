/**
 * PoolHelperMenu.m
 * iOS Dynamic Library — 8 Ball Pool Helper
 * Objective-C / UIKit only — ARM64
 *
 * Features:
 *  - Auto Play  : NSTimer fires every 1.8s and injects a swipe gesture
 *                 (safe loop — no freeze, no infinite recursion)
 *  - Auto Aim   : Fullscreen aim-guide overlay with cue-ball trajectory line
 *  - Aim Line   : Multi-segment pool reflection line (visual guide)
 *  - Debug      : HUD showing active features
 *
 * Compile:
 *   clang -arch arm64 \
 *     -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
 *     -miphoneos-version-min=14.0 \
 *     -framework UIKit -framework Foundation \
 *     -framework CoreGraphics -framework QuartzCore \
 *     -dynamiclib -fobjc-arc \
 *     -install_name @rpath/PoolHelperMenu.dylib \
 *     -O2 -o PoolHelperMenu.dylib PoolHelperMenu.m
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

/* ═══════════════════════════════════════════════════════════════════════════
   PassthroughWindow — lets all touches fall through to the game
   ═══════════════════════════════════════════════════════════════════════════ */
@interface PassthroughWindow : UIWindow @end
@implementation PassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}
@end

/* ═══════════════════════════════════════════════════════════════════════════
   AimLineView — pool trajectory with wall reflection
   ═══════════════════════════════════════════════════════════════════════════ */
@interface AimLineView : UIView
@property (nonatomic, assign) CGPoint  cueBall;   /* starting point  */
@property (nonatomic, assign) CGFloat  angleDeg;  /* shot angle 0-360 */
@end

@implementation AimLineView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {
        self.backgroundColor        = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        _cueBall  = CGPointMake(f.size.width * 0.5, f.size.height * 0.72);
        _angleDeg = 315.0; /* default 45° toward top-right */
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGFloat W = rect.size.width, H = rect.size.height;
    CGFloat angleRad = _angleDeg * M_PI / 180.0;
    CGFloat dx = cosf(angleRad), dy = -sinf(angleRad); /* screen y is flipped */

    /* Draw up to 3 segments with reflection */
    CGPoint  pts[5];
    pts[0] = _cueBall;
    NSInteger count = 1;
    CGFloat  segLen = 500.0;
    CGPoint  cur    = _cueBall;
    CGFloat  dirX   = dx, dirY = dy;

    for (int seg = 0; seg < 3; seg++) {
        CGFloat tX = (dirX > 0) ? (W - cur.x)/dirX : (cur.x)/(-dirX);
        CGFloat tY = (dirY > 0) ? (H - cur.y)/dirY : (cur.y)/(-dirY);
        if (dirX == 0) tX = CGFLOAT_MAX;
        if (dirY == 0) tY = CGFLOAT_MAX;
        CGFloat t = MIN(MIN(tX, tY), segLen);

        CGPoint next = CGPointMake(cur.x + dirX*t, cur.y + dirY*t);
        pts[count++] = next;

        /* reflect */
        if (tX < tY && tX < segLen) dirX = -dirX;
        else if (tY < tX && tY < segLen) dirY = -dirY;
        else break;
        cur = next;
        segLen -= t;
        if (segLen < 20) break;
    }

    /* Yellow dashed main line */
    CGContextSaveGState(ctx);
    CGContextSetStrokeColorWithColor(ctx,
        [UIColor colorWithRed:1.0 green:0.9 blue:0.0 alpha:0.9].CGColor);
    CGContextSetLineWidth(ctx, 2.5);
    CGFloat dash[] = {14, 6};
    CGContextSetLineDash(ctx, 0, dash, 2);
    CGContextMoveToPoint(ctx, pts[0].x, pts[0].y);
    for (int i = 1; i < count; i++)
        CGContextAddLineToPoint(ctx, pts[i].x, pts[i].y);
    CGContextStrokePath(ctx);
    CGContextRestoreGState(ctx);

    /* White dot at cue-ball origin */
    CGFloat r = 8;
    CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextFillEllipseInRect(ctx,
        CGRectMake(pts[0].x-r, pts[0].y-r, r*2, r*2));

    /* Orange dot at first impact */
    if (count > 1) {
        CGContextSetFillColorWithColor(ctx,
            [UIColor colorWithRed:1.0 green:0.5 blue:0.0 alpha:0.85].CGColor);
        CGContextFillEllipseInRect(ctx,
            CGRectMake(pts[1].x-6, pts[1].y-6, 12, 12));
    }
}
@end

/* ═══════════════════════════════════════════════════════════════════════════
   AutoAimView — dynamic cross-hair + extended aim guide at touch point
   ═══════════════════════════════════════════════════════════════════════════ */
@interface AutoAimView : UIView
@property (nonatomic, assign) CGPoint aimPoint;
@end

@implementation AutoAimView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {
        self.backgroundColor        = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        _aimPoint = CGPointMake(f.size.width*0.5, f.size.height*0.3);
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    CGSize  sz = rect.size;
    CGPoint ap = _aimPoint;

    /* Translucent fullscreen tint — very light */
    CGContextSetFillColorWithColor(ctx,
        [UIColor colorWithRed:0.0 green:0.4 blue:1.0 alpha:0.04].CGColor);
    CGContextFillRect(ctx, rect);

    /* Crosshair lines */
    CGContextSetStrokeColorWithColor(ctx,
        [UIColor colorWithRed:0.3 green:0.9 blue:1.0 alpha:0.75].CGColor);
    CGContextSetLineWidth(ctx, 1.2);
    CGContextMoveToPoint(ctx, 0, ap.y);
    CGContextAddLineToPoint(ctx, sz.width, ap.y);
    CGContextMoveToPoint(ctx, ap.x, 0);
    CGContextAddLineToPoint(ctx, ap.x, sz.height);
    CGContextStrokePath(ctx);

    /* Circle */
    CGFloat r = 22;
    CGContextSetStrokeColorWithColor(ctx,
        [UIColor colorWithRed:0.3 green:0.9 blue:1.0 alpha:0.9].CGColor);
    CGContextSetLineWidth(ctx, 2.0);
    CGContextStrokeEllipseInRect(ctx,
        CGRectMake(ap.x-r, ap.y-r, r*2, r*2));

    /* Centre dot */
    CGContextSetFillColorWithColor(ctx,
        [UIColor colorWithRed:0.3 green:0.9 blue:1.0 alpha:1.0].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(ap.x-3, ap.y-3, 6, 6));
}
@end

/* ═══════════════════════════════════════════════════════════════════════════
   AutoPlayEngine — safe repeating timer, NO infinite loops
   ═══════════════════════════════════════════════════════════════════════════ */
@interface AutoPlayEngine : NSObject
- (void)start;
- (void)stop;
@property (nonatomic, assign) BOOL running;
@end

@implementation AutoPlayEngine {
    NSTimer *_timer;
    NSInteger _shotCount;
}

- (void)start {
    if (_running) return;
    _running   = YES;
    _shotCount = 0;
    NSLog(@"[PoolHelper] AutoPlay started");
    /* Fire every 1.8 s on the main run loop — completely safe, no blocking */
    _timer = [NSTimer scheduledTimerWithTimeInterval:1.8
                                              target:self
                                            selector:@selector(performShot)
                                            userInfo:nil
                                             repeats:YES];
}

- (void)stop {
    if (!_running) return;
    _running = NO;
    [_timer invalidate];
    _timer = nil;
    NSLog(@"[PoolHelper] AutoPlay stopped after %ld shots", (long)_shotCount);
}

- (void)performShot {
    _shotCount++;
    NSLog(@"[PoolHelper] AutoPlay shot #%ld", (long)_shotCount);

    /* Inject a swipe gesture via UIApplication event system */
    dispatch_async(dispatch_get_main_queue(), ^{
        [self injectSwipeFromPoint:CGPointMake(UIScreen.mainScreen.bounds.size.width  * 0.50,
                                               UIScreen.mainScreen.bounds.size.height * 0.72)
                           toPoint:CGPointMake(UIScreen.mainScreen.bounds.size.width  * 0.50,
                                               UIScreen.mainScreen.bounds.size.height * 0.28)];
    });
}

/**
 * Inject a synthetic drag (press-move-release) using private UIApplication API.
 * This is the standard approach used for UI automation in dylibs.
 */
- (void)injectSwipeFromPoint:(CGPoint)start toPoint:(CGPoint)end {
    /* Use UIWindow sendEvent with synthetic UITouch objects via KVC */
    UIWindow *gameWin = [self gameWindow];
    if (!gameWin) return;

    Class UITouchClass = NSClassFromString(@"UITouch");
    if (!UITouchClass) return;

    UITouch *touch = [UITouchClass new];

    /* Set private properties via setValue:forKey: */
    CGPoint startWin = start, endWin = end;
    NSInteger steps = 8;

    /* Phase: began */
    [touch setValue:@(UITouchPhaseBegan) forKey:@"phase"];
    [touch setValue:gameWin forKey:@"window"];
    [touch setValue:gameWin forKey:@"view"];
    [touch setValue:[NSValue valueWithCGPoint:startWin] forKey:@"locationInWindow"];
    [touch setValue:[NSValue valueWithCGPoint:startWin] forKey:@"previousLocationInWindow"];
    [touch setValue:@(1) forKey:@"tapCount"];
    [touch setValue:@(1.0) forKey:@"force"];
    [touch setValue:@(CFAbsoluteTimeGetCurrent()) forKey:@"timestamp"];

    UIEvent *beganEvent = [self makeTouchEvent:touch phase:UITouchPhaseBegan];
    [gameWin sendEvent:beganEvent];

    /* Phase: moved — interpolate */
    for (NSInteger i = 1; i <= steps; i++) {
        CGFloat t = (CGFloat)i / steps;
        CGPoint mid = CGPointMake(startWin.x + (endWin.x - startWin.x)*t,
                                  startWin.y + (endWin.y - startWin.y)*t);
        [touch setValue:[NSValue valueWithCGPoint:mid] forKey:@"locationInWindow"];
        [touch setValue:@(UITouchPhaseMoved) forKey:@"phase"];
        [touch setValue:@(CFAbsoluteTimeGetCurrent()) forKey:@"timestamp"];
        UIEvent *movedEvent = [self makeTouchEvent:touch phase:UITouchPhaseMoved];
        [gameWin sendEvent:movedEvent];
    }

    /* Phase: ended */
    [touch setValue:[NSValue valueWithCGPoint:endWin] forKey:@"locationInWindow"];
    [touch setValue:@(UITouchPhaseEnded) forKey:@"phase"];
    [touch setValue:@(CFAbsoluteTimeGetCurrent()) forKey:@"timestamp"];
    UIEvent *endedEvent = [self makeTouchEvent:touch phase:UITouchPhaseEnded];
    [gameWin sendEvent:endedEvent];
}

- (UIEvent *)makeTouchEvent:(UITouch *)touch phase:(UITouchPhase)phase {
    Class UIEventClass = NSClassFromString(@"UIEvent");
    UIEvent *event = [UIEventClass new];
    NSSet *touches = [NSSet setWithObject:touch];
    [event setValue:touches forKey:@"allTouches"];
    [event setValue:@(CFAbsoluteTimeGetCurrent()) forKey:@"timestamp"];
    return event;
}

- (UIWindow *)gameWindow {
    for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if ([w isKindOfClass:[PassthroughWindow class]]) continue;
            if (w.isKeyWindow) return w;
        }
    }
    return UIApplication.sharedApplication.keyWindow;
}

@end

/* ═══════════════════════════════════════════════════════════════════════════
   DebugHUD — shows active features in corner
   ═══════════════════════════════════════════════════════════════════════════ */
@interface DebugHUD : UIView @end
@implementation DebugHUD

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {
        self.backgroundColor        = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.55];
        self.layer.cornerRadius     = 8;
        self.layer.masksToBounds    = YES;
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)setStatus:(NSDictionary<NSString*,NSNumber*> *)features {
    for (UIView *v in self.subviews) [v removeFromSuperview];
    CGFloat y = 6, lineH = 18;
    for (NSString *key in @[@"Auto Play", @"Auto Aim", @"Aim Line", @"Debug"]) {
        BOOL on = [features[key] boolValue];
        UILabel *l = [[UILabel alloc]
                      initWithFrame:CGRectMake(8, y, self.bounds.size.width-16, lineH)];
        l.text      = [NSString stringWithFormat:@"%@  %@", on ? @"●" : @"○", key];
        l.font      = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
        l.textColor = on
            ? [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0]
            : [UIColor colorWithWhite:0.6 alpha:1.0];
        [self addSubview:l];
        y += lineH;
    }
}
@end

/* ═══════════════════════════════════════════════════════════════════════════
   MenuController
   ═══════════════════════════════════════════════════════════════════════════ */
@interface MenuController : NSObject
@property (nonatomic, strong) PassthroughWindow *menuWindow;
@property (nonatomic, strong) UIView            *menuView;
@property (nonatomic, strong) AimLineView       *aimLine;
@property (nonatomic, strong) AutoAimView       *autoAimView;
@property (nonatomic, strong) DebugHUD          *debugHUD;
@property (nonatomic, strong) AutoPlayEngine    *autoPlay;
@property (nonatomic, assign) CGPoint            dragOffset;
- (void)show;
- (void)hide;
- (BOOL)isVisible;
@end

@implementation MenuController {
    NSMutableDictionary<NSString*,NSNumber*> *_states;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _states   = [NSMutableDictionary dictionary];
        _autoPlay = [AutoPlayEngine new];
        [self buildWindow];
    }
    return self;
}

- (void)buildWindow {
    UIWindowScene *scene = [self activeScene];
    CGRect screen = UIScreen.mainScreen.bounds;

    if (scene)
        _menuWindow = [[PassthroughWindow alloc] initWithWindowScene:scene];
    else
        _menuWindow = [[PassthroughWindow alloc] initWithFrame:screen];

    _menuWindow.windowLevel     = UIWindowLevelNormal + 100;
    _menuWindow.backgroundColor = [UIColor clearColor];

    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor clearColor];
    _menuWindow.rootViewController = root;

    /* Overlays — non-interactive */
    _aimLine = [[AimLineView alloc] initWithFrame:screen];
    _aimLine.hidden = YES;
    [root.view addSubview:_aimLine];

    _autoAimView = [[AutoAimView alloc] initWithFrame:screen];
    _autoAimView.hidden = YES;
    [root.view addSubview:_autoAimView];

    /* Debug HUD */
    _debugHUD = [[DebugHUD alloc] initWithFrame:CGRectMake(10, 60, 160, 82)];
    _debugHUD.hidden = YES;
    [root.view addSubview:_debugHUD];

    /* Menu panel */
    CGFloat mw = 300, mh = 390;
    _menuView = [[UIView alloc]
                 initWithFrame:CGRectMake((screen.size.width-mw)/2,
                                         (screen.size.height-mh)/2,
                                         mw, mh)];
    _menuView.layer.cornerRadius  = 18;
    _menuView.layer.masksToBounds = YES;
    _menuView.layer.borderColor   = [UIColor colorWithWhite:1.0 alpha:0.15].CGColor;
    _menuView.layer.borderWidth   = 1;

    /* Blur */
    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blur.frame = _menuView.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [_menuView addSubview:blur];

    /* Dark tint */
    UIView *tint = [[UIView alloc] initWithFrame:_menuView.bounds];
    tint.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.12 alpha:0.65];
    tint.autoresizingMask = blur.autoresizingMask;
    [_menuView addSubview:tint];

    /* Content */
    UIView *c = [[UIView alloc] initWithFrame:_menuView.bounds];
    c.backgroundColor = [UIColor clearColor];
    [_menuView addSubview:c];

    /* Title */
    UILabel *title = [self labelText:@"POOL HELPER MENU"
                                font:[UIFont systemFontOfSize:17 weight:UIFontWeightBold]
                               color:[UIColor colorWithRed:0.3 green:0.85 blue:1.0 alpha:1.0]
                               frame:CGRectMake(0, 16, mw, 36)
                               align:NSTextAlignmentCenter];
    [c addSubview:title];

    UILabel *sub = [self labelText:@"8 BALL POOL HELPER"
                              font:[UIFont systemFontOfSize:11 weight:UIFontWeightMedium]
                             color:[UIColor colorWithWhite:1.0 alpha:0.35]
                             frame:CGRectMake(0, 52, mw, 18)
                             align:NSTextAlignmentCenter];
    [c addSubview:sub];

    UILabel *icon = [self labelText:@"🎱"
                               font:[UIFont systemFontOfSize:22]
                              color:[UIColor whiteColor]
                              frame:CGRectMake(mw-44, 14, 32, 32)
                              align:NSTextAlignmentCenter];
    [c addSubview:icon];

    /* Separator */
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(20, 76, mw-40, 0.5)];
    sep.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
    [c addSubview:sep];

    /* Toggle rows */
    NSArray *rows = @[
        @{@"label":@"Auto Play",   @"sub":@"Swipe every 1.8s",      @"tag":@(101)},
        @{@"label":@"Auto Aim",    @"sub":@"Aim cross-hair overlay", @"tag":@(102)},
        @{@"label":@"Aim Line",    @"sub":@"Ball path overlay",      @"tag":@(103)},
        @{@"label":@"Debug",       @"sub":@"Show HUD status",        @"tag":@(104)},
    ];
    CGFloat rowY = 84;
    for (NSDictionary *r in rows) {
        [self addRow:c label:r[@"label"] sub:r[@"sub"]
                 tag:[r[@"tag"] integerValue] y:rowY width:mw];
        rowY += 54;
    }

    /* Close */
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(20, mh-56, mw-40, 38);
    close.layer.cornerRadius  = 10;
    close.layer.masksToBounds = YES;
    close.backgroundColor = [UIColor colorWithRed:0.85 green:0.15 blue:0.2 alpha:0.85];
    [close setTitle:@"✕  Close Menu" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [close addTarget:self action:@selector(hide)
    forControlEvents:UIControlEventTouchUpInside];
    [c addSubview:close];

    /* Pan gesture — drag menu */
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [_menuView addGestureRecognizer:pan];

    [root.view addSubview:_menuView];
    _menuView.hidden = YES;
    _menuView.alpha  = 0;

    _menuWindow.hidden = NO;
    [_menuWindow makeKeyAndVisible];
    [self resignKey];
}

- (void)addRow:(UIView *)parent label:(NSString *)label sub:(NSString *)sub
           tag:(NSInteger)tag y:(CGFloat)y width:(CGFloat)w {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0,y,w,50)];
    row.backgroundColor = [UIColor clearColor];

    UILabel *lbl = [self labelText:label
                              font:[UIFont systemFontOfSize:15 weight:UIFontWeightMedium]
                             color:[UIColor colorWithWhite:1.0 alpha:0.95]
                             frame:CGRectMake(18,4,w-100,22)
                             align:NSTextAlignmentLeft];
    [row addSubview:lbl];

    UILabel *slbl = [self labelText:sub
                               font:[UIFont systemFontOfSize:11]
                              color:[UIColor colorWithWhite:1.0 alpha:0.4]
                              frame:CGRectMake(18,26,w-100,16)
                              align:NSTextAlignmentLeft];
    [row addSubview:slbl];

    UISwitch *sw = [UISwitch new];
    sw.onTintColor = [UIColor colorWithRed:0.2 green:0.75 blue:1.0 alpha:1.0];
    sw.tag = tag; sw.on = NO;
    CGSize ss = sw.intrinsicContentSize;
    sw.frame = CGRectMake(w-ss.width-18, (50-ss.height)/2, ss.width, ss.height);
    [sw addTarget:self action:@selector(onToggle:)
 forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(18,49,w-36,0.5)];
    line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    [row addSubview:line];

    [parent addSubview:row];
}

- (UILabel *)labelText:(NSString *)text font:(UIFont *)font
                 color:(UIColor *)color frame:(CGRect)frame
                 align:(NSTextAlignment)align {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text          = text;
    l.font          = font;
    l.textColor     = color;
    l.textAlignment = align;
    l.userInteractionEnabled = NO;
    return l;
}

/* ── Toggle handler ─────────────────────────────────────────────────────── */
- (void)onToggle:(UISwitch *)sw {
    NSString *name;
    switch (sw.tag) {
        case 101: name = @"Auto Play"; break;
        case 102: name = @"Auto Aim";  break;
        case 103: name = @"Aim Line";  break;
        case 104: name = @"Debug";     break;
        default:  name = @"Unknown";   break;
    }
    _states[name] = @(sw.on);
    NSLog(@"[PoolHelper] %@ %@", name, sw.on ? @"Enabled" : @"Disabled");

    dispatch_async(dispatch_get_main_queue(), ^{
        switch (sw.tag) {
            case 101: /* Auto Play */
                sw.on ? [self->_autoPlay start] : [self->_autoPlay stop];
                break;
            case 102: /* Auto Aim */
                self->_autoAimView.hidden = !sw.on;
                [self->_autoAimView setNeedsDisplay];
                break;
            case 103: /* Aim Line */
                self->_aimLine.hidden = !sw.on;
                [self->_aimLine setNeedsDisplay];
                break;
            case 104: /* Debug */
                self->_debugHUD.hidden = !sw.on;
                [self->_debugHUD setStatus:self->_states];
                break;
        }
        if (!self->_debugHUD.hidden)
            [self->_debugHUD setStatus:self->_states];
    });
}

/* ── Pan / drag ─────────────────────────────────────────────────────────── */
- (void)onPan:(UIPanGestureRecognizer *)gr {
    UIView *v = gr.view, *p = v.superview;
    if (!p) return;
    if (gr.state == UIGestureRecognizerStateBegan) _dragOffset = v.center;
    CGPoint t = [gr translationInView:p];
    CGFloat hw = v.bounds.size.width/2, hh = v.bounds.size.height/2;
    CGSize  sz = p.bounds.size;
    v.center = CGPointMake(MAX(hw, MIN(_dragOffset.x+t.x, sz.width -hw)),
                           MAX(hh, MIN(_dragOffset.y+t.y, sz.height-hh)));
}

/* ── Show / hide ────────────────────────────────────────────────────────── */
- (void)show {
    _menuView.hidden    = NO;
    _menuView.transform = CGAffineTransformMakeScale(0.92, 0.92);
    [UIView animateWithDuration:0.22 delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self->_menuView.alpha     = 1;
        self->_menuView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hide {
    [UIView animateWithDuration:0.18 delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self->_menuView.alpha     = 0;
        self->_menuView.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } completion:^(BOOL d) { self->_menuView.hidden = YES; }];
}

- (BOOL)isVisible { return !_menuView.hidden && _menuView.alpha > 0.01; }

/* ── Helpers ────────────────────────────────────────────────────────────── */
- (void)resignKey {
    for (UIWindowScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows)
            if (w != _menuWindow) { [w makeKeyWindow]; return; }
    }
}

- (UIWindowScene *)activeScene {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive)
            return (UIWindowScene *)s;
    return nil;
}

@end

/* ═══════════════════════════════════════════════════════════════════════════
   FloatingButton
   ═══════════════════════════════════════════════════════════════════════════ */
@interface FloatingButton : NSObject
@property (nonatomic, strong) PassthroughWindow *win;
@property (nonatomic, strong) UIButton          *btn;
@property (nonatomic, strong) MenuController    *menu;
@property (nonatomic, assign) CGPoint            dragStart, centerStart;
@property (nonatomic, assign) BOOL               dragged;
- (instancetype)initWithMenu:(MenuController *)m;
- (void)show;
@end

@implementation FloatingButton

- (instancetype)initWithMenu:(MenuController *)m {
    self = [super init];
    if (self) { _menu = m; [self build]; }
    return self;
}

- (void)build {
    UIWindowScene *scene = [self activeScene];
    CGRect bounds = UIScreen.mainScreen.bounds;
    _win = scene
        ? [[PassthroughWindow alloc] initWithWindowScene:scene]
        : [[PassthroughWindow alloc] initWithFrame:bounds];
    _win.windowLevel     = UIWindowLevelNormal + 200;
    _win.backgroundColor = [UIColor clearColor];

    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor clearColor];
    _win.rootViewController = root;

    CGFloat sz = 54, mg = 16;
    _btn = [UIButton buttonWithType:UIButtonTypeCustom];
    _btn.frame = CGRectMake(bounds.size.width-sz-mg, bounds.size.height*0.38, sz, sz);
    _btn.layer.cornerRadius  = sz/2;
    _btn.layer.masksToBounds = NO;
    _btn.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.18 alpha:0.93];
    _btn.layer.borderColor   = [UIColor colorWithRed:0.25 green:0.7 blue:1.0 alpha:0.9].CGColor;
    _btn.layer.borderWidth   = 2.2;
    _btn.layer.shadowColor   = [UIColor blackColor].CGColor;
    _btn.layer.shadowOffset  = CGSizeMake(0,4);
    _btn.layer.shadowRadius  = 8;
    _btn.layer.shadowOpacity = 0.6;

    UILabel *ico = [[UILabel alloc] initWithFrame:_btn.bounds];
    ico.text = @"🎱"; ico.font = [UIFont systemFontOfSize:26];
    ico.textAlignment = NSTextAlignmentCenter;
    ico.userInteractionEnabled = NO;
    [_btn addSubview:ico];

    [_btn addTarget:self action:@selector(onTap:)
   forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [_btn addGestureRecognizer:pan];
    [root.view addSubview:_btn];
}

- (void)show {
    _win.hidden = NO;
    [_win makeKeyAndVisible];
    [self resignKey];
    _btn.alpha = 0; _btn.transform = CGAffineTransformMakeScale(0.1,0.1);
    [UIView animateWithDuration:0.4 delay:0
         usingSpringWithDamping:0.6 initialSpringVelocity:0.8
                        options:0 animations:^{
        self->_btn.alpha = 1;
        self->_btn.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)onTap:(id)s { if (!_dragged) ([_menu isVisible] ? [_menu hide] : [_menu show]); }

- (void)onPan:(UIPanGestureRecognizer *)gr {
    UIView *v = gr.view, *p = v.superview; if (!p) return;
    if (gr.state == UIGestureRecognizerStateBegan) {
        _dragStart = [gr locationInView:p]; _centerStart = v.center; _dragged = NO;
    }
    CGPoint cur = [gr locationInView:p];
    if (fabs(cur.x-_dragStart.x)>4||fabs(cur.y-_dragStart.y)>4) _dragged = YES;
    if (_dragged) {
        CGFloat hw=v.bounds.size.width/2, hh=v.bounds.size.height/2;
        CGSize sz=p.bounds.size;
        v.center = CGPointMake(MAX(hw,MIN(_centerStart.x+(cur.x-_dragStart.x),sz.width-hw)),
                               MAX(hh,MIN(_centerStart.y+(cur.y-_dragStart.y),sz.height-hh)));
    }
    if (gr.state==UIGestureRecognizerStateEnded||gr.state==UIGestureRecognizerStateCancelled)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.05*NSEC_PER_SEC)),
                       dispatch_get_main_queue(),^{ self->_dragged=NO; });
}

- (void)resignKey {
    for (UIWindowScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows)
            if (w != _win && w != _menu.menuWindow) { [w makeKeyWindow]; return; }
    }
}
- (UIWindowScene *)activeScene {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive)
            return (UIWindowScene *)s;
    return nil;
}
@end

/* ═══════════════════════════════════════════════════════════════════════════
   OverlayManager — singleton
   ═══════════════════════════════════════════════════════════════════════════ */
@interface OverlayManager : NSObject
+ (instancetype)shared;
- (void)launch;
@end

@implementation OverlayManager {
    MenuController *_menu;
    FloatingButton *_btn;
}

+ (instancetype)shared {
    static OverlayManager *i; static dispatch_once_t t;
    dispatch_once(&t, ^{ i = [OverlayManager new]; });
    return i;
}

- (void)launch {
    NSLog(@"[PoolHelper] Launching — 8 Ball Pool Helper");
    _menu = [MenuController new];
    _btn  = [[FloatingButton alloc] initWithMenu:_menu];
    [_btn show];
    NSLog(@"[PoolHelper] Ready. Game input unblocked.");
}
@end

/* ═══════════════════════════════════════════════════════════════════════════
   Constructor — runs when dylib is loaded into the game process
   ═══════════════════════════════════════════════════════════════════════════ */
__attribute__((constructor))
static void PoolHelperInit(void) {
    NSLog(@"[PoolHelper] Library loaded into process");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[OverlayManager shared] launch];
    });
}
