#import "NFBClassicLaunchSession.h"
#import "NFBLaunchComposition.h"

@interface NFBClassicLaunchSession () <CAAnimationDelegate>
@end

@implementation NFBClassicLaunchSession {
    __weak UIView *_launchView;
    __weak UIWindow *_window;
    UIView *_cover;
    UIView *_masked;
    UIView *_app;
    NFBLaunchComposition *_composition;
    NFBLaunchCompletionGate *_completion;
    CGSize _canvasSize;
    BOOL _started;
    BOOL _finishing;
}
- (instancetype)initWithLaunchView:(UIView *)view maskImage:(UIImage *)image {
    if (!view.window || !image.CGImage || CGRectIsEmpty(view.window.bounds)) return nil;
    if ((self = [super init])) {
        _launchView = view;
        _window = view.window;
        _canvasSize = view.window.bounds.size;
        _completion = [NFBLaunchCompletionGate new];
        _cover = [[UIView alloc] initWithFrame:view.window.bounds];
        // Do not let taps navigate the live app while its one-second snapshot
        // is still being revealed; the cover is removed before host callbacks.
        _cover.userInteractionEnabled = YES;
        _cover.accessibilityElementsHidden = YES;
        _cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _masked = [[UIView alloc] initWithFrame:_cover.bounds];
        _app = [[UIView alloc] initWithFrame:_cover.bounds];
        [_cover addSubview:_masked];
        [_masked addSubview:_app];
        _composition = [[NFBLaunchComposition alloc] initWithRoot:_cover.layer
                    masked:_masked.layer app:_app.layer maskImage:image.CGImage];
        _composition.preferredFramesPerSecond = _window.screen.maximumFramesPerSecond;
        [_window addSubview:_cover];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(willResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:self selector:@selector(reduceMotionChanged:) name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    }
    return self;
}
- (void)willResignActive:(NSNotification *)notification {
    [self finish];
}
- (void)reduceMotionChanged:(NSNotification *)notification {
    if (UIAccessibilityIsReduceMotionEnabled()) [self finish];
}
- (void)updateForLaunchView {
    if (_completion.finished) return;
    if (!_launchView.window || _launchView.window != _window ||
        !CGSizeEqualToSize(_canvasSize, _window.bounds.size)) {
        // Rotation/resizing or detachment must never leave a stale mask/window.
        [self finish];
    } else {
        [_window bringSubviewToFront:_cover];
    }
}
- (void)revealWithCompletion:(void (^)(void))completion {
    [_completion enqueue:completion];
    if (_completion.finished || _started) return;
    _started = YES;
    UIView *root = _window.rootViewController.view;
    if (!root || root == _launchView || !root.window || UIAccessibilityIsReduceMotionEnabled()) {
        [self finish];
        return;
    }
    _launchView.hidden = YES;
    [root layoutIfNeeded];
    // The cover is a WINDOW sibling, deliberately excluded from this snapshot.
    // Capture once after the native app is ready. The live root hierarchy,
    // its constraints, transforms and mask are never modified or reparented.
    UIView *snapshot = [root snapshotViewAfterScreenUpdates:YES];
    if (!snapshot) {
        [self finish];
        return;
    }
    snapshot.frame = [root convertRect:root.bounds toView:_window];
    UIColor *background = root.backgroundColor;
    _app.backgroundColor = background && CGColorGetAlpha(background.CGColor) >= .99
        ? background : [UIColor systemBackgroundColor];
    [_app addSubview:snapshot];
    [_composition animateWithDelegate:self];
    // A defensive deadline also releases the native ready callback if CA is
    // interrupted without delivering its delegate notification.
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf finish];
    });
}
- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished {
    [self finish];
}
- (void)finish {
    if (_finishing || _completion.finished) return;
    _finishing = YES;
    // Removing animations can synchronously re-enter via animationDidStop.
    // Guard that before cleaning up; host callbacks run only after cleanup.
    [_composition cancel];
    _composition = nil;
    [_cover removeFromSuperview];
    _cover = nil;
    _masked = nil;
    _app = nil;
    _launchView.hidden = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_completion finish];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end
