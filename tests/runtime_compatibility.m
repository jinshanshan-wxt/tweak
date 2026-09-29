#import <Foundation/Foundation.h>
#import "Core/RuntimeCompatibility.h"
#undef MSHookMessageEx

static NSUInteger installs;
static void replacement(id object, SEL selector) {}
void MSHookMessageEx(Class cls, SEL selector, IMP newIMP, IMP *original) {
    installs++;
    if (original) *original = (IMP)replacement;
}
@interface NFBTestParent : NSObject
- (void)existing;
+ (void)existingClassMethod;
@end
@implementation NFBTestParent
- (void)existing {}
+ (void)existingClassMethod {}
@end
@interface NFBTestChild : NFBTestParent @end
@implementation NFBTestChild @end

int main(void) {
    @autoreleasepool {
        IMP original = (IMP)replacement;
        NFBHookExistingMessage(Nil, @selector(existing), (IMP)replacement, &original);
        NSCAssert(!original && installs == 0, @"Missing class must be skipped");
        NFBHookExistingMessage(NFBTestChild.class, NSSelectorFromString(@"absent12xSelector:"), (IMP)replacement, &original);
        NSCAssert(!original && installs == 0, @"Missing selector must be skipped");
        NFBHookExistingMessage(NFBTestChild.class, @selector(existing), (IMP)replacement, &original);
        NSCAssert(original && installs == 1, @"Inherited method must install");
        NFBHookExistingMessage(object_getClass(NFBTestChild.class), @selector(existingClassMethod), (IMP)replacement, &original);
        NSCAssert(original && installs == 2, @"Class method must install");
        puts("PASS: absent, inherited and class-method hook dispatch");
    }
}
