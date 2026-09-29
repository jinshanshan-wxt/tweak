#import "HookHelpers.h"

static BOOL NFBWebLoginEnabled(void) {
    return [BHTSettings boolForKey:@"nfb_web_login"] &&
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

%ctor {
    @autoreleasepool {
        if ([NSClassFromString(@"T1AccountsViewController") instancesRespondToSelector:@selector(private_startLoginFlowWithSender:)]) {
            %init(NFBAccountLogin);
        }
        if ([NSClassFromString(@"T1HostViewController") instancesRespondToSelector:@selector(makeOnboardingViewControllerWithOCFFallback:completion:)]) {
            %init(NFBInitialLogin1198);
        }
    }
}
