#import "HookHelpers.h"

// No custom launch UI or transition. The feature gate disables the animated
// launch view. If 11.98 still creates one from cached startup state, finish its
// native host callback immediately rather than falling back to the X reveal.
// The pinned 11.98 Swift-to-ObjC thunk accepts void (^)(void).
%hook T1AnimatedLaunchScreenView
- (void)animateRevealWithCompletion:(id)completion {
    ((UIView *)self).hidden = YES;
    if (completion) ((void (^)(void))completion)();
}
%end
