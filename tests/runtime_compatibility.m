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

// Names and selectors deliberately match real entries in the generated v7
// manifest, but emulate older versions with incompatible signatures.
@interface TFSTwitterUser : NSObject
- (BOOL)isBlueVerified;
- (BOOL)verified;
@end
@implementation TFSTwitterUser
- (BOOL)isBlueVerified { return YES; }
- (BOOL)verified { return YES; }
@end
@interface TFNAttributedTextView : NSObject
- (void)setTextModel:(NSInteger)model;
@end
@implementation TFNAttributedTextView
- (void)setTextModel:(NSInteger)model {}
@end

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
        NFBHookExistingMessage(TFSTwitterUser.class, @selector(isBlueVerified), (IMP)replacement, &original);
        NSCAssert(!original && installs == 2, @"Object vs BOOL return ABI must be skipped");
        NFBHookExistingMessage(TFNAttributedTextView.class, @selector(setTextModel:), (IMP)replacement, &original);
        NSCAssert(!original && installs == 2, @"Object vs integer argument ABI must be skipped");
        NFBHookExistingMessage(TFSTwitterUser.class, @selector(verified), (IMP)replacement, &original);
        NSCAssert(original && installs == 3, @"Compatible BOOL ABI must install");
        puts("PASS: absent, inherited, class-method and incompatible-ABI hook dispatch");
    }
}
