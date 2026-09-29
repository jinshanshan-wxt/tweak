#import "Core/RuntimeCompatibility.h"
#undef MSHookMessageEx
#include <stdlib.h>
#include <string.h>
#import "Core/HookABI.h"

static BOOL NFBTypeMatches(const char *actual, const char *expected) {
    if (!actual || !expected) return NO;
    while (*actual && strchr("rnNoORV", *actual)) actual++;
    if (strcmp(expected, "boolean") == 0) return *actual == 'B' || *actual == 'c';
    // Signedness changes don't alter the 64-bit register ABI.
    if (strcmp(expected, "q") == 0 || strcmp(expected, "Q") == 0) return *actual == 'q' || *actual == 'Q';
    return strncmp(actual, expected, strlen(expected)) == 0;
}

static BOOL NFBMethodABICompatible(Class cls, SEL selector, Method method) {
    const char *name = class_getName(cls), *sel = sel_getName(selector);
    BOOL meta = class_isMetaClass(cls);
    for (NSUInteger i = 0; i < sizeof(NFBHookABIs) / sizeof(NFBHookABIs[0]); i++) {
        const NFBHookABI *abi = &NFBHookABIs[i];
        if (abi->classMethod != meta || strcmp(name, abi->className) || strcmp(sel, abi->selector)) continue;
        if (method_getNumberOfArguments(method) != abi->argumentCount + 2) return NO;
        char *type = method_copyReturnType(method);
        BOOL compatible = NFBTypeMatches(type, abi->returnKind);
        free(type);
        if (!compatible) return NO;
        for (unsigned int arg = 0; arg < abi->argumentCount; arg++) {
            type = method_copyArgumentType(method, arg + 2);
            compatible = NFBTypeMatches(type, abi->arguments[arg]);
            free(type);
            if (!compatible) return NO;
        }
        return YES;
    }
    return YES;
}

void NFBHookExistingMessage(Class cls, SEL selector, IMP replacement, IMP *original) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method || !NFBMethodABICompatible(cls, selector, method)) {
        if (original) *original = NULL;
        return;
    }
    MSHookMessageEx(cls, selector, replacement, original);
}
