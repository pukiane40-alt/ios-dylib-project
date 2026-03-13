/**
 * PoolHelperMenu.m
 * iOS Dynamic Library — Pool Helper Menu (UI Demo)
 * Objective-C / UIKit only — ARM64
 *
 * FIX: Uses PassthroughWindow — a UIWindow subclass that overrides
 * hitTest:withEvent: so any touch on an empty area returns nil and
 * falls through to the game underneath. The game never freezes.
 *
 * Compile:
 *   clang -arch arm64 \
 *         -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
 *         -miphoneos-version-min=14.0 \
 *         -framework UIKit -framework Foundation \
 *         -dynamiclib -fobjc-arc \
 *         -install_name @rpath/PoolHelperMenu.dylib \
 *         -O2 -o PoolHelperMenu.dylib PoolHelperMenu.m
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

/* ─────────────────────────────────────────────────────────────────────────
   PassthroughWindow
   Overrides hitTest so that touches on transparent / empty regions pass
   straight through to whatever is below (the game).
   ───────────────────────────────────────────────────────────────────────── */
@interface PassthroughWindow : UIWindow
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    /* If the hit view IS the window itself or its bare root-vc view,
       return nil so the touch falls through to the game.              */
    if (hit == self || hit == self.rootViewController.view) {
        return nil;
    }
    return hit;
}

@end

/* ─────────────────────────────────────────────────────────────────────────
   AimLineView  — fullscreen transparent overlay, draws a demo aim line.
   userInteractionEnabled = NO so it never eats touches.
   ───────────────────────────────────────────────────────────────────────── */
@interface AimLineView : UIView
@end

@implementation AimLineView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor        = [UIColor clearColor];
        self.userInteractionEnabled = NO;   /* NEVER blocks game touches */
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    CGFloat w = rect.size.width, h = rect.size.height;

    /* Dashed yellow aim line */
    CGContextSetStrokeColorWithColor(ctx,
        [UIColor colorWithRed:1.0 green:0.85 blue:0.0 alpha:0.85].CGColor);
    CGContextSetLineWidth(ctx, 3.0);
    CGFloat dash[] = {12.0, 6.0};
    CGContextSetLineDash(ctx, 0, dash, 2);
    CGContextMoveToPoint(ctx, w * 0.5, h);
    CGContextAddLineToPoint(ctx, w * 0.72, h * 0.15);
    CGContextStrokePath(ctx);

    /* Endpoint circle */
    CGFloat cx = w * 0.72, cy = h * 0.15, r = 10.0;
    CGContextSetLineDash(ctx, 0, NULL, 0);
    CGContextSetFillColorWithColor(ctx,
        [UIColor colorWithRed:1.0 green:0.85 blue:0.0 alpha:0.7].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(cx-r, cy-r, r*2, r*2));
}

@end

/* ─────────────────────────────────────────────────────────────────────────
   MenuController
   ───────────────────────────────────────────────────────────────────────── */
@interface MenuController : NSObject
@property (nonatomic, strong) PassthroughWindow *menuWindow;
@property (nonatomic, strong) UIView            *menuView;
@property (nonatomic, strong) AimLineView       *aimLine;
@property (nonatomic, strong) UILabel           *debugLabel;
@property (nonatomic, assign) CGPoint            dragOffset;
- (void)show;
- (void)hide;
- (BOOL)isVisible;
@end

@implementation MenuController

- (instancetype)init {
    self = [super init];
    if (self) [self buildWindow];
    return self;
}

/* ── Build ──────────────────────────────────────────────────────────────── */

- (void)buildWindow {
    /* PassthroughWindow at a level above the game but below alerts */
    UIWindowScene *scene = [self activeScene];
    if (scene)
        _menuWindow = [[PassthroughWindow alloc] initWithWindowScene:scene];
    else
        _menuWindow = [[PassthroughWindow alloc]
                        initWithFrame:UIScreen.mainScreen.bounds];

    _menuWindow.windowLevel    = UIWindowLevelNormal + 100;
    _menuWindow.backgroundColor = [UIColor clearColor];

    /* Transparent root view controller */
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor       = [UIColor clearColor];
    /* CRITICAL: root view must NOT intercept touches */
    root.view.userInteractionEnabled = YES;
    _menuWindow.rootViewController   = root;

    CGSize screen = UIScreen.mainScreen.bounds.size;

    /* Aim line — behind everything, non-interactive */
    _aimLine = [[AimLineView alloc]
                initWithFrame:UIScreen.mainScreen.bounds];
    _aimLine.hidden = YES;
    [root.view addSubview:_aimLine];

    /* Debug label — non-interactive */
    _debugLabel = [[UILabel alloc] initWithFrame:CGRectMake(10,60,320,28)];
    _debugLabel.text      = @"[DEBUG] Pool Helper — Active";
    _debugLabel.font      = [UIFont monospacedSystemFontOfSize:13
                                                         weight:UIFontWeightMedium];
    _debugLabel.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0];
    _debugLabel.userInteractionEnabled = NO;
    _debugLabel.hidden = YES;
    [root.view addSubview:_debugLabel];

    /* Menu panel */
    CGFloat mw = 300, mh = 380;
    _menuView = [[UIView alloc]
                 initWithFrame:CGRectMake((screen.width-mw)/2,
                                         (screen.height-mh)/2,
                                         mw, mh)];
    _menuView.layer.cornerRadius  = 18;
    _menuView.layer.masksToBounds = YES;
    _menuView.layer.borderColor   = [UIColor colorWithWhite:1.0 alpha:0.15].CGColor;
    _menuView.layer.borderWidth   = 1;

    /* Blur */
    UIBlurEffect *blur = [UIBlurEffect
        effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *blurV = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurV.frame = _menuView.bounds;
    blurV.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                             UIViewAutoresizingFlexibleHeight;
    [_menuView addSubview:blurV];

    /* Dark tint */
    UIView *tint = [[UIView alloc] initWithFrame:_menuView.bounds];
    tint.backgroundColor = [UIColor colorWithRed:0.05 green:0.05
                                            blue:0.12 alpha:0.6];
    tint.autoresizingMask = blurV.autoresizingMask;
    [_menuView addSubview:tint];

    /* Content */
    UIView *content = [[UIView alloc] initWithFrame:_menuView.bounds];
    content.backgroundColor = [UIColor clearColor];
    [_menuView addSubview:content];

    /* Title */
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0,16,mw,36)];
    title.text          = @"POOL HELPER MENU";
    title.textAlignment = NSTextAlignmentCenter;
    title.font          = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    title.textColor     = [UIColor colorWithRed:0.3 green:0.85 blue:1.0 alpha:1.0];
    [content addSubview:title];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(0,52,mw,20)];
    sub.text          = @"UI DEMO";
    sub.textAlignment = NSTextAlignmentCenter;
    sub.font          = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    sub.textColor     = [UIColor colorWithWhite:1.0 alpha:0.35];
    [content addSubview:sub];

    UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(mw-44,14,32,32)];
    icon.text          = @"🎱";
    icon.font          = [UIFont systemFontOfSize:22];
    icon.textAlignment = NSTextAlignmentCenter;
    [content addSubview:icon];

    /* Separator */
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(20,78,mw-40,1)];
    sep.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
    [content addSubview:sep];

    /* Toggle rows */
    NSArray *rows = @[
        @{@"label":@"Auto Play",    @"tag":@(101)},
        @{@"label":@"Auto Aim",     @"tag":@(102)},
        @{@"label":@"Aim Line",     @"tag":@(103)},
        @{@"label":@"Debug Overlay",@"tag":@(104)},
    ];
    CGFloat rowY = 92;
    for (NSDictionary *row in rows) {
        [self addRow:content label:row[@"label"]
                 tag:[row[@"tag"] integerValue] y:rowY width:mw];
        rowY += 48;
    }

    /* Close button */
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(20, mh-60, mw-40, 40);
    close.layer.cornerRadius  = 10;
    close.layer.masksToBounds = YES;
    close.backgroundColor = [UIColor colorWithRed:0.85 green:0.15
                                             blue:0.2 alpha:0.85];
    [close setTitle:@"Close Menu" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [close addTarget:self action:@selector(hide)
    forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:close];

    /* Drag gesture on menu panel */
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(onMenuPan:)];
    [_menuView addGestureRecognizer:pan];

    [root.view addSubview:_menuView];

    _menuView.hidden    = YES;
    _menuView.alpha     = 0;
    _menuWindow.hidden  = NO;
    [_menuWindow makeKeyAndVisible];
    /* Give key status back to the game's window immediately */
    [self resignKey];
}

- (void)addRow:(UIView *)parent label:(NSString *)text
           tag:(NSInteger)tag y:(CGFloat)y width:(CGFloat)w {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0,y,w,44)];
    row.backgroundColor = [UIColor clearColor];

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(20,0,w-90,44)];
    lbl.text      = text;
    lbl.font      = [UIFont systemFontOfSize:15];
    lbl.textColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    [row addSubview:lbl];

    UISwitch *sw = [UISwitch new];
    sw.onTintColor = [UIColor colorWithRed:0.2 green:0.75 blue:1.0 alpha:1.0];
    sw.tag = tag;
    sw.on  = NO;
    CGSize ss = sw.intrinsicContentSize;
    sw.frame = CGRectMake(w-ss.width-20, (44-ss.height)/2, ss.width, ss.height);
    [sw addTarget:self action:@selector(onToggle:)
 forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(20,43,w-40,0.5)];
    line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    [row addSubview:line];

    [parent addSubview:row];
}

/* ── Actions ────────────────────────────────────────────────────────────── */

- (void)onToggle:(UISwitch *)sw {
    NSString *name;
    switch (sw.tag) {
        case 101: name = @"Auto Play";      break;
        case 102: name = @"Auto Aim";       break;
        case 103: name = @"Aim Line";       break;
        case 104: name = @"Debug Overlay";  break;
        default:  name = @"Unknown";        break;
    }
    NSLog(@"[PoolHelper] %@ %@", name, sw.on ? @"Enabled" : @"Disabled");

    if (sw.tag == 103) {
        _aimLine.hidden = !sw.on;
        [_aimLine setNeedsDisplay];
    }
    if (sw.tag == 104) {
        _debugLabel.hidden = !sw.on;
    }
}

- (void)onMenuPan:(UIPanGestureRecognizer *)gr {
    UIView *v = gr.view, *p = v.superview;
    if (!p) return;
    if (gr.state == UIGestureRecognizerStateBegan)
        _dragOffset = v.center;
    CGPoint t = [gr translationInView:p];
    CGFloat hw = v.bounds.size.width/2, hh = v.bounds.size.height/2;
    CGSize  sz = p.bounds.size;
    v.center = CGPointMake(
        MAX(hw, MIN(_dragOffset.x + t.x, sz.width  - hw)),
        MAX(hh, MIN(_dragOffset.y + t.y, sz.height - hh))
    );
}

/* ── Show / Hide ────────────────────────────────────────────────────────── */

- (void)show {
    _menuView.hidden    = NO;
    _menuView.transform = CGAffineTransformMakeScale(0.92, 0.92);
    [UIView animateWithDuration:0.22
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self->_menuView.alpha     = 1;
        self->_menuView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hide {
    [UIView animateWithDuration:0.18
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self->_menuView.alpha     = 0;
        self->_menuView.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } completion:^(BOOL done) {
        self->_menuView.hidden = YES;
    }];
}

- (BOOL)isVisible { return !_menuView.hidden && _menuView.alpha > 0.01; }

/* ── Helpers ────────────────────────────────────────────────────────────── */

/* Return key window status to the game so it receives input normally */
- (void)resignKey {
    for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w != _menuWindow) { [w makeKeyWindow]; return; }
        }
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

/* ─────────────────────────────────────────────────────────────────────────
   FloatingButton  — lives in its own PassthroughWindow above the game.
   ───────────────────────────────────────────────────────────────────────── */
@interface FloatingButton : NSObject
@property (nonatomic, strong) PassthroughWindow *floatWindow;
@property (nonatomic, strong) UIButton          *button;
@property (nonatomic, strong) MenuController    *menu;
@property (nonatomic, assign) CGPoint            dragStart;
@property (nonatomic, assign) CGPoint            centerStart;
@property (nonatomic, assign) BOOL               dragged;
- (instancetype)initWithMenu:(MenuController *)menu;
- (void)show;
@end

@implementation FloatingButton

- (instancetype)initWithMenu:(MenuController *)mc {
    self = [super init];
    if (self) { _menu = mc; [self build]; }
    return self;
}

- (void)build {
    UIWindowScene *scene = [self activeScene];
    if (scene)
        _floatWindow = [[PassthroughWindow alloc] initWithWindowScene:scene];
    else
        _floatWindow = [[PassthroughWindow alloc]
                         initWithFrame:UIScreen.mainScreen.bounds];

    _floatWindow.windowLevel    = UIWindowLevelNormal + 200;
    _floatWindow.backgroundColor = [UIColor clearColor];

    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor clearColor];
    _floatWindow.rootViewController = root;

    CGFloat sz  = 52, margin = 16;
    CGSize  scr = UIScreen.mainScreen.bounds.size;

    _button = [UIButton buttonWithType:UIButtonTypeCustom];
    _button.frame = CGRectMake(scr.width - sz - margin,
                               scr.height * 0.38, sz, sz);
    _button.layer.cornerRadius  = sz / 2;
    _button.layer.masksToBounds = NO;
    _button.backgroundColor =
        [UIColor colorWithRed:0.08 green:0.08 blue:0.20 alpha:0.92];
    _button.layer.borderColor =
        [UIColor colorWithRed:0.3 green:0.75 blue:1.0 alpha:0.9].CGColor;
    _button.layer.borderWidth   = 2;
    _button.layer.shadowColor   = [UIColor blackColor].CGColor;
    _button.layer.shadowOffset  = CGSizeMake(0, 4);
    _button.layer.shadowRadius  = 8;
    _button.layer.shadowOpacity = 0.55;

    UILabel *ico = [[UILabel alloc] initWithFrame:_button.bounds];
    ico.text          = @"🎱";
    ico.font          = [UIFont systemFontOfSize:26];
    ico.textAlignment = NSTextAlignmentCenter;
    ico.userInteractionEnabled = NO;
    [_button addSubview:ico];

    [_button addTarget:self action:@selector(onTap:)
      forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(onPan:)];
    [_button addGestureRecognizer:pan];

    [root.view addSubview:_button];
}

- (void)show {
    _floatWindow.hidden = NO;
    [_floatWindow makeKeyAndVisible];
    /* Give key-window back to the game immediately */
    [self resignKey];

    _button.alpha     = 0;
    _button.transform = CGAffineTransformMakeScale(0.1, 0.1);
    [UIView animateWithDuration:0.4
                          delay:0
         usingSpringWithDamping:0.6
          initialSpringVelocity:0.8
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self->_button.alpha     = 1;
        self->_button.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)onTap:(UIButton *)sender {
    if (_dragged) return;
    if ([_menu isVisible]) [_menu hide];
    else                   [_menu show];
}

- (void)onPan:(UIPanGestureRecognizer *)gr {
    UIView *v = gr.view, *p = v.superview;
    if (!p) return;
    if (gr.state == UIGestureRecognizerStateBegan) {
        _dragStart   = [gr locationInView:p];
        _centerStart = v.center;
        _dragged     = NO;
    }
    CGPoint cur = [gr locationInView:p];
    CGFloat dx = cur.x - _dragStart.x, dy = cur.y - _dragStart.y;
    if (fabs(dx) > 4 || fabs(dy) > 4) _dragged = YES;
    if (_dragged) {
        CGFloat hw = v.bounds.size.width/2, hh = v.bounds.size.height/2;
        CGSize  sz = p.bounds.size;
        v.center = CGPointMake(
            MAX(hw, MIN(_centerStart.x+dx, sz.width -hw)),
            MAX(hh, MIN(_centerStart.y+dy, sz.height-hh))
        );
    }
    if (gr.state == UIGestureRecognizerStateEnded ||
        gr.state == UIGestureRecognizerStateCancelled) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(0.05*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ self->_dragged = NO; });
    }
}

- (void)resignKey {
    for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w != _floatWindow && w != _menu.menuWindow) {
                [w makeKeyWindow]; return;
            }
        }
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

/* ─────────────────────────────────────────────────────────────────────────
   OverlayManager  — singleton entry point
   ───────────────────────────────────────────────────────────────────────── */
@interface OverlayManager : NSObject
+ (instancetype)shared;
- (void)launch;
@end

@implementation OverlayManager {
    MenuController *_menu;
    FloatingButton *_btn;
}

+ (instancetype)shared {
    static OverlayManager *inst;
    static dispatch_once_t tok;
    dispatch_once(&tok, ^{ inst = [OverlayManager new]; });
    return inst;
}

- (void)launch {
    NSLog(@"[PoolHelper] OverlayManager launching");
    _menu = [MenuController new];
    _btn  = [[FloatingButton alloc] initWithMenu:_menu];
    [_btn show];
    NSLog(@"[PoolHelper] Ready — game input unblocked.");
}

@end

/* ─────────────────────────────────────────────────────────────────────────
   Constructor — runs when dylib is loaded
   ───────────────────────────────────────────────────────────────────────── */
__attribute__((constructor))
static void PoolHelperInit(void) {
    NSLog(@"[PoolHelper] Library loaded");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[OverlayManager shared] launch];
    });
}
