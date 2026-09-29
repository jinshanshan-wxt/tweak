//
//  WebLoginViewController.m
//  NeoFreeBird
//

#import "WebLoginViewController.h"
#import <WebKit/WebKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Hooks/HookHelpers.h"

// Implemented in WebCreateTweet.x: seed the web-session cache for `userID` and mark it
// a cookie-login account so its native calls get re-signed with these cookies.
extern void webLoginDidCaptureCookies(NSString* userID, NSString* username,
                                      NSDictionary<NSString*, NSString*>* cookiePairs);

static NSString* const kWebLoginUserAgent =
    @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like "
    @"Gecko) Version/17.4 Mobile/15E148 Safari/604.1";

// Pulls the numeric account id out of the twid cookie ("u=<id>", percent-encoded) and
// the screen name out of the loaded page. Posts one of:
//   "username:<handle>"        -> success, both id and handle resolved
//   "userid:<id>"              -> id resolved, handle not found yet (keep polling)
//   ""                         -> no session yet
static NSString* const kWebLoginScannerJS =
    @"(function(){"
     "var uid='';"
     "var m=document.cookie.match(/twid=u(?:%3D|=)(\\d+)/);"
     "if(m&&m[1]){uid=m[1];}"
     "if(!uid){return '';}"
     "function findHandle(text){"
     "if(!text)return null;"
     "var idx=text.indexOf(uid);"
     "if(idx===-1)return null;"
     "var sub=text.substring(Math.max(0,idx-1200),Math.min(text.length,idx+1200));"
     "var pats=[/\"screen_name\"\\s*:\\s*\"([a-zA-Z0-9_]{1,15})\"/g,"
     "/\"screenName\"\\s*:\\s*\"([a-zA-Z0-9_]{1,15})\"/g];"
     "for(var p=0;p<pats.length;p++){var mm;pats[p].lastIndex=0;"
     "while((mm=pats[p].exec(sub))!==null){var u=mm[1];"
     "if(!/^(home|explore|notifications|messages|settings|search|i|compose|login|signup|intent)$/i."
     "test(u))return u;}}"
     "return null;"
     "}"
     "try{if(window.__INITIAL_STATE__){var u=findHandle(JSON.stringify(window.__INITIAL_STATE__));"
     "if(u)return 'username:'+u;}}catch(e){}"
     "try{var s=document.getElementsByTagName('script');"
     "for(var i=0;i<s.length;i++){var u=findHandle(s[i].textContent||'');"
     "if(u)return 'username:'+u;}}catch(e){}"
     "return 'userid:'+uid;"
     "})();";

static id performShared(id target, SEL selector) {
    if (!target || ![target respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static NSString* stringOrEmpty(NSString* value) { return value ?: @""; }

@interface WebLoginViewController () <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView* webView;
@property (nonatomic, strong) NSTimer* pollTimer;
@property (nonatomic, assign) BOOL asRootScreen;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL checkingSession;
@property (nonatomic, assign) BOOL cancelled;
@end

@implementation WebLoginViewController

#pragma mark - Presentation

+ (BOOL)isNativeBridgeAvailable {
    @try {
    Class cls = NSClassFromString(@"TFNTwitterAccount");
    id twitter = performShared(NSClassFromString(@"TFNTwitter"), @selector(sharedTwitter));
    id service = performShared(twitter, @selector(accountService));
    id host = performShared(NSClassFromString(@"T1HostViewController"), @selector(sharedHostViewController));
    return [cls instancesRespondToSelector:@selector(initWithUsername:userID:)] &&
           [cls instancesRespondToSelector:@selector(updateUserInfoAndCredentialsWithToken:secret:username:)] &&
           [service respondsToSelector:@selector(addAccount:)] &&
           [host respondsToSelector:@selector(viewAccount:animated:)];
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

+ (BOOL)bht_isOurs:(UIViewController*)vc {
    if ([vc isKindOfClass:[WebLoginViewController class]]) {
        return YES;
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        id root = ((UINavigationController*)vc).viewControllers.firstObject;
        return [root isKindOfClass:[WebLoginViewController class]];
    }
    return NO;
}

+ (void)presentLoginFrom:(UIViewController*)presenter {
    if (!presenter || ![self isNativeBridgeAvailable]) {
        return;
    }
    for (UIViewController* vc = presenter; vc; vc = vc.presentedViewController) {
        if ([self bht_isOurs:vc]) {
            return;
        }
    }
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }

    WebLoginViewController* login = [[WebLoginViewController alloc] init];
    UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:login];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [presenter presentViewController:nav animated:YES completion:nil];
}

+ (UINavigationController*)loginRootNavigationController {
    WebLoginViewController* login = [[WebLoginViewController alloc] init];
    login.asRootScreen = YES;
    return [[UINavigationController alloc] initWithRootViewController:login];
}

#pragma mark - View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = [[BHTBundle sharedBundle] localizedStringForKey:@"LOG_IN_TITLE"];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"NFB_NATIVE_LOGIN"]
        style:UIBarButtonItemStylePlain target:self action:@selector(nativeLoginTapped)];

    if (!self.asRootScreen) {
        self.navigationItem.leftBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                          target:self
                                                          action:@selector(cancelTapped)];
    }

    WKWebViewConfiguration* cfg = [[WKWebViewConfiguration alloc] init];
    // Make sure the webview is always logged out, otherwise it'll duplicate the existing session
    cfg.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:cfg];
    self.webView.navigationDelegate = self;
    self.webView.customUserAgent = kWebLoginUserAgent;
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.webView];

    NSURL* url = [NSURL URLWithString:@"https://x.com/login"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];

    __weak WebLoginViewController *weakSelf = self;
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(__unused NSTimer *timer) {
        [weakSelf checkForSession];
    }];
}

- (void)dealloc {
    [_pollTimer invalidate];
}

- (void)cancelTapped {
    self.cancelled = YES;
    [self.pollTimer invalidate];
    self.pollTimer = nil;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)nativeLoginTapped {
    self.cancelled = YES;
    [self.pollTimer invalidate];
    self.pollTimer = nil;
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"nfb_web_login"];
    [self.webView stopLoading];
    if (!self.asRootScreen) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已切回原生登录"
        message:@"请从后台关闭并重新打开 Twitter，即可进入原生登录。此操作不会删除已有账号。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Navigation delegate

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation {
    [self checkForSession];
}

#pragma mark - Session capture

- (void)checkForSession {
    if (self.finished || self.cancelled || self.checkingSession) {
        return;
    }

    WKWebView* webView = self.webView;
    self.checkingSession = YES;
    [webView.configuration.websiteDataStore.httpCookieStore
        getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
            if (self.cancelled || self.finished) { self.checkingSession = NO; return; }
            NSString *authToken = nil, *ct0 = nil, *twid = nil, *authMulti = nil;
            for (NSHTTPCookie* cookie in cookies) {
                NSString* domain = cookie.domain ?: @"";
                if (!NFBTrustedCookieDomain(domain)) {
                    continue;
                }
                if (cookie.value.length == 0) {
                    continue;
                }
                if ([cookie.name isEqualToString:@"auth_token"]) {
                    authToken = cookie.value;
                } else if ([cookie.name isEqualToString:@"ct0"]) {
                    ct0 = cookie.value;
                } else if ([cookie.name isEqualToString:@"twid"]) {
                    twid = cookie.value;
                } else if ([cookie.name isEqualToString:@"auth_multi"]) {
                    authMulti = cookie.value;
                }
            }

            // A complete session needs all three. ct0 sometimes lands a beat after
            // auth_token; the poll timer retries until it does.
            if (authToken.length == 0 || ct0.length == 0 || twid.length == 0) {
                self.checkingSession = NO;
                return;
            }

            [webView evaluateJavaScript:kWebLoginScannerJS
                      completionHandler:^(id result, __unused NSError* error) {
                          self.checkingSession = NO;
                          if (self.cancelled || self.finished) return;
                          NSString* userID = [self userIDFromTwid:twid];
                          if (userID.length == 0) {
                              return;
                          }

                          NSString* username = nil;
                          if ([result isKindOfClass:[NSString class]] &&
                              [(NSString*)result hasPrefix:@"username:"]) {
                              username = [(NSString*)result substringFromIndex:9];
                          }

                          [self finishWithUserID:userID
                                        username:username
                                       authToken:authToken
                                             ct0:ct0
                                            twid:twid
                                       authMulti:authMulti];
                      }];
        }];
}

// Copy the webview's cookies into the shared NSHTTPCookieStorage so the app's own
// NSURLSession stack (and WebCreateTweet.x's harvestSharedCookies) can read them.
- (void)syncCookies:(NSArray<NSHTTPCookie*>*)cookies {
    NSHTTPCookieStorage* storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie* cookie in cookies) {
        NSString* domain = cookie.domain ?: @"";
        if (!NFBTrustedCookieDomain(domain)) {
            continue;
        }
        [storage setCookie:cookie];
    }
}

- (NSString*)userIDFromTwid:(NSString*)twid {
    if (twid.length == 0) {
        return nil;
    }
    NSString* decoded = [twid stringByRemovingPercentEncoding] ?: twid;
    NSCharacterSet* nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSString* digits =
        [[decoded componentsSeparatedByCharactersInSet:nonDigits] componentsJoinedByString:@""];
    return digits.length ? digits : nil;
}

- (void)finishWithUserID:(NSString*)userID
                username:(NSString*)username
               authToken:(NSString*)authToken
                     ct0:(NSString*)ct0
                    twid:(NSString*)twid
               authMulti:(NSString*)authMulti {
    if (self.finished || self.cancelled) {
        return;
    }
    self.finished = YES;
    [self.pollTimer invalidate];
    self.pollTimer = nil;

    NSMutableDictionary<NSString*, NSString*>* pairs = [NSMutableDictionary dictionary];
    pairs[@"auth_token"] = authToken;
    pairs[@"ct0"] = ct0;
    pairs[@"twid"] = twid;
    if (authMulti.length) {
        pairs[@"auth_multi"] = authMulti;
    }

    id account = [self registerNativeAccountForUserID:userID username:username authToken:authToken];
    if (!account) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"登录未完成"
            message:@"网页登录已成功，但无法在 11.98 中保存账号。请取消后重试；已有账号未受影响。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    // Do not persist a cookie-login session unless native registration succeeded.
    webLoginDidCaptureCookies(userID, username, pairs);

    void (^switchAndDismiss)(void) = ^{
        [self switchToAccount:account];
        UIViewController* presenting = self.presentingViewController;
        if (presenting) {
            [presenting dismissViewControllerAnimated:YES completion:nil];
        }
    };
    dispatch_async(dispatch_get_main_queue(), switchAndDismiss);
}

#pragma mark - Native account registration

// Register a dummy OAuth1 account in the native store so any code that reads the account's oauth token
// still recovers the correct userID.
- (id)registerNativeAccountForUserID:(NSString*)userID
                            username:(NSString*)username
                           authToken:(NSString*)authToken {
    Class accountCls = objc_getClass("TFNTwitterAccount");
    if (!accountCls || ![WebLoginViewController isNativeBridgeAvailable]) {
        return nil;
    }

    long long uid = userID.longLongValue;
    if (uid <= 0) return nil;

    // Reuse an explicitly re-authenticated account without creating a duplicate.
    id existing = [self existingAccountForUserID:uid];
    id account = existing;
    @try {
        if (!account) {
            account = ((id (*)(id, SEL, id, long long))objc_msgSend)(
                [accountCls alloc], @selector(initWithUsername:userID:), username ?: userID, uid);
        }
    } @catch (__unused NSException *exception) {
        return nil;
    }
    if (!account) {
        return nil;
    }

    // Stamp a placeholder credential in the native "<userID>-<token>" shape so any code
    // that parses the account's oauth token still recovers the correct userID.
    if ([account respondsToSelector:@selector(updateUserInfoAndCredentialsWithToken:secret:username:)]) {
        // A non-secret marker lets the wire hook distinguish cookie login from a
        // subsequent genuine native OAuth login for the same user ID.
        NSString* placeholderToken = [NSString stringWithFormat:@"%@-nfb-cookie-login", userID];
        @try {
            ((void (*)(id, SEL, id, id, id))objc_msgSend)(
                account, @selector(updateUserInfoAndCredentialsWithToken:secret:username:),
                placeholderToken, @"nfb-cookie-login", username ?: [account valueForKey:@"username"] ?: userID);
        } @catch (__unused NSException* exception) {
            return nil;
        }
    }

    if (existing) {
        @try {
            Class twitterClass = NSClassFromString(@"TFNTwitter");
            if ([twitterClass respondsToSelector:@selector(saveSharedTwitter)]) {
                ((void (*)(id, SEL))objc_msgSend)(twitterClass, @selector(saveSharedTwitter));
            }
        } @catch (__unused NSException *exception) { return nil; }
        return account;
    }
    return [self addAccountToStore:account] ? account : nil;
}

- (id)existingAccountForUserID:(long long)uid {
    if (uid == 0) {
        return nil;
    }
    @try {
        id shared = performShared(objc_getClass("TFNTwitter"), @selector(sharedTwitter));
        id accounts = performShared(shared, @selector(accounts));
        if ([accounts isKindOfClass:[NSArray class]]) {
            for (id acct in accounts) {
                if ([acct respondsToSelector:@selector(userID)] &&
                    ((long long (*)(id, SEL))objc_msgSend)(acct, @selector(userID)) == uid) {
                    return acct;
                }
            }
        }
    } @catch (__unused NSException* exception) {
    }
    return nil;
}

- (BOOL)addAccountToStore:(id)account {
    if (!account) {
        return NO;
    }
    @try {
        Class twitterCls = objc_getClass("TFNTwitter");
        id shared = performShared(twitterCls, @selector(sharedTwitter));
        id service = performShared(shared, @selector(accountService));

        if (service && [service respondsToSelector:@selector(addAccount:)]) {
            ((void (*)(id, SEL, id))objc_msgSend)(service, @selector(addAccount:), account);
        } else {
            return NO;
        }
        if ([twitterCls respondsToSelector:@selector(saveSharedTwitter)]) {
            ((void (*)(id, SEL))objc_msgSend)(twitterCls, @selector(saveSharedTwitter));
        }

        Class notifCls = objc_getClass("TFSAccountNotification");
        id name = performShared(notifCls, @selector(TFSAccountsDidChange));
        if ([name isKindOfClass:[NSString class]]) {
            [[NSNotificationCenter defaultCenter] postNotificationName:name
                                                                object:shared
                                                              userInfo:nil];
        }
    } @catch (__unused NSException* exception) {
        return NO;
    }
    return [self existingAccountForUserID:((long long (*)(id, SEL))objc_msgSend)(account, @selector(userID))] != nil;
}

- (void)switchToAccount:(id)account {
    if (!account) {
        return;
    }
    id host = performShared(objc_getClass("T1HostViewController"), @selector(sharedHostViewController));
    if (host && [host respondsToSelector:@selector(viewAccount:animated:)]) {
        @try {
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(host, @selector(viewAccount:animated:),
                                                        account, YES);
        } @catch (__unused NSException* exception) {
        }
    }
}

@end
