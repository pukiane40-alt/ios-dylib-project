/**
 * PoolHelperMenu.m
 *
 * iOS Dynamic Library — Pool Helper Menu (UI Demo)
 * Written in Objective-C using UIKit only.
 *
 * PURPOSE: Educational demonstration of a floating mod-style overlay menu UI.
 * This library adds a draggable floating button and a centered overlay menu
 * with toggle switches that only log messages to the console.
 *
 * COMPILE (ARM64 cross-compile example):
 *   clang -arch arm64 -isysroot /path/to/iPhoneOS.sdk \
 *         -framework UIKit -framework Foundation \
 *         -dynamiclib -o PoolHelperMenu.dylib PoolHelperMenu.m
 *
 * The constructor runs automatically when the dylib is loaded into a process.
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - Forward Declarations

@class MenuController;
@class OverlayManager;

#pragma mark - AimLineView

/**
 * AimLineView
 * A simple fullscreen transparent view that draws a demo aim line
 * from the bottom-center of the screen upward at a slight angle.
 */
@interface AimLineView : UIView
@end

@implementation AimLineView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGFloat w = rect.size.width;
    CGFloat h = rect.size.height;

    /* Dashed yellow aim line from bottom-center toward top-right */
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:1.0
                                                          green:0.85
                                                           blue:0.0
                                                          alpha:0.85].CGColor);
    CGContextSetLineWidth(ctx, 3.0);

    CGFloat dashPattern[] = {12.0, 6.0};
    CGContextSetLineDash(ctx, 0, dashPattern, 2);

    CGContextMoveToPoint(ctx, w * 0.5, h);
    CGContextAddLineToPoint(ctx, w * 0.72, h * 0.15);
    CGContextStrokePath(ctx);

    /* Draw a small circle at the projected endpoint */
    CGFloat cx = w * 0.72, cy = h * 0.15, r = 10.0;
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:1.0
                                                        green:0.85
                                                         blue:0.0
                                                        alpha:0.7].CGColor);
    CGContextSetLineDash(ctx, 0, NULL, 0);
    CGContextFillEllipseInRect(ctx, CGRectMake(cx - r, cy - r, r * 2, r * 2));
}

@end

#pragma mark - MenuController

/**
 * MenuController
 * Manages the centered overlay menu window with blur effect,
 * rounded corners, toggle switches, and a close button.
 * The window is draggable via a pan gesture.
 */
@interface MenuController : NSObject

@property (nonatomic, strong) UIView        *menuView;
@property (nonatomic, strong) UIWindow      *menuWindow;
@property (nonatomic, strong) AimLineView   *aimLineView;
@property (nonatomic, strong) UILabel       *debugLabel;
@property (nonatomic, assign) CGPoint        dragOffset;

- (void)showMenu;
- (void)hideMenu;
- (BOOL)isMenuVisible;

@end

@implementation MenuController

- (instancetype)init {
    self = [super init];
    if (self) {
        [self buildMenuWindow];
    }
    return self;
}

#pragma mark Build UI

- (void)buildMenuWindow {
    /* Create a dedicated UIWindow that floats above everything */
    UIWindowScene *scene = [self activeWindowScene];
    if (scene) {
        self->_menuWindow = [[UIWindow alloc] initWithWindowScene:scene];
    } else {
        self->_menuWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    }
    self->_menuWindow.windowLevel = UIWindowLevelAlert + 200;
    self->_menuWindow.backgroundColor = [UIColor clearColor];
    self->_menuWindow.userInteractionEnabled = YES;

    /* Transparent root view controller required to present the window */
    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.backgroundColor = [UIColor clearColor];
    self->_menuWindow.rootViewController = rootVC;

    /* ── Aim line overlay (fullscreen, behind menu) ─────────────────────── */
    self->_aimLineView = [[AimLineView alloc]
                          initWithFrame:UIScreen.mainScreen.bounds];
    self->_aimLineView.hidden = YES;
    [rootVC.view addSubview:self->_aimLineView];

    /* ── Debug label (top-left corner) ───────────────────────────────────── */
    self->_debugLabel = [[UILabel alloc]
                         initWithFrame:CGRectMake(10, 60, 300, 28)];
    self->_debugLabel.text = @"[DEBUG] Pool Helper — Active";
    self->_debugLabel.font = [UIFont monospacedSystemFontOfSize:13
                                                          weight:UIFontWeightMedium];
    self->_debugLabel.textColor = [UIColor colorWithRed:0.2
                                                  green:1.0
                                                   blue:0.4
                                                  alpha:1.0];
    self->_debugLabel.hidden = YES;
    [rootVC.view addSubview:self->_debugLabel];

    /* ── Menu panel ──────────────────────────────────────────────────────── */
    CGFloat menuW = 300.0, menuH = 380.0;
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGRect menuFrame = CGRectMake((screen.width  - menuW) / 2.0,
                                  (screen.height - menuH) / 2.0,
                                  menuW, menuH);
    self->_menuView = [[UIView alloc] initWithFrame:menuFrame];
    self->_menuView.layer.cornerRadius  = 18.0;
    self->_menuView.layer.masksToBounds = YES;
    self->_menuView.layer.borderColor   = [UIColor colorWithWhite:1.0
                                                            alpha:0.15].CGColor;
    self->_menuView.layer.borderWidth   = 1.0;

    /* Blur effect background */
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc]
                                    initWithEffect:blur];
    blurView.frame = self->_menuView.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                UIViewAutoresizingFlexibleHeight;
    [self->_menuView addSubview:blurView];

    /* Semi-transparent dark tint on top of blur */
    UIView *tint = [[UIView alloc] initWithFrame:self->_menuView.bounds];
    tint.backgroundColor = [UIColor colorWithRed:0.05
                                           green:0.05
                                            blue:0.12
                                           alpha:0.6];
    tint.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                            UIViewAutoresizingFlexibleHeight;
    [self->_menuView addSubview:tint];

    /* Content container (above blur+tint) */
    UIView *content = [[UIView alloc] initWithFrame:self->_menuView.bounds];
    content.backgroundColor = [UIColor clearColor];
    [self->_menuView addSubview:content];

    /* Title label */
    UILabel *title = [[UILabel alloc]
                      initWithFrame:CGRectMake(0, 16, menuW, 36)];
    title.text = @"POOL HELPER MENU";
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    title.textColor = [UIColor colorWithRed:0.3
                                      green:0.85
                                       blue:1.0
                                      alpha:1.0];
    [content addSubview:title];

    /* Subtitle / tag line */
    UILabel *subtitle = [[UILabel alloc]
                         initWithFrame:CGRectMake(0, 52, menuW, 20)];
    subtitle.text = @"UI DEMO";
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    subtitle.textColor = [UIColor colorWithWhite:1.0 alpha:0.35];
    [content addSubview:subtitle];

    /* Separator */
    UIView *sep = [[UIView alloc]
                   initWithFrame:CGRectMake(20, 78, menuW - 40, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
    [content addSubview:sep];

    /* Toggle rows */
    NSArray<NSDictionary *> *rows = @[
        @{ @"label": @"Auto Play",    @"tag": @(101) },
        @{ @"label": @"Auto Aim",     @"tag": @(102) },
        @{ @"label": @"Aim Line",     @"tag": @(103) },
        @{ @"label": @"Debug Overlay",@"tag": @(104) },
    ];

    CGFloat rowY = 92.0, rowH = 48.0;
    for (NSDictionary *row in rows) {
        [self addToggleRow:content
                     label:row[@"label"]
                       tag:[row[@"tag"] integerValue]
                         y:rowY
                     width:menuW];
        rowY += rowH;
    }

    /* Close button */
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, menuH - 60, menuW - 40, 40);
    closeBtn.layer.cornerRadius  = 10.0;
    closeBtn.layer.masksToBounds = YES;
    closeBtn.backgroundColor = [UIColor colorWithRed:0.85
                                               green:0.15
                                                blue:0.2
                                               alpha:0.85];
    [closeBtn setTitle:@"Close Menu" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:15
                                                  weight:UIFontWeightSemibold];
    [closeBtn addTarget:self
                 action:@selector(closeMenuTapped:)
       forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:closeBtn];

    /* Pool ball icon in title area */
    UILabel *icon = [[UILabel alloc]
                     initWithFrame:CGRectMake(menuW - 44, 14, 32, 32)];
    icon.text = @"🎱";
    icon.font = [UIFont systemFontOfSize:22];
    icon.textAlignment = NSTextAlignmentCenter;
    [content addSubview:icon];

    [rootVC.view addSubview:self->_menuView];

    /* Pan gesture for dragging the menu */
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(handleMenuPan:)];
    [self->_menuView addGestureRecognizer:pan];

    self->_menuView.hidden = YES;
    self->_menuView.alpha  = 0.0;
}

- (void)addToggleRow:(UIView *)parent
               label:(NSString *)labelText
                 tag:(NSInteger)tag
                   y:(CGFloat)y
               width:(CGFloat)w {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, w, 44)];
    row.backgroundColor = [UIColor clearColor];

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(20, 0, w - 90, 44)];
    lbl.text = labelText;
    lbl.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    lbl.textColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    [row addSubview:lbl];

    UISwitch *sw = [[UISwitch alloc] init];
    sw.onTintColor = [UIColor colorWithRed:0.2
                                     green:0.75
                                      blue:1.0
                                     alpha:1.0];
    sw.tag = tag;
    sw.on  = NO;
    CGFloat swW = sw.intrinsicContentSize.width;
    CGFloat swH = sw.intrinsicContentSize.height;
    sw.frame = CGRectMake(w - swW - 20,
                          (44 - swH) / 2.0,
                          swW, swH);
    [sw addTarget:self
           action:@selector(toggleChanged:)
 forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];

    /* Row separator */
    UIView *line = [[UIView alloc]
                    initWithFrame:CGRectMake(20, 43, w - 40, 0.5)];
    line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    [row addSubview:line];

    [parent addSubview:row];
}

#pragma mark Actions

- (void)toggleChanged:(UISwitch *)sw {
    NSString *name;
    switch (sw.tag) {
        case 101: name = @"Auto Play";     break;
        case 102: name = @"Auto Aim";      break;
        case 103: name = @"Aim Line";      break;
        case 104: name = @"Debug Overlay"; break;
        default:  name = @"Unknown";       break;
    }
    NSString *state = sw.on ? @"Enabled" : @"Disabled";
    NSLog(@"[PoolHelper] %@ %@", name, state);

    /* Special side-effects (visual only, no gameplay) */
    if (sw.tag == 103) {
        /* Aim Line: show/hide demo line overlay */
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_aimLineView.hidden = !sw.on;
        });
    }
    if (sw.tag == 104) {
        /* Debug Overlay: show/hide UILabel */
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_debugLabel.hidden = !sw.on;
        });
    }
}

- (void)closeMenuTapped:(UIButton *)sender {
    [self hideMenu];
}

#pragma mark Pan / Drag

- (void)handleMenuPan:(UIPanGestureRecognizer *)recognizer {
    UIView *view = recognizer.view;
    if (!view) return;

    CGPoint translation = [recognizer translationInView:view.superview];

    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self->_dragOffset = view.center;
    }

    CGFloat newX = self->_dragOffset.x + translation.x;
    CGFloat newY = self->_dragOffset.y + translation.y;

    /* Clamp so the menu stays on-screen */
    CGSize screen  = UIScreen.mainScreen.bounds.size;
    CGFloat halfW  = view.bounds.size.width  / 2.0;
    CGFloat halfH  = view.bounds.size.height / 2.0;
    newX = MAX(halfW,  MIN(newX, screen.width  - halfW));
    newY = MAX(halfH,  MIN(newY, screen.height - halfH));

    view.center = CGPointMake(newX, newY);
}

#pragma mark Show / Hide

- (void)showMenu {
    self->_menuWindow.hidden = NO;
    [self->_menuWindow makeKeyAndVisible];
    self->_menuView.hidden = NO;

    [UIView animateWithDuration:0.25
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self->_menuView.alpha  = 1.0;
        self->_menuView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hideMenu {
    [UIView animateWithDuration:0.2
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self->_menuView.alpha = 0.0;
        self->_menuView.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } completion:^(BOOL finished) {
        self->_menuView.hidden = YES;
    }];
}

- (BOOL)isMenuVisible {
    return !self->_menuView.hidden && self->_menuView.alpha > 0.01;
}

#pragma mark Helpers

- (UIWindowScene *)activeWindowScene {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] &&
            scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)scene;
        }
    }
    return nil;
}

@end

#pragma mark - FloatingButton

/**
 * FloatingButton
 * A small circular button that stays above all other views.
 * Tapping it opens/closes the menu; it can be dragged to reposition.
 */
@interface FloatingButton : NSObject

@property (nonatomic, strong) UIWindow         *floatWindow;
@property (nonatomic, strong) UIButton         *button;
@property (nonatomic, strong) MenuController   *menuController;
@property (nonatomic, assign) CGPoint           dragOffset;
@property (nonatomic, assign) BOOL              dragging;

- (void)show;

@end

@implementation FloatingButton

- (instancetype)initWithMenuController:(MenuController *)mc {
    self = [super init];
    if (self) {
        self->_menuController = mc;
        [self buildWindow];
    }
    return self;
}

- (void)buildWindow {
    UIWindowScene *scene = [self activeWindowScene];
    if (scene) {
        self->_floatWindow = [[UIWindow alloc] initWithWindowScene:scene];
    } else {
        self->_floatWindow = [[UIWindow alloc]
                               initWithFrame:UIScreen.mainScreen.bounds];
    }
    self->_floatWindow.windowLevel = UIWindowLevelAlert + 100;
    self->_floatWindow.backgroundColor = [UIColor clearColor];

    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.backgroundColor = [UIColor clearColor];
    self->_floatWindow.rootViewController = rootVC;

    /* Floating circular button */
    CGFloat size = 54.0;
    CGFloat margin = 20.0;
    CGSize screen = UIScreen.mainScreen.bounds.size;

    self->_button = [UIButton buttonWithType:UIButtonTypeCustom];
    self->_button.frame = CGRectMake(screen.width - size - margin,
                                     screen.height * 0.35,
                                     size, size);
    self->_button.layer.cornerRadius  = size / 2.0;
    self->_button.layer.masksToBounds = NO;
    self->_button.backgroundColor =
        [UIColor colorWithRed:0.08 green:0.08 blue:0.22 alpha:0.92];

    /* Drop shadow */
    self->_button.layer.shadowColor   = [UIColor blackColor].CGColor;
    self->_button.layer.shadowOffset  = CGSizeMake(0, 4);
    self->_button.layer.shadowRadius  = 8.0;
    self->_button.layer.shadowOpacity = 0.55;

    /* Gradient ring border */
    self->_button.layer.borderColor =
        [UIColor colorWithRed:0.3 green:0.75 blue:1.0 alpha:0.9].CGColor;
    self->_button.layer.borderWidth = 2.0;

    /* Pool ball emoji label */
    UILabel *ico = [[UILabel alloc] initWithFrame:self->_button.bounds];
    ico.text = @"🎱";
    ico.font = [UIFont systemFontOfSize:26];
    ico.textAlignment = NSTextAlignmentCenter;
    ico.userInteractionEnabled = NO;
    [self->_button addSubview:ico];

    [self->_button addTarget:self
                      action:@selector(buttonTapped:)
            forControlEvents:UIControlEventTouchUpInside];

    /* Pan gesture for dragging */
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(handlePan:)];
    [self->_button addGestureRecognizer:pan];

    [rootVC.view addSubview:self->_button];
}

- (void)show {
    self->_floatWindow.hidden = NO;
    [self->_floatWindow makeKeyAndVisible];

    /* Bounce-in animation */
    self->_button.transform = CGAffineTransformMakeScale(0.1, 0.1);
    self->_button.alpha = 0.0;
    [UIView animateWithDuration:0.45
                          delay:0.2
         usingSpringWithDamping:0.6
          initialSpringVelocity:0.8
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self->_button.transform = CGAffineTransformIdentity;
        self->_button.alpha = 1.0;
    } completion:nil];
}

#pragma mark Actions

- (void)buttonTapped:(UIButton *)sender {
    if (self->_dragging) return;

    if ([self->_menuController isMenuVisible]) {
        [self->_menuController hideMenu];
        NSLog(@"[PoolHelper] Menu closed via floating button");
    } else {
        [self->_menuController showMenu];
        NSLog(@"[PoolHelper] Menu opened via floating button");
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    UIView *view = recognizer.view;
    if (!view) return;

    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self->_dragOffset = view.center;
        self->_dragging   = YES;
    }

    CGPoint translation = [recognizer translationInView:view.superview];
    CGFloat newX = self->_dragOffset.x + translation.x;
    CGFloat newY = self->_dragOffset.y + translation.y;

    /* Clamp to screen */
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat half  = view.bounds.size.width / 2.0;
    newX = MAX(half,  MIN(newX, screen.width  - half));
    newY = MAX(half,  MIN(newY, screen.height - half));

    view.center = CGPointMake(newX, newY);

    if (recognizer.state == UIGestureRecognizerStateEnded ||
        recognizer.state == UIGestureRecognizerStateCancelled) {
        /* Small delay so tap action doesn't fire after a drag */
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(0.05 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            self->_dragging = NO;
        });
    }
}

#pragma mark Helpers

- (UIWindowScene *)activeWindowScene {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] &&
            scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)scene;
        }
    }
    return nil;
}

@end

#pragma mark - OverlayManager

/**
 * OverlayManager
 * Singleton that owns the FloatingButton and MenuController.
 * Entry point for the entire library overlay system.
 */
@interface OverlayManager : NSObject

+ (instancetype)sharedInstance;
- (void)launch;

@property (nonatomic, strong) MenuController *menuController;
@property (nonatomic, strong) FloatingButton *floatingButton;

@end

@implementation OverlayManager

+ (instancetype)sharedInstance {
    static OverlayManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OverlayManager alloc] init];
    });
    return instance;
}

- (void)launch {
    NSLog(@"[PoolHelper] OverlayManager launching — Pool Helper Menu (UI Demo)");

    self->_menuController = [[MenuController alloc] init];
    self->_floatingButton = [[FloatingButton alloc]
                              initWithMenuController:self->_menuController];
    [self->_floatingButton show];

    NSLog(@"[PoolHelper] Floating button added — tap it to open the menu.");
}

@end

#pragma mark - Library Constructor

/**
 * __attribute__((constructor)) causes this function to run automatically
 * as soon as the dynamic library is loaded into the target process.
 * All UI work is dispatched to the main thread.
 */
__attribute__((constructor))
static void PoolHelperMenuInit(void) {
    NSLog(@"[PoolHelper] Dynamic library loaded — initialising overlay...");

    dispatch_async(dispatch_get_main_queue(), ^{
        [[OverlayManager sharedInstance] launch];
    });
}
