#import "HookHelpers.h"
#import <QuartzCore/QuartzCore.h>

// The 11.98 native layout creates an X-shaped reveal mask. Own the classic
// layout instead: a small build-time PNG, no zoom and no native reveal subtree.
static const void *NFBLaunchOverlayKey = &NFBLaunchOverlayKey;
static const void *NFBLaunchPendingKey = &NFBLaunchPendingKey;
static const void *NFBLaunchDoneKey = &NFBLaunchDoneKey;

static void NFBClearLaunchLayers(CALayer *layer) {
    [layer removeAllAnimations];
    layer.mask = nil;
    for (CALayer *child in [layer.sublayers copy]) NFBClearLaunchLayers(child);
}

static UIView *NFBPrepareLaunch(UIView *view) {
    UIView *overlay = objc_getAssociatedObject(view, NFBLaunchOverlayKey);
    if (overlay || [objc_getAssociatedObject(view, NFBLaunchDoneKey) boolValue]) return overlay;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    NFBClearLaunchLayers(view.layer);
    for (UIView *subview in view.subviews) subview.hidden = YES;
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    view.layer.allowsGroupOpacity = NO;
    overlay = [[UIView alloc] initWithFrame:view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = [UIColor colorWithRed:29.0/255 green:155.0/255 blue:240.0/255 alpha:1];
    overlay.userInteractionEnabled = NO;
    overlay.layer.allowsGroupOpacity = NO;
    static UIImage *bird;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *url = [[BHTBundle sharedBundle] pathForFile:@"NFBLaunchBird@3x.png"];
        if (url.path) bird = [UIImage imageWithContentsOfFile:url.path];
    });
    UIImageView *logo = [[UIImageView alloc] initWithImage:bird];
    logo.contentMode = UIViewContentModeScaleAspectFit;
    logo.frame = CGRectMake((overlay.bounds.size.width - 76) / 2,
                            (overlay.bounds.size.height - 76) / 2, 76, 76);
    logo.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                           UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [overlay addSubview:logo];
    [view addSubview:overlay];
    objc_setAssociatedObject(view, NFBLaunchOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [CATransaction commit];
    return overlay;
}

static void NFBFinishLaunch(UIView *view) {
    if ([objc_getAssociatedObject(view, NFBLaunchDoneKey) boolValue]) return;
    objc_setAssociatedObject(view, NFBLaunchDoneKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *overlay = objc_getAssociatedObject(view, NFBLaunchOverlayKey);
    [overlay removeFromSuperview];
    objc_setAssociatedObject(view, NFBLaunchOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSMutableArray *pending = objc_getAssociatedObject(view, NFBLaunchPendingKey);
    NSArray *callbacks = [pending copy];
    [pending removeAllObjects];
    objc_setAssociatedObject(view, NFBLaunchPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Verified against the pinned 11.98 Swift-to-ObjC thunk: void (^)(void).
    for (id callback in callbacks) ((void (^)(void))callback)();
}

%hook T1AnimatedLaunchScreenView
- (void)didMoveToWindow {
    %orig;
    UIView *view = (UIView *)self;
    if (view.window && [BHTSettings boolForKey:@"blue_launch_screen"]) NFBPrepareLaunch(view);
    // Interrupted transitions must still release the host's completion.
    if (!view.window && objc_getAssociatedObject(view, NFBLaunchPendingKey)) NFBFinishLaunch(view);
}

- (void)layoutSubviews {
    if (![BHTSettings boolForKey:@"blue_launch_screen"]) {
        %orig;
        return;
    }
    // Never let the native layout re-install its X mask over our overlay.
    NFBPrepareLaunch((UIView *)self);
}

- (void)animateRevealWithCompletion:(id)completion {
    if (![BHTSettings boolForKey:@"blue_launch_screen"]) {
        %orig;
        return;
    }
    UIView *view = (UIView *)self;
    if ([objc_getAssociatedObject(view, NFBLaunchDoneKey) boolValue]) {
        if (completion) ((void (^)(void))completion)();
        return;
    }
    NSMutableArray *pending = objc_getAssociatedObject(view, NFBLaunchPendingKey);
    if (pending) {
        if (completion) [pending addObject:[completion copy]];
        return;
    }
    pending = [NSMutableArray array];
    if (completion) [pending addObject:[completion copy]];
    objc_setAssociatedObject(view, NFBLaunchPendingKey, pending, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *overlay = NFBPrepareLaunch(view);
    if (!view.window || UIAccessibilityIsReduceMotionEnabled() ||
        [BHTSettings boolForKey:@"disable_launch_transition"]) {
        NFBFinishLaunch(view);
        return;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [CATransaction setCompletionBlock:^{ NFBFinishLaunch(view); }];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @1;
    fade.toValue = @0;
    fade.duration = 0.18;
    fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    overlay.layer.opacity = 0;
    [overlay.layer addAnimation:fade forKey:@"nfb.launch.fade"];
    [CATransaction commit];
}
%end
