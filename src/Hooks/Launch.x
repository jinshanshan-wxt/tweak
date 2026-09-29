#import "HookHelpers.h"

// One overlay per launch view, one cached glyph, one bounded transition.
// Do not run the original X mask animation against a bluebird resource pack.
static const void *NFBLaunchOverlayKey = &NFBLaunchOverlayKey;
static const void *NFBLaunchLogoKey = &NFBLaunchLogoKey;
static const void *NFBLaunchPendingKey = &NFBLaunchPendingKey;
static const void *NFBLaunchDoneKey = &NFBLaunchDoneKey;

static UIView *NFBPrepareLaunch(UIView *view) {
    UIView *overlay = objc_getAssociatedObject(view, NFBLaunchOverlayKey);
    if (overlay) return overlay;
    overlay = [[UIView alloc] initWithFrame:view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = [UIColor colorWithRed:29.0/255 green:155.0/255 blue:240.0/255 alpha:1];
    overlay.userInteractionEnabled = NO;
    static UIImage *bird;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if ([UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
            bird = [UIImage tfn_vectorImageNamed:@"twitter" fitsSize:CGSizeMake(76, 76)
                                      fillColor:UIColor.whiteColor];
        }
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
    objc_setAssociatedObject(view, NFBLaunchLogoKey, logo, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return overlay;
}

%hook T1AnimatedLaunchScreenView
- (void)didMoveToWindow {
    %orig;
    if (self.window && [BHTSettings boolForKey:@"blue_launch_screen"]) NFBPrepareLaunch((UIView *)self);
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
    NFBPrepareLaunch(view);
    UIImageView *logo = objc_getAssociatedObject(view, NFBLaunchLogoKey);
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    [UIView animateWithDuration:reduceMotion ? 0.15 : 0.28 delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn
                     animations:^{
                         if (!reduceMotion) logo.transform = CGAffineTransformMakeScale(9, 9);
                         view.alpha = 0;
                     } completion:^(__unused BOOL finished) {
                         objc_setAssociatedObject(view, NFBLaunchDoneKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                         NSArray *callbacks = [pending copy];
                         [pending removeAllObjects];
                         for (id callback in callbacks) ((void (^)(void))callback)();
                     }];
}
%end
