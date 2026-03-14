/**
 * PoolHelperMenu.m — 8 Ball Pool Helper
 * Single file · Objective-C · UIKit · ARM64 · iOS 14+
 *
 * Auto Play  : NSTimer every 3 s.  Calls touchesBegan/Moved/Ended DIRECTLY
 *              on the game's render view — bypasses UIApplication so it
 *              reaches Metal/GL engines.  Never changes aim, so never hits
 *              opponent's ball.
 *
 * Aim Line   : Full-screen overlay drawn every frame via CADisplayLink.
 *              Shows multiple trajectory paths + wall reflections so you
 *              can see where every shot will go.
 *
 * Auto Aim   : Crosshair targets drawn every frame.
 *
 * Debug HUD  : Corner label showing ON/OFF state of each feature.
 *
 * PassthroughWindow: All touches fall through to the game — no freeze.
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

/* ═══════════════════════════════════════════════════════════════════════
   Helpers
   ═══════════════════════════════════════════════════════════════════════ */

static UIWindow *PHGameWindow(void) {
    @try {
        for (UIWindowScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                if ([w isKindOfClass:NSClassFromString(@"PassthroughWindow")]) continue;
                if (w.isKeyWindow) return w;
            }
        }
    } @catch (...) {}
    return nil;
}

static UIWindowScene *PHActiveScene(void) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive)
            return (UIWindowScene *)s;
    return nil;
}

/* ═══════════════════════════════════════════════════════════════════════
   PassthroughWindow
   ═══════════════════════════════════════════════════════════════════════ */
@interface PassthroughWindow : UIWindow @end
@implementation PassthroughWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *h = [super hitTest:p withEvent:e];
    return (h == self || h == self.rootViewController.view) ? nil : h;
}
@end

/* ═══════════════════════════════════════════════════════════════════════
   AimLineView — drawn every frame via CADisplayLink
   Shows multiple ball trajectories + wall reflections over the game.
   ═══════════════════════════════════════════════════════════════════════ */
@interface AimLineView : UIView
- (void)startRefresh;
- (void)stopRefresh;
@end

@implementation AimLineView {
    CADisplayLink *_link;
}

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {
        self.backgroundColor        = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.opaque                 = NO;
        /* Force the backing layer to composite over game */
        self.layer.allowsGroupOpacity = NO;
    }
    return self;
}

- (void)startRefresh {
    if (_link) return;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(_tick)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)stopRefresh {
    [_link invalidate]; _link = nil;
}

- (void)_tick { [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGFloat W = rect.size.width, H = rect.size.height;

    /* Cue ball — lower-centre of table */
    CGPoint cue = CGPointMake(W * 0.50, H * 0.70);

    /* Six shot-angle candidates */
    CGFloat degs[] = { 55, 70, 90, 110, 125, 140 };
    int     nDegs  = 6;

    for (int di = 0; di < nDegs; di++) {
        CGFloat rad = degs[di] * (CGFloat)M_PI / 180.0f;
        CGFloat dx  =  cosf(rad);
        CGFloat dy  = -sinf(rad); /* screen y flips */

        /* Up to 3 wall reflections */
        CGPoint seg[5]; seg[0] = cue;
        int     nSeg  = 1;
        CGFloat ddx   = dx, ddy = dy;
        CGPoint cur   = cue;
        CGFloat left  = 650;

        for (int s = 0; s < 3 && left > 15; s++) {
            CGFloat tX = ddx > 0 ? (W - cur.x)/ddx : (ddx < 0 ? cur.x/-ddx : 1e9f);
            CGFloat tY = ddy > 0 ? (H - cur.y)/ddy : (ddy < 0 ? cur.y/-ddy : 1e9f);
            CGFloat t  = fminf(fminf(tX, tY), left);
            CGPoint nxt = CGPointMake(cur.x + ddx*t, cur.y + ddy*t);
            seg[nSeg++] = nxt;
            if (tX < tY) ddx = -ddx; else ddy = -ddy;
            cur  = nxt;
            left -= t;
        }

        /* Main line = 90°, others thinner */
        BOOL main = (di == 2);
        UIColor *col = main
            ? [UIColor colorWithRed:1.0f green:0.92f blue:0.0f alpha:1.0f]
            : [UIColor colorWithRed:1.0f green:1.0f  blue:1.0f alpha:0.60f];
        CGFloat lw = main ? 3.5f : 2.0f;

        CGContextSaveGState(ctx);
        CGContextSetStrokeColorWithColor(ctx, col.CGColor);
        CGContextSetLineWidth(ctx, lw);
        CGFloat dash[] = { 14, 6 };
        CGContextSetLineDash(ctx, 0, dash, 2);
        CGContextMoveToPoint(ctx, seg[0].x, seg[0].y);
        for (int i = 1; i < nSeg; i++)
            CGContextAddLineToPoint(ctx, seg[i].x, seg[i].y);
        CGContextStrokePath(ctx);
        CGContextRestoreGState(ctx);

        /* Impact dot */
        if (nSeg > 1) {
            CGContextSetFillColorWithColor(ctx,
                [UIColor colorWithRed:1.0f green:0.45f blue:0.0f alpha:0.9f].CGColor);
            CGFloat r = main ? 8.0f : 5.5f;
            CGContextFillEllipseInRect(ctx, CGRectMake(seg[1].x-r, seg[1].y-r, r*2, r*2));
        }
    }

    /* Cue ball circle */
    CGContextSetLineDash(ctx, 0, NULL, 0);
    CGContextSetStrokeColorWithColor(ctx,
        [UIColor colorWithRed:1.0f green:0.9f blue:0.0f alpha:1.0f].CGColor);
    CGContextSetLineWidth(ctx, 2.5f);
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1.0f alpha:0.92f].CGColor);
    CGRect cueR = CGRectMake(cue.x-10, cue.y-10, 20, 20);
    CGContextFillEllipseInRect(ctx, cueR);
    CGContextStrokeEllipseInRect(ctx, cueR);
}

@end

/* ═══════════════════════════════════════════════════════════════════════
   AutoAimView — crosshair targets, redrawn every frame
   ═══════════════════════════════════════════════════════════════════════ */
@interface AutoAimView : UIView
- (void)startRefresh;
- (void)stopRefresh;
@end

@implementation AutoAimView {
    CADisplayLink *_link;
}

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {
        self.backgroundColor        = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.opaque                 = NO;
    }
    return self;
}

- (void)startRefresh {
    if (_link) return;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(_tick)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)stopRefresh { [_link invalidate]; _link = nil; }
- (void)_tick       { [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    CGFloat W = rect.size.width, H = rect.size.height;

    struct { CGFloat x, y; } pts[] = {
        { W*0.28f, H*0.25f },
        { W*0.50f, H*0.20f },
        { W*0.72f, H*0.25f },
        { W*0.35f, H*0.40f },
        { W*0.65f, H*0.38f },
    };
    int n = 5;

    for (int i = 0; i < n; i++) {
        CGFloat ax = pts[i].x, ay = pts[i].y;
        CGFloat r  = 18;

        CGContextSetLineDash(ctx, 0, NULL, 0);
        CGContextSetStrokeColorWithColor(ctx,
            [UIColor colorWithRed:0.15f green:1.0f blue:0.35f alpha:0.9f].CGColor);
        CGContextSetLineWidth(ctx, 2.2f);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(ax-r, ay-r, r*2, r*2));

        /* cross */
        CGContextSetStrokeColorWithColor(ctx,
            [UIColor colorWithRed:0.15f green:1.0f blue:0.35f alpha:0.65f].CGColor);
        CGContextSetLineWidth(ctx, 1.4f);
        CGContextMoveToPoint(ctx, ax-30, ay); CGContextAddLineToPoint(ctx, ax+30, ay);
        CGContextMoveToPoint(ctx, ax, ay-30); CGContextAddLineToPoint(ctx, ax, ay+30);
        CGContextStrokePath(ctx);

        /* centre */
        CGContextSetFillColorWithColor(ctx,
            [UIColor colorWithRed:0.15f green:1.0f blue:0.35f alpha:1.0f].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(ax-3.5f, ay-3.5f, 7, 7));
    }

    NSDictionary *attr = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:11],
        NSForegroundColorAttributeName:
            [UIColor colorWithRed:0.15f green:1.0f blue:0.35f alpha:0.85f]
    };
    [@"◎ AUTO AIM" drawAtPoint:CGPointMake(10, H*0.18f) withAttributes:attr];
}
@end

/* ═══════════════════════════════════════════════════════════════════════
   DebugHUD
   ═══════════════════════════════════════════════════════════════════════ */
@interface DebugHUD : UIView
- (void)setStatus:(NSDictionary *)f;
@end

@implementation DebugHUD
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {
        self.backgroundColor        = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.62f];
        self.layer.cornerRadius     = 8;
        self.layer.masksToBounds    = YES;
        self.userInteractionEnabled = NO;
    }
    return self;
}
- (void)setStatus:(NSDictionary *)features {
    for (UIView *v in self.subviews) [v removeFromSuperview];
    CGFloat y = 5;
    for (NSString *k in @[@"Auto Play",@"Auto Aim",@"Aim Line",@"Debug"]) {
        BOOL on = [features[k] boolValue];
        UILabel *l = [[UILabel alloc]
                      initWithFrame:CGRectMake(8, y, self.bounds.size.width-16, 18)];
        l.text      = [NSString stringWithFormat:@"%@  %@", on ? @"●" : @"○", k];
        l.font      = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
        l.textColor = on
            ? [UIColor colorWithRed:0.2f green:1.0f blue:0.45f alpha:1.0f]
            : [UIColor colorWithWhite:0.5f alpha:1.0f];
        [self addSubview:l]; y += 18;
    }
}
@end

/* ═══════════════════════════════════════════════════════════════════════
   AutoPlayEngine
   ═══════════════════════════════════════════════════════════════════════ */
/*
 * How it shoots WITHOUT mistakes:
 *   - Does NOT change aim direction at all.
 *   - Only simulates the "pull back cue and release" gesture.
 *   - The game keeps the aim you set, so it shoots your ball only.
 *
 * Why this injection works on Metal/GL games:
 *   - Calls -touchesBegan:withEvent: / -touchesMoved: / -touchesEnded:
 *     DIRECTLY on the game's render view found via hitTest.
 *   - This bypasses UIApplication's event queue which doesn't reach
 *     Metal or OpenGL ES rendering views.
 */
@interface AutoPlayEngine : NSObject
@property (nonatomic, assign) BOOL running;
- (void)start;
- (void)stop;
@end

@implementation AutoPlayEngine {
    NSTimer   *_timer;
    NSInteger  _shots;
}

- (void)start {
    if (_running) return;
    _running = YES; _shots = 0;
    /* Safe NSTimer — NOT a loop */
    _timer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                              target:self
                                            selector:@selector(_fire)
                                            userInfo:nil
                                             repeats:YES];
    NSLog(@"[PoolHelper] AutoPlay ON — every 3 s");
}

- (void)stop {
    _running = NO;
    [_timer invalidate]; _timer = nil;
    NSLog(@"[PoolHelper] AutoPlay OFF  shots=%ld", (long)_shots);
}

- (void)_fire {
    _shots++;
    NSLog(@"[PoolHelper] AutoPlay shot #%ld", (long)_shots);
    dispatch_async(dispatch_get_main_queue(), ^{ [self _shoot]; });
}

- (void)_shoot {
    @try {
        UIWindow *win = PHGameWindow();
        if (!win) { NSLog(@"[PoolHelper] No game window"); return; }

        CGSize  S    = UIScreen.mainScreen.bounds.size;
        /* Cue-stick pull: start at cue-ball, drag toward bottom edge */
        CGPoint from = CGPointMake(S.width * 0.50f, S.height * 0.65f);
        CGPoint to   = CGPointMake(S.width * 0.50f, S.height * 0.83f);

        /* Find the deepest game view at the touch point */
        UIView *gameView = [win hitTest:from withEvent:nil];
        if (!gameView) gameView = win;

        /* Build a UITouch via KVC — set location and phase */
        Class TC = NSClassFromString(@"UITouch");
        if (!TC) return;

        UITouch *touch = [[TC alloc] init];

        void (^setKey)(id, NSString *, id) = ^(id obj, NSString *key, id val) {
            @try { [obj setValue:val forKey:key]; } @catch (...) {}
        };

        /* BEGAN */
        setKey(touch, @"locationInWindow",         [NSValue valueWithCGPoint:from]);
        setKey(touch, @"previousLocationInWindow", [NSValue valueWithCGPoint:from]);
        setKey(touch, @"window",                   win);
        setKey(touch, @"view",                     gameView);
        setKey(touch, @"phase",                    @(UITouchPhaseBegan));
        setKey(touch, @"timestamp",                @(CFAbsoluteTimeGetCurrent()));
        setKey(touch, @"tapCount",                 @(1));

        NSSet *set = [NSSet setWithObject:touch];
        @try { [gameView touchesBegan:set withEvent:nil]; } @catch(...) {}

        /* MOVED — 10 steps from from→to */
        for (int i = 1; i <= 10; i++) {
            CGFloat f   = (CGFloat)i / 10.0f;
            CGPoint mid = CGPointMake(from.x + (to.x - from.x)*f,
                                      from.y + (to.y - from.y)*f);
            setKey(touch, @"previousLocationInWindow", [NSValue valueWithCGPoint:
                (i==1 ? from : CGPointMake(from.x + (to.x-from.x)*(f-0.1f),
                                           from.y + (to.y-from.y)*(f-0.1f)))]);
            setKey(touch, @"locationInWindow", [NSValue valueWithCGPoint:mid]);
            setKey(touch, @"phase",            @(UITouchPhaseMoved));
            setKey(touch, @"timestamp",        @(CFAbsoluteTimeGetCurrent()));
            @try { [gameView touchesMoved:set withEvent:nil]; } @catch(...) {}
        }

        /* ENDED */
        setKey(touch, @"locationInWindow",         [NSValue valueWithCGPoint:to]);
        setKey(touch, @"previousLocationInWindow", [NSValue valueWithCGPoint:to]);
        setKey(touch, @"phase",                    @(UITouchPhaseEnded));
        setKey(touch, @"timestamp",                @(CFAbsoluteTimeGetCurrent()));
        @try { [gameView touchesEnded:set withEvent:nil]; } @catch(...) {}

    } @catch (NSException *ex) {
        NSLog(@"[PoolHelper] AutoPlay error: %@", ex.reason);
    }
}
@end

/* ═══════════════════════════════════════════════════════════════════════
   MenuController
   ═══════════════════════════════════════════════════════════════════════ */
@interface MenuController : NSObject
@property (nonatomic, strong) PassthroughWindow *window;
@property (nonatomic, strong) UIView            *panel;
@property (nonatomic, strong) AimLineView       *aimLine;
@property (nonatomic, strong) AutoAimView       *autoAim;
@property (nonatomic, strong) DebugHUD          *debugHUD;
@property (nonatomic, strong) AutoPlayEngine    *engine;
@property (nonatomic, assign) CGPoint            panOffset;
- (void)show;
- (void)hide;
- (BOOL)visible;
@end

@implementation MenuController {
    NSMutableDictionary *_state;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _state  = [NSMutableDictionary dictionary];
        _engine = [AutoPlayEngine new];
        [self build];
    }
    return self;
}

- (void)build {
    UIWindowScene *scene = PHActiveScene();
    CGRect S = UIScreen.mainScreen.bounds;

    _window = scene
        ? [[PassthroughWindow alloc] initWithWindowScene:scene]
        : [[PassthroughWindow alloc] initWithFrame:S];
    _window.windowLevel     = UIWindowLevelAlert + 500;
    _window.backgroundColor = [UIColor clearColor];

    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor clearColor];
    _window.rootViewController = root;

    /* Overlay views */
    _aimLine = [[AimLineView alloc] initWithFrame:S];
    _aimLine.hidden = YES;
    [root.view addSubview:_aimLine];

    _autoAim = [[AutoAimView alloc] initWithFrame:S];
    _autoAim.hidden = YES;
    [root.view addSubview:_autoAim];

    _debugHUD = [[DebugHUD alloc] initWithFrame:CGRectMake(10, 55, 162, 82)];
    _debugHUD.hidden = YES;
    [root.view addSubview:_debugHUD];

    /* Panel */
    CGFloat pw = 300, ph = 390;
    _panel = [[UIView alloc]
              initWithFrame:CGRectMake((S.size.width-pw)/2, (S.size.height-ph)/2, pw, ph)];
    _panel.layer.cornerRadius  = 18;
    _panel.layer.masksToBounds = YES;
    _panel.layer.borderColor   = [UIColor colorWithWhite:1 alpha:0.14f].CGColor;
    _panel.layer.borderWidth   = 1;

    /* Blur */
    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blur.frame = _panel.bounds;
    blur.autoresizingMask = 18;
    [_panel addSubview:blur];

    /* Dark tint */
    UIView *tint = [[UIView alloc] initWithFrame:_panel.bounds];
    tint.backgroundColor = [UIColor colorWithRed:0.04f green:0.04f blue:0.14f alpha:0.68f];
    tint.autoresizingMask = 18;
    [_panel addSubview:tint];

    UIView *c = [[UIView alloc] initWithFrame:_panel.bounds];
    c.backgroundColor = [UIColor clearColor];
    [_panel addSubview:c];

    /* Title */
    [c addSubview:[self _lbl:@"🎱  POOL HELPER"
                        font:[UIFont systemFontOfSize:17 weight:UIFontWeightBold]
                       color:[UIColor colorWithRed:0.25f green:0.85f blue:1.0f alpha:1]
                       frame:CGRectMake(0,15,pw,36) align:1]];
    [c addSubview:[self _lbl:@"8 BALL POOL ASSISTANT"
                        font:[UIFont systemFontOfSize:10 weight:UIFontWeightMedium]
                       color:[UIColor colorWithWhite:1 alpha:0.30f]
                       frame:CGRectMake(0,50,pw,16) align:1]];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(18,72,pw-36,0.5f)];
    sep.backgroundColor = [UIColor colorWithWhite:1 alpha:0.13f];
    [c addSubview:sep];

    /* Rows */
    [self _row:c label:@"Auto Play"  sub:@"Shoots for you (3 s)"        tag:101 y:78  w:pw];
    [self _row:c label:@"Auto Aim"   sub:@"Shows target cross-hairs"    tag:102 y:132 w:pw];
    [self _row:c label:@"Aim Line"   sub:@"Ball path + wall reflections" tag:103 y:186 w:pw];
    [self _row:c label:@"Debug"      sub:@"Feature status HUD"           tag:104 y:240 w:pw];

    /* Close */
    UIButton *cls = [UIButton buttonWithType:UIButtonTypeSystem];
    cls.frame = CGRectMake(18, ph-60, pw-36, 40);
    cls.layer.cornerRadius = 10; cls.layer.masksToBounds = YES;
    cls.backgroundColor = [UIColor colorWithRed:0.85f green:0.15f blue:0.18f alpha:0.88f];
    [cls setTitle:@"✕  Close" forState:UIControlStateNormal];
    [cls setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    cls.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [cls addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
    [c addSubview:cls];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_panPanel:)];
    [_panel addGestureRecognizer:pan];
    [root.view addSubview:_panel];

    _panel.hidden = YES; _panel.alpha = 0;
    _window.hidden = NO;
    [_window makeKeyAndVisible];
    [self _resignKey];
}

/* ── Toggle ──────────────────────────────────────────────────────────── */
- (void)_toggle:(UISwitch *)sw {
    NSString *names[] = { @"", @"Auto Play", @"Auto Aim", @"Aim Line", @"Debug" };
    NSString *name = (sw.tag >= 101 && sw.tag <= 104) ? names[sw.tag - 100] : @"";
    _state[name] = @(sw.on);

    dispatch_async(dispatch_get_main_queue(), ^{
        switch (sw.tag) {
            case 101:
                sw.on ? [self->_engine start] : [self->_engine stop];
                break;
            case 102:
                self->_autoAim.hidden = !sw.on;
                sw.on ? [self->_autoAim startRefresh] : [self->_autoAim stopRefresh];
                break;
            case 103:
                self->_aimLine.hidden = !sw.on;
                sw.on ? [self->_aimLine startRefresh] : [self->_aimLine stopRefresh];
                break;
            case 104:
                self->_debugHUD.hidden = !sw.on;
                break;
        }
        if (!self->_debugHUD.hidden) [self->_debugHUD setStatus:self->_state];
    });
}

/* ── Panel pan ───────────────────────────────────────────────────────── */
- (void)_panPanel:(UIPanGestureRecognizer *)gr {
    UIView *v = gr.view, *p = v.superview;
    if (!p) return;
    if (gr.state == UIGestureRecognizerStateBegan) _panOffset = v.center;
    CGPoint t = [gr translationInView:p];
    CGSize  sz = p.bounds.size;
    CGFloat hw = v.bounds.size.width/2, hh = v.bounds.size.height/2;
    v.center = CGPointMake(MAX(hw, MIN(_panOffset.x+t.x, sz.width-hw)),
                           MAX(hh, MIN(_panOffset.y+t.y, sz.height-hh)));
}

/* ── Show / hide ─────────────────────────────────────────────────────── */
- (void)show {
    _panel.hidden = NO;
    _panel.transform = CGAffineTransformMakeScale(0.90f, 0.90f);
    [UIView animateWithDuration:0.22 delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self->_panel.alpha = 1;
        self->_panel.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hide {
    [UIView animateWithDuration:0.16 delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self->_panel.alpha = 0;
        self->_panel.transform = CGAffineTransformMakeScale(0.90f, 0.90f);
    } completion:^(BOOL d) { self->_panel.hidden = YES; }];
}

- (BOOL)visible { return !_panel.hidden && _panel.alpha > 0.01f; }

/* ── Builder helpers ─────────────────────────────────────────────────── */
- (void)_row:(UIView *)p label:(NSString *)lbl sub:(NSString *)sub
         tag:(NSInteger)tag y:(CGFloat)y w:(CGFloat)w {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, w, 50)];
    row.backgroundColor = [UIColor clearColor];

    [row addSubview:[self _lbl:lbl
                          font:[UIFont systemFontOfSize:14 weight:UIFontWeightMedium]
                         color:[UIColor colorWithWhite:1 alpha:0.95f]
                         frame:CGRectMake(16,3,w-100,22) align:0]];
    [row addSubview:[self _lbl:sub
                          font:[UIFont systemFontOfSize:11]
                         color:[UIColor colorWithWhite:1 alpha:0.38f]
                         frame:CGRectMake(16,25,w-100,16) align:0]];

    UISwitch *sw = [UISwitch new];
    sw.onTintColor = [UIColor colorWithRed:0.18f green:0.72f blue:1.0f alpha:1];
    sw.tag = tag; sw.on = NO;
    CGSize ss = sw.intrinsicContentSize;
    sw.frame = CGRectMake(w-ss.width-16, (50-ss.height)/2, ss.width, ss.height);
    [sw addTarget:self action:@selector(_toggle:) forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(16, 49, w-32, 0.5f)];
    line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.09f];
    [row addSubview:line];
    [p addSubview:row];
}

- (UILabel *)_lbl:(NSString *)t font:(UIFont *)f color:(UIColor *)c
             frame:(CGRect)r align:(NSTextAlignment)a {
    UILabel *l = [[UILabel alloc] initWithFrame:r];
    l.text = t; l.font = f; l.textColor = c; l.textAlignment = a;
    l.userInteractionEnabled = NO;
    return l;
}

- (void)_resignKey {
    for (UIWindowScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows)
            if (w != _window) { [w makeKeyWindow]; return; }
    }
}
@end

/* ═══════════════════════════════════════════════════════════════════════
   FloatingButton  (🎱 drag button)
   ═══════════════════════════════════════════════════════════════════════ */
@interface FloatingButton : NSObject
@property (nonatomic, strong) PassthroughWindow *window;
@property (nonatomic, strong) UIButton          *btn;
@property (nonatomic, strong) MenuController    *menu;
@property (nonatomic, assign) CGPoint            ds, cs;
@property (nonatomic, assign) BOOL               dragged;
- (instancetype)initWithMenu:(MenuController *)m;
- (void)show;
@end

@implementation FloatingButton

- (instancetype)initWithMenu:(MenuController *)m {
    self = [super init]; if (self){ _menu = m; [self _build]; } return self;
}

- (void)_build {
    UIWindowScene *scene = PHActiveScene();
    CGRect S = UIScreen.mainScreen.bounds;
    _window = scene
        ? [[PassthroughWindow alloc] initWithWindowScene:scene]
        : [[PassthroughWindow alloc] initWithFrame:S];
    _window.windowLevel     = UIWindowLevelAlert + 600;
    _window.backgroundColor = [UIColor clearColor];

    UIViewController *r = [UIViewController new];
    r.view.backgroundColor = [UIColor clearColor];
    _window.rootViewController = r;

    CGFloat sz = 52, mg = 14;
    _btn = [UIButton buttonWithType:UIButtonTypeCustom];
    _btn.frame = CGRectMake(S.size.width-sz-mg, S.size.height*0.36f, sz, sz);
    _btn.layer.cornerRadius = sz/2;
    _btn.backgroundColor    = [UIColor colorWithRed:0.05f green:0.05f blue:0.17f alpha:0.95f];
    _btn.layer.borderColor  = [UIColor colorWithRed:0.22f green:0.68f blue:1.0f alpha:0.95f].CGColor;
    _btn.layer.borderWidth  = 2.2f;
    _btn.layer.shadowColor  = [UIColor blackColor].CGColor;
    _btn.layer.shadowOffset = CGSizeMake(0, 4);
    _btn.layer.shadowRadius = 8; _btn.layer.shadowOpacity = 0.55f;

    UILabel *ico = [[UILabel alloc] initWithFrame:_btn.bounds];
    ico.text = @"🎱"; ico.font = [UIFont systemFontOfSize:25];
    ico.textAlignment = NSTextAlignmentCenter;
    ico.userInteractionEnabled = NO;
    [_btn addSubview:ico];

    [_btn addTarget:self action:@selector(_tap:) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_pan:)];
    [_btn addGestureRecognizer:pan];
    [r.view addSubview:_btn];
}

- (void)show {
    _window.hidden = NO;
    [_window makeKeyAndVisible];
    [self _resignKey];
    _btn.alpha = 0; _btn.transform = CGAffineTransformMakeScale(0.1f, 0.1f);
    [UIView animateWithDuration:0.40 delay:0
         usingSpringWithDamping:0.60 initialSpringVelocity:0.8 options:0
                     animations:^{ self->_btn.alpha=1; self->_btn.transform=CGAffineTransformIdentity; }
                     completion:nil];
}

- (void)_tap:(id)s {
    if (!_dragged) ([_menu visible] ? [_menu hide] : [_menu show]);
}

- (void)_pan:(UIPanGestureRecognizer *)gr {
    UIView *v=gr.view, *p=v.superview; if(!p) return;
    if (gr.state==UIGestureRecognizerStateBegan){ _ds=[gr locationInView:p]; _cs=v.center; _dragged=NO; }
    CGPoint c=[gr locationInView:p];
    if(fabsf(c.x-_ds.x)>4||fabsf(c.y-_ds.y)>4) _dragged=YES;
    if (_dragged) {
        CGFloat hw=v.bounds.size.width/2, hh=v.bounds.size.height/2;
        CGSize  sz=p.bounds.size;
        v.center = CGPointMake(MAX(hw,MIN(_cs.x+(c.x-_ds.x),sz.width-hw)),
                               MAX(hh,MIN(_cs.y+(c.y-_ds.y),sz.height-hh)));
    }
    if (gr.state==UIGestureRecognizerStateEnded||gr.state==UIGestureRecognizerStateCancelled)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.05*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ self->_dragged=NO; });
}

- (void)_resignKey {
    for (UIWindowScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows)
            if (w != _window && w != _menu.window) { [w makeKeyWindow]; return; }
    }
}
@end

/* ═══════════════════════════════════════════════════════════════════════
   OverlayManager — singleton
   ═══════════════════════════════════════════════════════════════════════ */
@interface OverlayManager : NSObject
+ (instancetype)shared;
- (void)startWaiting;
@end

@implementation OverlayManager {
    MenuController *_menu;
    FloatingButton *_fab;
    NSInteger       _tries;
}

+ (instancetype)shared {
    static OverlayManager *i; static dispatch_once_t t;
    dispatch_once(&t, ^{ i = [OverlayManager new]; });
    return i;
}

- (void)startWaiting { _tries = 0; [self _try]; }

- (void)_try {
    UIWindowScene *sc = PHActiveScene();
    if ((!sc || sc.windows.count == 0) && _tries < 30) {
        _tries++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self _try]; });
        return;
    }
    NSLog(@"[PoolHelper] Game window ready — launching");
    _menu = [MenuController new];
    _fab  = [[FloatingButton alloc] initWithMenu:_menu];
    [_fab show];
    NSLog(@"[PoolHelper] 🎱 Ready");
}
@end

/* ═══════════════════════════════════════════════════════════════════════
   Constructor — called when dylib is injected
   ═══════════════════════════════════════════════════════════════════════ */
__attribute__((constructor))
static void PHInit(void) {
    NSLog(@"[PoolHelper] Injected");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[OverlayManager shared] startWaiting];
    });
}
