#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <Security/Security.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "../BHTBundle/BHTBundle.h"

// Only the private interfaces verified in the user's 11.98 base are declared.
@interface TFNTwitter : NSObject
+ (instancetype)sharedTwitter;
@property (readonly, nonatomic) NSArray *accounts;
@end
@interface T1HostViewController : UIViewController
+ (instancetype)sharedHostViewController;
- (id)currentAccount;
@end
@interface T1WebViewController : UIViewController
- (instancetype)initWithRootURL:(NSURL *)url account:(id)account
             shouldAuthenticate:(BOOL)authenticate shouldPresentAsNativePage:(BOOL)native
                   sourceStatus:(id)status scribeComponent:(id)component
               scribeParameters:(id)parameters;
@end
void prewarmWebCookiesIfNeeded(void);
id accountForAuthenticatedWebView(void);
BOOL isCookieLoginUserID(NSString *userID);

static inline BOOL NFBTrustedCookieDomain(NSString *domain) {
    NSString *host = domain.lowercaseString;
    while ([host hasPrefix:@"."]) host = [host substringFromIndex:1];
    return [host isEqualToString:@"x.com"] || [host hasSuffix:@".x.com"] ||
           [host isEqualToString:@"twitter.com"] || [host hasSuffix:@".twitter.com"];
}
