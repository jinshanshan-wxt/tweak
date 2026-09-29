#import <Foundation/Foundation.h>

// Compile and execute the actual remaining hook method, not a rewritten copy.
// UIKit rendering is deliberately out of scope for this callback-only test.
@interface UIView : NSObject
@property (nonatomic) BOOL hidden;
@end
@implementation UIView @end
@interface T1AnimatedLaunchScreenView : UIView
- (void)animateRevealWithCompletion:(id)completion;
@end
@implementation T1AnimatedLaunchScreenView
#include "LaunchMethod.inc"
@end

int main(void) {
    @autoreleasepool {
        T1AnimatedLaunchScreenView *view = [T1AnimatedLaunchScreenView new];
        __block NSUInteger callbacks = 0;
        [view animateRevealWithCompletion:^{ callbacks++; }];
        NSCAssert(view.hidden && callbacks == 1, @"Launch must finish synchronously");
        [view animateRevealWithCompletion:nil];
        NSCAssert(callbacks == 1, @"A nil completion must be harmless");
        [view animateRevealWithCompletion:^{ callbacks++; }];
        NSCAssert(callbacks == 2, @"Every host request completes exactly once");
        puts("PASS: no-animation fallback, synchronous completion and nil callback");
    }
}
