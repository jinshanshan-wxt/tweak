#import "Core/RuntimeCompatibility.h"
#undef MSHookMessageEx

void NFBHookExistingMessage(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (!cls || !class_getInstanceMethod(cls, selector)) {
        if (original) *original = NULL;
        return;
    }
    MSHookMessageEx(cls, selector, replacement, original);
}
