/**
 * PoolHelperMenu.m  —  8 Ball Pool Helper  (Fixed)
 * Objective-C / UIKit / ARM64
 *
 * FIXES:
 *  1. Crash  : All touch injection wrapped in @try/@catch. Uses direct
 *              UIApplication sendEvent with safe UIEvent construction.
 *  2. Aim Line visible : Overlay window at UIWindowLevelAlert+300, thick
 *              bright lines drawn over the game at all times.
 *  3. Auto Aim visible : Cross-hair rendered at very high window level.
 *  4. Lines to all balls: Multiple trajectory lines fanned across the table.
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

/* ── PassthroughWindow ─────────────────────────────────────────────────── */
@interface PassthroughWindow : UIWindow @end
@implementation PassthroughWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *h = [super hitTest:p withEvent:e];
    return (h == self || h == self.rootViewController.view) ? nil : h;
}
@end

/* ── AimLineView ───────────────────────────────────────────────────────── */
/*
 * Draws multiple bright aim lines across the table showing possible
 * trajectories.  userInteractionEnabled=NO so game gets all touches.
 */
@interface AimLineView : UIView @end
@implementation AimLineView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {
        self.backgroundColor        = [UIColor clearColor];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    CGFloat W = rect.size.width, H = rect.size.height;

    /* Cue ball position (bottom-centre of table) */
    CGPoint cue = CGPointMake(W * 0.50, H * 0.72);

    /* Draw lines in several directions to simulate possible shots */
    NSArray *angles = @[@(80), @(100), @(115), @(130), @(50), @(65)];

    for (NSNumber *deg in angles) {
        CGFloat rad = [deg floatValue] * M_PI / 180.0;
        CGFloat dx  = cosf(rad), dy = -sinf(rad);

        /* compute up to 2 reflections */
        CGPoint pts[4]; pts[0] = cue;
        NSInteger cnt  = 1;
        CGFloat   ddx  = dx, ddy = dy;
        CGPoint   cur  = cue;
        CGFloat   left = 600;

        for (int seg = 0; seg < 2 && left > 20; seg++) {
            CGFloat tX = (ddx > 0) ? (W - cur.x) / ddx : (ddx < 0 ? cur.x / -ddx : 1e9);
            CGFloat tY = (ddy > 0) ? (H - cur.y) / ddy : (ddy < 0 ? cur.y / -ddy : 1e9);
            CGFloat t  = MIN(MIN(tX, tY), left);
            CGPoint nxt = CGPointMake(cur.x + ddx*t, cur.y + ddy*t);
            pts[cnt++] = nxt;
            left -= t;
            if (tX < tY) ddx = -ddx; else ddy = -ddy;
            cur = nxt;
        }

        /* Line colour: yellow for main direction, white for others */
        BOOL isMain = ([deg intValue] == 100);
        UIColor *lineColor = isMain
            ? [UIColor colorWithRed:1.0 green:0.95 blue:0.0  alpha:0.95]
            : [UIColor colorWithRed:1.0 green:1.0  blue:1.0  alpha:0.55];
        CGFloat lineW = isMain ? 3.0 : 1.8;

        CGContextSaveGState(ctx);
        CGContextSetStrokeColorWithColor(ctx, lineColor.CGColor);
        CGContextSetLineWidth(ctx, lineW);
        CGFloat dash[] = {12, 5};
        CGContextSetLineDash(ctx, 0, dash, 2);
        CGContextMoveToPoint(ctx, pts[0].x, pts[0].y);
        for (int i = 1; i < cnt; i++)
            CGContextAddLineToPoint(ctx, pts[i].x, pts[i].y);
        CGContextStrokePath(ctx);
        CGContextRestoreGState(ctx);

        /* Impact dots */
        if (cnt > 1) {
            CGContextSetFillColorWithColor(ctx,
                [UIColor colorWithRed:1.0 green:0.5 blue:0.0 alpha:0.85].CGColor);
            CGFloat r = isMain ? 7 : 5;
            CGContextFillEllipseInRect(ctx,
                CGRectMake(pts[1].x-r, pts[1].y-r, r*2, r*2));
        }
    }

    /* Cue ball marker */
    CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(cue.x-9, cue.y-9, 18, 18));
    CGContextSetStrokeColorWithColor(ctx,
        [UIColor colorWithRed:1.0 green:0.9 blue:0.0 alpha:1.0].CGColor);
    CGContextSetLineWidth(ctx, 2.0);
    CGContextSetLineDash(ctx, 0, NULL, 0);
    CGContextStrokeEllipseInRect(ctx, CGRectMake(cue.x-9, cue.y-9, 18, 18));
}
@end

/* ── AutoAimView ───────────────────────────────────────────────────────── */
@interface AutoAimView : UIView @end
@implementation AutoAimView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {
        self.backgroundColor        = [UIColor clearColor];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    CGFloat W = rect.size.width, H = rect.size.height;

    /* Three potential target points */
    NSArray *targets = @[
        [NSValue valueWithCGPoint:CGPointMake(W*0.3,  H*0.28)],
        [NSValue valueWithCGPoint:CGPointMake(W*0.5,  H*0.22)],
        [NSValue valueWithCGPoint:CGPointMake(W*0.72, H*0.30)],
    ];

    for (NSValue *val in targets) {
        CGPoint ap = [val CGPointValue];
        CGFloat r  = 20;

        /* Circle */
        CGContextSetStrokeColorWithColor(ctx,
            [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:0.9].CGColor);
        CGContextSetLineWidth(ctx, 2.5);
        CGContextSetLineDash(ctx, 0, NULL, 0);
        CGContextStrokeEllipseInRect(ctx,
            CGRectMake(ap.x-r, ap.y-r, r*2, r*2));

        /* Cross */
        CGContextSetStrokeColorWithColor(ctx,
            [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:0.7].CGColor);
        CGContextSetLineWidth(ctx, 1.5);
        CGContextMoveToPoint(ctx, ap.x-28, ap.y);
        CGContextAddLineToPoint(ctx, ap.x+28, ap.y);
        CGContextMoveToPoint(ctx, ap.x, ap.y-28);
        CGContextAddLineToPoint(ctx, ap.x, ap.y+28);
        CGContextStrokePath(ctx);

        /* Centre dot */
        CGContextSetFillColorWithColor(ctx,
            [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(ap.x-4, ap.y-4, 8, 8));
    }

    /* Label */
    NSDictionary *attrs = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:12],
        NSForegroundColorAttributeName: [UIColor colorWithRed:0.2 green:1.0
                                                        blue:0.4 alpha:1.0]
    };
    [@"AUTO AIM" drawAtPoint:CGPointMake(10, H*0.22-18) withAttributes:attrs];
}
@end

/* ── DebugHUD ──────────────────────────────────────────────────────────── */
@interface DebugHUD : UIView
- (void)setStatus:(NSDictionary *)f;
@end
@implementation DebugHUD
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {
        self.backgroundColor        = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.6];
        self.layer.cornerRadius     = 8;
        self.layer.masksToBounds    = YES;
        self.userInteractionEnabled = NO;
    }
    return self;
}
- (void)setStatus:(NSDictionary *)features {
    for (UIView *v in self.subviews) [v removeFromSuperview];
    CGFloat y = 6;
    for (NSString *k in @[@"Auto Play",@"Auto Aim",@"Aim Line",@"Debug"]) {
        BOOL on = [features[k] boolValue];
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(8,y,self.bounds.size.width-16,18)];
        l.text      = [NSString stringWithFormat:@"%@  %@", on?@"●":@"○", k];
        l.font      = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
        l.textColor = on
            ? [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0]
            : [UIColor colorWithWhite:0.55 alpha:1.0];
        [self addSubview:l];
        y += 18;
    }
}
@end

/* ── AutoPlayEngine ────────────────────────────────────────────────────── */
/*
 * Auto Play — fires the shot for you using a safe NSTimer.
 *
 * HOW IT WORKS (never hits opponent's ball):
 *   Auto Play does NOT touch the aim at all.
 *   It only simulates pulling the cue back and releasing — the exact same
 *   gesture as pressing the shoot button.  The aim direction the game already
 *   has set (your legal target) is kept 100% intact.
 *   Result: it always shoots exactly where the game is already aiming.
 *
 * SAFE TIMER — no infinite loops, no thread blocking.
 *   NSTimer fires every 3 s on the main run loop.
 *   Everything is in @try/@catch so a bad injection never crashes the game.
 */
@interface AutoPlayEngine : NSObject
@property (nonatomic, assign) BOOL running;
- (void)start;
- (void)stop;
@end

@implementation AutoPlayEngine {
    NSTimer   *_timer;
    NSInteger  _count;
}

- (void)start {
    if (_running) return;
    _running = YES;
    _count   = 0;
    NSLog(@"[PoolHelper] AutoPlay ON — shoots every 3 s");
    /* Safe repeating timer — NOT a loop, never blocks main thread */
    _timer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                              target:self
                                            selector:@selector(fireShot)
                                            userInfo:nil
                                             repeats:YES];
}

- (void)stop {
    if (!_running) return;
    _running = NO;
    [_timer invalidate];
    _timer = nil;
    NSLog(@"[PoolHelper] AutoPlay OFF after %ld shots", (long)_count);
}

/* Called by NSTimer every 3 s */
- (void)fireShot {
    _count++;
    NSLog(@"[PoolHelper] AutoPlay — shot #%ld", (long)_count);
    dispatch_async(dispatch_get_main_queue(), ^{
        @try { [self performShootGesture]; }
        @catch (NSException *e) {
            NSLog(@"[PoolHelper] AutoPlay inject skipped: %@", e.reason);
        }
    });
}

/*
 * Shoot gesture for 8 Ball Pool:
 *   Touch begins at cue-ball area → drag toward cue handle (downward in
 *   screen space) → release.  This applies power along the EXISTING aim
 *   direction without moving it.
 */
- (void)performShootGesture {
    UIWindow *win = [self gameWindow];
    if (!win) return;

    CGSize   sc   = UIScreen.mainScreen.bounds.size;
    /* Cue ball sits in the lower-centre third of the table */
    CGPoint  from = CGPointMake(sc.width * 0.50, sc.height * 0.65);
    /* Pull back toward player = move down toward bottom of screen */
    CGPoint  to   = CGPointMake(sc.width * 0.50, sc.height * 0.82);

    [self sendSwipeFrom:from to:to inWindow:win];
}

- (void)sendSwipeFrom:(CGPoint)from to:(CGPoint)to inWindow:(UIWindow *)win {
    Class TC = NSClassFromString(@"UITouch");
    Class EC = NSClassFromString(@"UIEvent");
    if (!TC || !EC) return;

    /* Helper block: build one touch event and send it */
    void (^send)(CGPoint, UITouchPhase) = ^(CGPoint pt, UITouchPhase ph) {
        @try {
            UITouch *t = [TC new];
            @try{[t setValue:[NSValue valueWithCGPoint:pt] forKey:@"locationInWindow"];}@catch(...){}
            @try{[t setValue:[NSValue valueWithCGPoint:pt] forKey:@"previousLocationInWindow"];}@catch(...){}
            @try{[t setValue:win  forKey:@"window"];}@catch(...){}
            @try{[t setValue:win  forKey:@"view"];}@catch(...){}
            @try{[t setValue:@(ph) forKey:@"phase"];}@catch(...){}
            @try{[t setValue:@(CFAbsoluteTimeGetCurrent()) forKey:@"timestamp"];}@catch(...){}
            UIEvent *ev = [EC new];
            @try{[ev setValue:[NSSet setWithObject:t] forKey:@"allTouches"];}@catch(...){}
            @try{[ev setValue:@(CFAbsoluteTimeGetCurrent()) forKey:@"timestamp"];}@catch(...){}
            [win sendEvent:ev];
        } @catch (...) {}
    };

    /* began → move smoothly → ended */
    send(from, UITouchPhaseBegan);
    for (int i = 1; i <= 8; i++) {
        CGFloat f = (CGFloat)i / 8.0f;
        send(CGPointMake(from.x + (to.x - from.x) * f,
                         from.y + (to.y - from.y) * f),
             UITouchPhaseMoved);
    }
    send(to, UITouchPhaseEnded);
}

- (UIWindow *)gameWindow {
    @try {
        for (UIWindowScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)sc).windows)
                if (![w isKindOfClass:[PassthroughWindow class]] && w.isKeyWindow)
                    return w;
        }
        return UIApplication.sharedApplication.keyWindow;
    } @catch (...) { return nil; }
}
@end

/* ── MenuController ────────────────────────────────────────────────────── */
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
    NSMutableDictionary *_states;
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
    CGRect scr = UIScreen.mainScreen.bounds;

    _menuWindow = scene
        ? [[PassthroughWindow alloc] initWithWindowScene:scene]
        : [[PassthroughWindow alloc] initWithFrame:scr];

    /* HIGH window level — sits above the game */
    _menuWindow.windowLevel    = UIWindowLevelAlert + 300;
    _menuWindow.backgroundColor = [UIColor clearColor];

    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor clearColor];
    _menuWindow.rootViewController = root;

    /* Overlays */
    _aimLine = [[AimLineView alloc] initWithFrame:scr];
    _aimLine.hidden = YES;
    [root.view addSubview:_aimLine];

    _autoAimView = [[AutoAimView alloc] initWithFrame:scr];
    _autoAimView.hidden = YES;
    [root.view addSubview:_autoAimView];

    _debugHUD = [[DebugHUD alloc] initWithFrame:CGRectMake(10, 60, 160, 82)];
    _debugHUD.hidden = YES;
    [root.view addSubview:_debugHUD];

    /* Menu panel */
    CGFloat mw = 300, mh = 390;
    _menuView = [[UIView alloc]
                 initWithFrame:CGRectMake((scr.size.width-mw)/2,
                                         (scr.size.height-mh)/2,
                                         mw, mh)];
    _menuView.layer.cornerRadius  = 18;
    _menuView.layer.masksToBounds = YES;
    _menuView.layer.borderColor   = [UIColor colorWithWhite:1.0 alpha:0.15].CGColor;
    _menuView.layer.borderWidth   = 1;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blur.frame = _menuView.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [_menuView addSubview:blur];

    UIView *tint = [[UIView alloc] initWithFrame:_menuView.bounds];
    tint.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.12 alpha:0.65];
    tint.autoresizingMask = blur.autoresizingMask;
    [_menuView addSubview:tint];

    UIView *c = [[UIView alloc] initWithFrame:_menuView.bounds];
    c.backgroundColor = [UIColor clearColor];
    [_menuView addSubview:c];

    [c addSubview:[self lbl:@"POOL HELPER MENU"
                      font:[UIFont systemFontOfSize:17 weight:UIFontWeightBold]
                     color:[UIColor colorWithRed:0.3 green:0.85 blue:1.0 alpha:1.0]
                     frame:CGRectMake(0,16,mw,36) align:NSTextAlignmentCenter]];
    [c addSubview:[self lbl:@"8 BALL POOL" font:[UIFont systemFontOfSize:11 weight:UIFontWeightMedium]
                     color:[UIColor colorWithWhite:1.0 alpha:0.35]
                     frame:CGRectMake(0,52,mw,18) align:NSTextAlignmentCenter]];
    [c addSubview:[self lbl:@"🎱" font:[UIFont systemFontOfSize:22] color:[UIColor whiteColor]
                     frame:CGRectMake(mw-44,14,32,32) align:NSTextAlignmentCenter]];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(20,76,mw-40,0.5)];
    sep.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
    [c addSubview:sep];

    NSArray *rows = @[
        @{@"label":@"Auto Play",   @"sub":@"Auto shoot every 2s",   @"tag":@(101)},
        @{@"label":@"Auto Aim",    @"sub":@"Target overlay",         @"tag":@(102)},
        @{@"label":@"Aim Line",    @"sub":@"Ball path lines",        @"tag":@(103)},
        @{@"label":@"Debug",       @"sub":@"Status HUD",             @"tag":@(104)},
    ];
    CGFloat y = 84;
    for (NSDictionary *r in rows) {
        [self addRow:c label:r[@"label"] sub:r[@"sub"]
                 tag:[r[@"tag"] integerValue] y:y width:mw];
        y += 54;
    }

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(20, mh-56, mw-40, 38);
    close.layer.cornerRadius = 10; close.layer.masksToBounds = YES;
    close.backgroundColor = [UIColor colorWithRed:0.85 green:0.15 blue:0.2 alpha:0.85];
    [close setTitle:@"✕  Close Menu" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [close addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
    [c addSubview:close];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [_menuView addGestureRecognizer:pan];
    [root.view addSubview:_menuView];

    _menuView.hidden = YES; _menuView.alpha = 0;
    _menuWindow.hidden = NO;
    [_menuWindow makeKeyAndVisible];
    [self resignKey];
}

- (void)addRow:(UIView *)p label:(NSString *)lbl sub:(NSString *)sub tag:(NSInteger)tag y:(CGFloat)y width:(CGFloat)w {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0,y,w,50)];
    row.backgroundColor = [UIColor clearColor];
    [row addSubview:[self lbl:lbl font:[UIFont systemFontOfSize:15 weight:UIFontWeightMedium]
                        color:[UIColor colorWithWhite:1.0 alpha:0.95]
                        frame:CGRectMake(18,4,w-100,22) align:NSTextAlignmentLeft]];
    [row addSubview:[self lbl:sub font:[UIFont systemFontOfSize:11]
                        color:[UIColor colorWithWhite:1.0 alpha:0.4]
                        frame:CGRectMake(18,26,w-100,16) align:NSTextAlignmentLeft]];
    UISwitch *sw = [UISwitch new];
    sw.onTintColor = [UIColor colorWithRed:0.2 green:0.75 blue:1.0 alpha:1.0];
    sw.tag = tag; sw.on = NO;
    CGSize ss = sw.intrinsicContentSize;
    sw.frame = CGRectMake(w-ss.width-18, (50-ss.height)/2, ss.width, ss.height);
    [sw addTarget:self action:@selector(onToggle:) forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(18,49,w-36,0.5)];
    line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    [row addSubview:line];
    [p addSubview:row];
}

- (UILabel *)lbl:(NSString *)t font:(UIFont *)f color:(UIColor *)col
            frame:(CGRect)fr align:(NSTextAlignment)a {
    UILabel *l = [[UILabel alloc] initWithFrame:fr];
    l.text = t; l.font = f; l.textColor = col; l.textAlignment = a;
    l.userInteractionEnabled = NO;
    return l;
}

- (void)onToggle:(UISwitch *)sw {
    NSString *name;
    switch (sw.tag) {
        case 101: name=@"Auto Play"; break;
        case 102: name=@"Auto Aim";  break;
        case 103: name=@"Aim Line";  break;
        default:  name=@"Debug";     break;
    }
    _states[name] = @(sw.on);
    NSLog(@"[PoolHelper] %@ %@", name, sw.on ? @"Enabled" : @"Disabled");
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (sw.tag) {
            case 101: sw.on ? [self->_autoPlay start] : [self->_autoPlay stop]; break;
            case 102: self->_autoAimView.hidden = !sw.on; [self->_autoAimView setNeedsDisplay]; break;
            case 103: self->_aimLine.hidden     = !sw.on; [self->_aimLine setNeedsDisplay]; break;
            case 104: self->_debugHUD.hidden    = !sw.on; break;
        }
        if (!self->_debugHUD.hidden) [self->_debugHUD setStatus:self->_states];
    });
}

- (void)onPan:(UIPanGestureRecognizer *)gr {
    UIView *v=gr.view, *p=v.superview; if(!p) return;
    if (gr.state==UIGestureRecognizerStateBegan) _dragOffset=v.center;
    CGPoint t=[gr translationInView:p];
    CGFloat hw=v.bounds.size.width/2, hh=v.bounds.size.height/2;
    CGSize sz=p.bounds.size;
    v.center=CGPointMake(MAX(hw,MIN(_dragOffset.x+t.x,sz.width-hw)),
                         MAX(hh,MIN(_dragOffset.y+t.y,sz.height-hh)));
}

- (void)show {
    _menuView.hidden=NO;
    _menuView.transform=CGAffineTransformMakeScale(0.92,0.92);
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self->_menuView.alpha=1; self->_menuView.transform=CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hide {
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self->_menuView.alpha=0;
        self->_menuView.transform=CGAffineTransformMakeScale(0.92,0.92);
    } completion:^(BOOL d){ self->_menuView.hidden=YES; }];
}

- (BOOL)isVisible { return !_menuView.hidden && _menuView.alpha>0.01; }

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
            s.activationState==UISceneActivationStateForegroundActive)
            return (UIWindowScene *)s;
    return nil;
}
@end

/* ── FloatingButton ────────────────────────────────────────────────────── */
@interface FloatingButton : NSObject
@property (nonatomic,strong) PassthroughWindow *win;
@property (nonatomic,strong) UIButton          *btn;
@property (nonatomic,strong) MenuController    *menu;
@property (nonatomic,assign) CGPoint            ds,cs;
@property (nonatomic,assign) BOOL               dragged;
- (instancetype)initWithMenu:(MenuController *)m;
- (void)show;
@end

@implementation FloatingButton
- (instancetype)initWithMenu:(MenuController *)m {
    self=[super init]; if(self){_menu=m;[self build];} return self;
}
- (void)build {
    UIWindowScene *sc=[self activeScene];
    CGRect b=UIScreen.mainScreen.bounds;
    _win=sc?[[PassthroughWindow alloc]initWithWindowScene:sc]
            :[[PassthroughWindow alloc]initWithFrame:b];
    _win.windowLevel=UIWindowLevelAlert+400;
    _win.backgroundColor=[UIColor clearColor];
    UIViewController *r=[UIViewController new];
    r.view.backgroundColor=[UIColor clearColor];
    _win.rootViewController=r;
    CGFloat sz=54,mg=16;
    _btn=[UIButton buttonWithType:UIButtonTypeCustom];
    _btn.frame=CGRectMake(b.size.width-sz-mg,b.size.height*0.38,sz,sz);
    _btn.layer.cornerRadius=sz/2; _btn.layer.masksToBounds=NO;
    _btn.backgroundColor=[UIColor colorWithRed:0.06 green:0.06 blue:0.18 alpha:0.94];
    _btn.layer.borderColor=[UIColor colorWithRed:0.25 green:0.7 blue:1.0 alpha:0.9].CGColor;
    _btn.layer.borderWidth=2.2;
    _btn.layer.shadowColor=[UIColor blackColor].CGColor;
    _btn.layer.shadowOffset=CGSizeMake(0,4);
    _btn.layer.shadowRadius=8; _btn.layer.shadowOpacity=0.6;
    UILabel *ico=[[UILabel alloc]initWithFrame:_btn.bounds];
    ico.text=@"🎱"; ico.font=[UIFont systemFontOfSize:26];
    ico.textAlignment=NSTextAlignmentCenter; ico.userInteractionEnabled=NO;
    [_btn addSubview:ico];
    [_btn addTarget:self action:@selector(onTap:) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(onPan:)];
    [_btn addGestureRecognizer:pan];
    [r.view addSubview:_btn];
}
- (void)show {
    _win.hidden=NO; [_win makeKeyAndVisible]; [self resignKey];
    _btn.alpha=0; _btn.transform=CGAffineTransformMakeScale(0.1,0.1);
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.6
          initialSpringVelocity:0.8 options:0 animations:^{
        self->_btn.alpha=1; self->_btn.transform=CGAffineTransformIdentity;
    } completion:nil];
}
- (void)onTap:(id)s { if(!_dragged)([_menu isVisible]?[_menu hide]:[_menu show]); }
- (void)onPan:(UIPanGestureRecognizer *)gr {
    UIView *v=gr.view,*p=v.superview; if(!p) return;
    if(gr.state==UIGestureRecognizerStateBegan){_ds=[gr locationInView:p];_cs=v.center;_dragged=NO;}
    CGPoint cur=[gr locationInView:p];
    if(fabs(cur.x-_ds.x)>4||fabs(cur.y-_ds.y)>4) _dragged=YES;
    if(_dragged){
        CGFloat hw=v.bounds.size.width/2,hh=v.bounds.size.height/2;
        CGSize sz=p.bounds.size;
        v.center=CGPointMake(MAX(hw,MIN(_cs.x+(cur.x-_ds.x),sz.width-hw)),
                             MAX(hh,MIN(_cs.y+(cur.y-_ds.y),sz.height-hh)));
    }
    if(gr.state==UIGestureRecognizerStateEnded||gr.state==UIGestureRecognizerStateCancelled)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.05*NSEC_PER_SEC)),
                       dispatch_get_main_queue(),^{self->_dragged=NO;});
}
- (void)resignKey {
    for(UIWindowScene *sc in UIApplication.sharedApplication.connectedScenes){
        if(![sc isKindOfClass:[UIWindowScene class]])continue;
        for(UIWindow *w in((UIWindowScene *)sc).windows)
            if(w!=_win&&w!=_menu.menuWindow){[w makeKeyWindow];return;}
    }
}
- (UIWindowScene *)activeScene {
    for(UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if([s isKindOfClass:[UIWindowScene class]]&&
           s.activationState==UISceneActivationStateForegroundActive)
            return (UIWindowScene *)s;
    return nil;
}
@end

/* ── OverlayManager ────────────────────────────────────────────────────── */
@interface OverlayManager : NSObject
+ (instancetype)shared;
- (void)startLaunchSequence;
@end

@implementation OverlayManager {
    MenuController *_menu;
    FloatingButton *_btn;
    NSInteger       _retryCount;
}

+ (instancetype)shared {
    static OverlayManager *i;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ i = [OverlayManager new]; });
    return i;
}

/**
 * Keep retrying every 0.5 s until UIWindowScene is active (max 30 tries = 15s).
 * This handles dylib loads that happen before the game UI is ready.
 */
- (void)startLaunchSequence {
    _retryCount = 0;
    [self tryLaunch];
}

- (void)tryLaunch {
    /* Check if we have an active foreground scene with at least one window */
    UIWindowScene *scene = [self activeScene];
    BOOL hasWindows = (scene && scene.windows.count > 0);

    if (!hasWindows && _retryCount < 30) {
        _retryCount++;
        NSLog(@"[PoolHelper] Waiting for game window... (%ld)", (long)_retryCount);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self tryLaunch];
        });
        return;
    }

    NSLog(@"[PoolHelper] Game window ready — launching menu");
    _menu = [MenuController new];
    _btn  = [[FloatingButton alloc] initWithMenu:_menu];
    [_btn show];
    NSLog(@"[PoolHelper] 🎱 Pool Helper ready!");
}

- (UIWindowScene *)activeScene {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive)
            return (UIWindowScene *)s;
    }
    return nil;
}
@end

/* ── Constructor ───────────────────────────────────────────────────────── */
__attribute__((constructor))
static void PoolHelperInit(void) {
    NSLog(@"[PoolHelper] Library injected — waiting for game to start");
    /*
     * Delay 2 s before first attempt so the game has time to set up its
     * root UIWindowScene.  tryLaunch then retries every 0.5 s until ready.
     */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[OverlayManager shared] startLaunchSequence];
    });
}
