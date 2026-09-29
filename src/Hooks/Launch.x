#import "HookHelpers.h"
#import "Launch/NFBClassicLaunchSession.h"

static char NFBClassicLaunchSessionKey;

static NFBClassicLaunchSession *NFBLaunchSession(UIView *view) {
    NFBClassicLaunchSession *session = objc_getAssociatedObject(view, &NFBClassicLaunchSessionKey);
    if (!session && view.window && [BHTSettings boolForKey:@"classic_launch_animation"] &&
        !UIAccessibilityIsReduceMotionEnabled() && ![BHTSettings boolForKey:@"padlock"]) {
        static UIImage *bird;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            NSURL *url = [[BHTBundle sharedBundle] pathForFile:@"NFBLaunchMask.png"];
            bird = [UIImage imageWithContentsOfFile:url.path];
        });
        session = [[NFBClassicLaunchSession alloc] initWithLaunchView:view maskImage:bird];
        if (session) objc_setAssociatedObject(view, &NFBClassicLaunchSessionKey, session, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return session;
}

%hook T1AnimatedLaunchScreenView
- (void)didMoveToWindow {
    %orig;
    UIView *view = (UIView *)self;
    if (view.window) [NFBLaunchSession(view) updateForLaunchView];
    else [objc_getAssociatedObject(view, &NFBClassicLaunchSessionKey) finish];
}
- (void)layoutSubviews {
    %orig;
    [NFBLaunchSession((UIView *)self) updateForLaunchView];
}
- (void)animateRevealWithCompletion:(id)completion {
    // Verified 11.98 Swift-to-ObjC thunk: void (^)(void), NOT void (^)(BOOL).
    NFBClassicLaunchSession *session = NFBLaunchSession((UIView *)self);
    if (session) [session revealWithCompletion:(void (^)(void))completion];
    else {
        ((UIView *)self).hidden = YES;
        if (completion) ((void (^)(void))completion)();
    }
}
%end
