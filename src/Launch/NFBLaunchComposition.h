#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

// The React Native article's three layers, implemented entirely in Core
// Animation: blue background, masked white layer, masked app content.
// https://reactnative.dev/blog/2018/01/18/implementing-twitters-app-loading-animation-in-react-native
FOUNDATION_EXPORT const CFTimeInterval NFBLaunchDuration;
FOUNDATION_EXPORT const CGFloat NFBLaunchBirdSide;
FOUNDATION_EXPORT double NFBLaunchProgress(double elapsedFraction);
FOUNDATION_EXPORT BOOL NFBLaunchMaskCoversRect(CGImageRef image, CGSize size, CGFloat scale);

@interface NFBLaunchComposition : NSObject
@property (nonatomic, readonly) CALayer *maskLayer;
@property (nonatomic, readonly) CALayer *appLayer;
@property (nonatomic, readonly) CGFloat finalMaskScale;
@property (nonatomic) CGFloat preferredFramesPerSecond;
- (instancetype)initWithRoot:(CALayer *)root masked:(CALayer *)masked
                         app:(CALayer *)app maskImage:(CGImageRef)image;
- (void)applyProgress:(double)progress;
- (void)animateWithDelegate:(id<CAAnimationDelegate>)delegate;
- (void)cancel;
@end

// A host can submit more than one ready callback. Each is delivered exactly
// once, even when backgrounding / Reduce Motion cancels the reveal.
@interface NFBLaunchCompletionGate : NSObject
@property (nonatomic, readonly) BOOL finished;
- (void)enqueue:(void (^)(void))completion;
- (void)finish;
@end
