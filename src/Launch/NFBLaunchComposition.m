#import "NFBLaunchComposition.h"
#import <math.h>
#import <TargetConditionals.h>

const CFTimeInterval NFBLaunchDuration = 1.0;
const CGFloat NFBLaunchBirdSide = 100.0;

// One shared ease-in-out progress drives ALL three properties. Sampling its
// values once avoids per-frame code, and keeps opacity and scaling in sync.
double NFBLaunchProgress(double elapsedFraction) {
    double t = fmin(1, fmax(0, elapsedFraction));
    double low = 0, high = 1, u = t;
    for (int i = 0; i < 30; i++) {
        u = (low + high) * .5;
        double x = 3 * (1-u) * (1-u) * u * .42 + 3 * (1-u) * u * u * .58 + u*u*u;
        if (x < t) low = u; else high = u;
    }
    return t == 0 || t == 1 ? t : 3 * (1-u) * u * u + u*u*u;
}

static NSData *NFBMaskAlpha(CGImageRef image) {
    if (!image) return nil;
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    if (!width || !height || width > 4096 || height > 4096) return nil;
    NSMutableData *alpha = [NSMutableData dataWithLength:width * height];
    CGContextRef context = CGBitmapContextCreate(alpha.mutableBytes, width, height, 8,
                                                 width, NULL, kCGImageAlphaOnly);
    if (!context) return nil;
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    return alpha;
}

static BOOL NFBCovers(NSData *alpha, size_t width, size_t height, CGSize size, CGFloat scale) {
    if (!alpha || !isfinite(scale) || scale <= 0) return NO;
    const uint8_t *bytes = alpha.bytes;
    // Check the entire rectangle, not just the bounding box of a concave bird.
    // Both axes are symmetric around the logo centre, so bitmap row direction
    // does not affect this coverage test.
    for (int y = 0; y <= 32; y++) {
        for (int x = 0; x <= 32; x++) {
            double px = (.5 + (x / 32.0 - .5) * size.width / (NFBLaunchBirdSide * scale)) * width;
            double py = (.5 + (y / 32.0 - .5) * size.height / (NFBLaunchBirdSide * scale)) * height;
            if (px < 0 || py < 0 || px >= width || py >= height ||
                bytes[(size_t)py * width + (size_t)px] < 254) return NO;
        }
    }
    return YES;
}

BOOL NFBLaunchMaskCoversRect(CGImageRef image, CGSize size, CGFloat scale) {
    if (!image) return NO;
    return NFBCovers(NFBMaskAlpha(image), CGImageGetWidth(image), CGImageGetHeight(image), size, scale);
}

static CGFloat NFBFinalScale(CGImageRef image, CGSize size) {
    NSData *alpha = NFBMaskAlpha(image);
    // Keep the article's phone-sized 70x endpoint, but adapt to the device.
    CGFloat scale = MAX(70, 70 * MIN(size.width, size.height) / 375.0);
    while (scale < 4096 && !NFBCovers(alpha, CGImageGetWidth(image), CGImageGetHeight(image), size, scale)) {
        scale *= 1.1;
    }
    return scale * 1.02; // Full alpha at the edges before removing the cover.
}

static CGColorRef NFBColor(CGFloat r, CGFloat g, CGFloat b) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat components[] = {r, g, b, 1};
    CGColorRef color = CGColorCreate(space, components);
    CGColorSpaceRelease(space);
    return color;
}

@implementation NFBLaunchComposition {
    CALayer *_maskedLayer;
}
- (instancetype)initWithRoot:(CALayer *)root masked:(CALayer *)masked
                         app:(CALayer *)app maskImage:(CGImageRef)image {
    if (!image || CGRectIsEmpty(root.bounds)) return nil;
    if ((self = [super init])) {
        _maskedLayer = masked;
        _appLayer = app;
        _preferredFramesPerSecond = 60;
        _maskLayer = [CALayer layer];
        _finalMaskScale = NFBFinalScale(image, root.bounds.size);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        CGColorRef blue = NFBColor(29/255.0, 161/255.0, 242/255.0);
        CGColorRef white = NFBColor(1, 1, 1);
        root.backgroundColor = blue;
        root.masksToBounds = YES;
        masked.frame = root.bounds;
        // The masked container's background IS the solid white layer, behind
        // the app sublayer. No opaque logo is composited over the home screen.
        masked.backgroundColor = white;
        app.frame = masked.bounds;
        CGColorRelease(blue);
        CGColorRelease(white);
        _maskLayer.bounds = CGRectMake(0, 0, NFBLaunchBirdSide, NFBLaunchBirdSide);
        _maskLayer.position = CGPointMake(CGRectGetMidX(masked.bounds), CGRectGetMidY(masked.bounds));
        _maskLayer.contents = (__bridge id)image;
        _maskLayer.contentsGravity = kCAGravityResize;
        _maskLayer.magnificationFilter = kCAFilterLinear;
        _maskLayer.minificationFilter = kCAFilterTrilinear;
        masked.mask = _maskLayer;
        [self applyProgress:0];
        [CATransaction commit];
    }
    return self;
}
- (void)applyProgress:(double)progress {
    double p = fmin(1, fmax(0, progress));
    double birdScale = p <= .1 ? 1 - 2*p : .8 + (_finalMaskScale - .8) * (p - .1) / .9;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _maskLayer.transform = CATransform3DMakeScale(birdScale, birdScale, 1);
    _appLayer.opacity = (float)fmin(1, fmax(0, (p - .15) / .15));
    _appLayer.transform = CATransform3DMakeScale(1.1 - .1*p, 1.1 - .1*p, 1);
    [CATransaction commit];
}
- (void)animateWithDelegate:(id<CAAnimationDelegate>)delegate {
    NSMutableArray *times = [NSMutableArray array], *bird = [NSMutableArray array];
    NSMutableArray *opacity = [NSMutableArray array], *app = [NSMutableArray array];
    for (int i = 0; i <= 240; i++) {
        double t = i / 240.0, p = NFBLaunchProgress(t);
        [times addObject:@(t)];
        [bird addObject:@(p <= .1 ? 1 - 2*p : .8 + (_finalMaskScale - .8) * (p - .1) / .9)];
        [opacity addObject:@(fmin(1, fmax(0, (p - .15) / .15)))];
        [app addObject:@(1.1 - .1*p)];
    }
    CFTimeInterval start = CACurrentMediaTime();
    NSArray *layers = @[_maskLayer, _appLayer, _appLayer];
    NSArray *paths = @[@"transform.scale", @"opacity", @"transform.scale"];
    NSArray *values = @[bird, opacity, app];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self applyProgress:1];
    for (NSUInteger i = 0; i < 3; i++) {
        CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:paths[i]];
        animation.values = values[i];
        animation.keyTimes = times;
        animation.duration = NFBLaunchDuration;
        animation.beginTime = [layers[i] convertTime:start fromLayer:nil];
        animation.calculationMode = kCAAnimationLinear;
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
#if TARGET_OS_IOS
        if (@available(iOS 15.0, *)) {
            float rate = (float)MAX(30, _preferredFramesPerSecond);
            animation.preferredFrameRateRange = CAFrameRateRangeMake(MIN(60, rate), rate, rate);
        }
#endif
        if (i == 0) animation.delegate = delegate;
        [layers[i] addAnimation:animation forKey:i == 1 ? @"nfb.opacity" : @"nfb.scale"];
    }
    [CATransaction commit];
}
- (void)cancel {
    [_maskLayer removeAllAnimations];
    [_appLayer removeAllAnimations];
    _maskedLayer.mask = nil;
}
@end

@implementation NFBLaunchCompletionGate {
    NSMutableArray *_callbacks;
}
- (instancetype)init {
    if ((self = [super init])) _callbacks = [NSMutableArray array];
    return self;
}
- (void)enqueue:(void (^)(void))completion {
    if (!completion) return;
    if (_finished) completion();
    else [_callbacks addObject:[completion copy]];
}
- (void)finish {
    if (_finished) return;
    _finished = YES;
    NSArray *pending = [_callbacks copy];
    [_callbacks removeAllObjects];
    for (void (^callback)(void) in pending) callback();
}
@end
