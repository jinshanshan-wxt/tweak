// Selective 11.98 backport of orionblur/NeoFreeBird, not the 12.x application.
#import "WebLogin/HookHelpers.h"
#import "WebLogin/WebLoginViewController.h"

extern UIColor *BHTCurrentAccentColor(void);

static BOOL NFBWebLoginEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"nfb_web_login"] &&
           [WebLoginViewController isNativeBridgeAvailable];
}

%group NFBAccountLogin
%hook T1AccountsViewController
- (void)private_startLoginFlowWithSender:(id)sender {
    if (!NFBWebLoginEnabled()) {
        %orig;
        return;
    }
    [WebLoginViewController presentLoginFrom:(UIViewController *)self];
}
%end
%end

%group NFBInitialLogin1198
%hook T1HostViewController
- (void)makeOnboardingViewControllerWithOCFFallback:(id)fallback completion:(void (^)(id))completion {
    if (!completion || !NFBWebLoginEnabled()) {
        %orig;
        return;
    }
    completion([WebLoginViewController loginRootNavigationController]);
}
%end
%end

%group NFBInitialLoginNewer
%hook T1HostViewController
- (void)makeOnboardingViewControllerWithCompletion:(void (^)(id))completion {
    if (!completion || !NFBWebLoginEnabled()) {
        %orig;
        return;
    }
    completion([WebLoginViewController loginRootNavigationController]);
}
%end
%end

@interface UIImage (NFBVector)
+ (UIImage *)tfn_vectorImageNamed:(NSString *)name fitsSize:(CGSize)size fillColor:(UIColor *)color;
@end

%group NFBHomeBird
%hook _TtC11TwitterHome39HomeDefaultNavigationBarTitleViewPlugin
- (UIView *)titleView {
    UIView *view = %orig;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"nfb_classic_branding"] &&
        [view isKindOfClass:UIImageView.class]) {
        UIImageView *logo = (UIImageView *)view;
        CGSize size = logo.image ? logo.image.size : CGSizeMake(28, 28);
        if (size.width <= 0 || size.height <= 0) size = CGSizeMake(28, 28);
        UIColor *blue = [UIColor colorWithRed:29.0/255 green:155.0/255 blue:240.0/255 alpha:1];
        NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
        BOOL tintEnabled = [prefs objectForKey:@"color_twitter_icon_in_top_bar"] == nil ||
                           [prefs boolForKey:@"color_twitter_icon_in_top_bar"];
        UIColor *color = tintEnabled ? (BHTCurrentAccentColor() ?: blue) : blue;
        if ([UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
            UIImage *bird = [UIImage tfn_vectorImageNamed:@"twitter" fitsSize:size fillColor:color];
            if (bird) logo.image = [bird imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
        logo.tintColor = color;
    }
    return view;
}
%end
%end

%group NFBBirdLaunch
%hook T1AnimatedLaunchScreenView
- (void)layoutSubviews {
    %orig;
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"nfb_classic_branding"]) return;
    UIView *view = (UIView *)self;
    UIColor *blue = [UIColor colorWithRed:29.0/255 green:155.0/255 blue:240.0/255 alpha:1];
    view.backgroundColor = blue;
    view.layer.mask = nil;
    for (UIView *sub in view.subviews) {
        sub.backgroundColor = blue;
        sub.layer.mask = nil;
    }
}
%end
%end

%group NFBSessionLifecycle
%hook T1AppDelegate
- (void)applicationDidBecomeActive:(id)application {
    %orig;
    prewarmWebCookiesIfNeeded();
}
%end
%end

%ctor {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults registerDefaults:@{
            @"nfb_web_login": @YES, @"nfb_classic_branding": @YES
        }];
        Class host = NSClassFromString(@"T1HostViewController");
        if ([NSClassFromString(@"T1AccountsViewController") instancesRespondToSelector:@selector(private_startLoginFlowWithSender:)]) {
            %init(NFBAccountLogin);
        }
        if ([host instancesRespondToSelector:@selector(makeOnboardingViewControllerWithOCFFallback:completion:)]) {
            %init(NFBInitialLogin1198);
        } else if ([host instancesRespondToSelector:@selector(makeOnboardingViewControllerWithCompletion:)]) {
            %init(NFBInitialLoginNewer);
        }
        if ([NSClassFromString(@"_TtC11TwitterHome39HomeDefaultNavigationBarTitleViewPlugin") instancesRespondToSelector:@selector(titleView)]) {
            %init(NFBHomeBird);
        }
        if ([NSClassFromString(@"T1AnimatedLaunchScreenView") instancesRespondToSelector:@selector(layoutSubviews)]) {
            %init(NFBBirdLaunch);
        }
        if ([NSClassFromString(@"T1AppDelegate") instancesRespondToSelector:@selector(applicationDidBecomeActive:)]) {
            %init(NFBSessionLifecycle);
        }
    }
}
