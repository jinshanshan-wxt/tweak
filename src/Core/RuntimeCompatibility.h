#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

// Upstream v7 also targets 12.x. Never install a replacement for a private
// selector absent from 11.98: its %orig trampoline would otherwise be NULL.
FOUNDATION_EXPORT void NFBHookExistingMessage(Class cls, SEL selector, IMP replacement, IMP *original);
#define MSHookMessageEx NFBHookExistingMessage
