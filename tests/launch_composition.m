#import "Launch/NFBLaunchComposition.h"
#import <ImageIO/ImageIO.h>
#import <math.h>

static CGContextRef Bitmap(CGSize size) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, size.width, size.height, 8,
        (size_t)size.width * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    return context;
}

static CGImageRef Home(CGSize size) {
    CGContextRef context = Bitmap(size);
    CGContextSetRGBFillColor(context, .04, .04, .04, 1);
    CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));
    for (int row = 0; row < 5; row++) {
        CGFloat top = size.height - 150 - row * 130;
        CGContextSetRGBFillColor(context, 29/255.0, 161/255.0, 242/255.0, 1);
        CGContextFillEllipseInRect(context, CGRectMake(20, top, 40, 40));
        CGContextSetRGBFillColor(context, .65, .65, .65, 1);
        CGContextFillRect(context, CGRectMake(80, top + 25, size.width - 115, 10));
        CGContextSetRGBFillColor(context, .25, .25, .25, 1);
        CGContextFillRect(context, CGRectMake(80, top, size.width - 140, 8));
        CGContextFillRect(context, CGRectMake(80, top - 22, size.width - 110, 8));
    }
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}

// Deterministic rendering of the ACTUAL layer model. UIKit's replicant-view
// snapshot and the render-server GPU are not covered by this macOS pixel test.
static CGContextRef Render(CALayer *root, CALayer *masked, CALayer *app, CGImageRef bird) {
    CGContextRef context = Bitmap(root.bounds.size);
    CGContextSetFillColorWithColor(context, root.backgroundColor);
    CGContextFillRect(context, root.bounds);
    CGFloat side = NFBLaunchBirdSide * masked.mask.transform.m11;
    CGRect birdRect = CGRectMake(CGRectGetMidX(root.bounds) - side/2,
                                CGRectGetMidY(root.bounds) - side/2, side, side);
    CGContextSaveGState(context);
    CGContextClipToMask(context, birdRect, bird);
    CGContextSetFillColorWithColor(context, masked.backgroundColor);
    CGContextFillRect(context, masked.bounds);
    CGContextSetAlpha(context, app.opacity);
    CGFloat scale = app.transform.m11;
    CGContextTranslateCTM(context, CGRectGetMidX(root.bounds), CGRectGetMidY(root.bounds));
    CGContextScaleCTM(context, scale, scale);
    CGContextTranslateCTM(context, -CGRectGetMidX(root.bounds), -CGRectGetMidY(root.bounds));
    CGContextDrawImage(context, app.bounds, (__bridge CGImageRef)app.contents);
    CGContextRestoreGState(context);
    return context;
}

static void Save(CGContextRef context, NSString *path) {
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
        (__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.png"), 1, NULL);
    NSCAssert(destination, @"Preview destination");
    CGImageDestinationAddImage(destination, image, NULL);
    NSCAssert(CGImageDestinationFinalize(destination), @"Preview export");
    CFRelease(destination);
    CGImageRelease(image);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSCAssert(argc == 2, @"Pass the actual packaged mask asset");
        CGImageSourceRef source = CGImageSourceCreateWithURL(
            (__bridge CFURLRef)[NSURL fileURLWithPath:@(argv[1])], NULL);
        NSCAssert(source, @"Mask PNG must decode");
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CFRelease(source);
        NSCAssert(image && CGImageGetWidth(image) == 1024 && CGImageGetHeight(image) == 1024, @"Pre-rendered alpha mask");
        CGSize sizes[] = {{390,844}, {440,956}, {1376,1032}, {1032,1376}};
        for (int device = 0; device < 4; device++) {
            CGSize size = sizes[device];
            CALayer *root = [CALayer layer], *masked = [CALayer layer], *app = [CALayer layer];
            root.bounds = CGRectMake(0, 0, size.width, size.height);
            [root addSublayer:masked];
            [masked addSublayer:app];
            CGImageRef home = Home(size);
            app.contents = (__bridge id)home;
            NFBLaunchComposition *composition = [[NFBLaunchComposition alloc]
                initWithRoot:root masked:masked app:app maskImage:image];
            NSCAssert(composition && masked.mask == composition.maskLayer, @"Bird masks white + app");
            NSCAssert(root.backgroundColor && masked.backgroundColor, @"Blue behind masked white");
            NSCAssert(NFBLaunchMaskCoversRect(image, size, composition.finalMaskScale), @"No blue corners on phone/tablet");
            NSCAssert(!NFBLaunchMaskCoversRect(image, size, 1), @"Initial bird must not fill screen");
            NSCAssert(fabs(composition.maskLayer.transform.m11 - 1) < .0001 && app.opacity == 0, @"White bird initially");
            [composition applyProgress:.1];
            NSCAssert(fabs(composition.maskLayer.transform.m11 - .8) < .0001 && app.opacity == 0, @"Shrink before reveal");
            [composition applyProgress:.15];
            NSCAssert(app.opacity == 0, @"App transparent through 15 percent");
            [composition applyProgress:.225];
            NSCAssert(fabs(app.opacity - .5) < .0001, @"App fades only inside bird");
            [composition applyProgress:.3];
            NSCAssert(app.opacity == 1, @"App fully opaque at 30 percent");
            [composition applyProgress:1];
            NSCAssert(fabs(app.transform.m11 - 1) < .0001, @"Home settles to normal scale");
            NSString *preview = NSProcessInfo.processInfo.environment[@"NFB_LAUNCH_PREVIEW_DIR"];
            for (NSNumber *time in @[@0, @.15, @.225, @.3, @.4, @.6, @1]) {
                [composition applyProgress:NFBLaunchProgress(time.doubleValue)];
                CGContextRef frame = Render(root, masked, app, image);
                const uint8_t *bytes = CGBitmapContextGetData(frame);
                size_t center = (((size_t)size.height / 2) * (size_t)size.width + (size_t)size.width / 2) * 4;
                if (time.doubleValue == 0) {
                    NSCAssert(bytes[0] == 29 && bytes[1] == 161 && bytes[2] == 242, @"Initial corners blue");
                    NSCAssert(bytes[center] == 255 && bytes[center+1] == 255, @"Initial bird white");
                }
                if (time.doubleValue == 1) NSCAssert(bytes[0] < 20 && bytes[1] < 20, @"Final corner fully home, not blue");
                if (preview) Save(frame, [preview stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"%.0fx%.0f-%03d.png", size.width, size.height,
                                               (int)round(time.doubleValue * 100)]]);
                CGContextRelease(frame);
            }
            [composition animateWithDelegate:nil];
            CAKeyframeAnimation *maskAnimation = (id)[composition.maskLayer animationForKey:@"nfb.scale"];
            CAKeyframeAnimation *opacityAnimation = (id)[app animationForKey:@"nfb.opacity"];
            CAKeyframeAnimation *appAnimation = (id)[app animationForKey:@"nfb.scale"];
            NSCAssert(maskAnimation.values.count == 241 && maskAnimation.duration == 1.0, @"One second native keyframes");
            NSCAssert([maskAnimation.keyTimes isEqual:opacityAnimation.keyTimes] &&
                      [maskAnimation.keyTimes isEqual:appAnimation.keyTimes], @"Common timeline");
            NSCAssert([opacityAnimation.values.firstObject doubleValue] == 0 &&
                      [opacityAnimation.values.lastObject doubleValue] == 1, @"Correct opacity endpoints");
            [composition cancel];
            NSCAssert(!masked.mask && !app.animationKeys.count && !composition.maskLayer.animationKeys.count, @"Cancellation cleans all layers");
            printf("PASS: %.0fx%.0f classic masked reveal, final scale %.2f\n", size.width, size.height, composition.finalMaskScale);
            CGImageRelease(home);
        }
        NFBLaunchCompletionGate *gate = [NFBLaunchCompletionGate new];
        __block NSUInteger calls = 0;
        [gate enqueue:^{ calls++; [gate finish]; }]; // Reentrant callback.
        [gate enqueue:nil];
        [gate enqueue:^{ calls++; }];
        NSCAssert(calls == 0, @"Hold ready callbacks until reveal finishes");
        [gate finish];
        [gate finish];
        NSCAssert(calls == 2 && gate.finished, @"Cancel completes each request once");
        [gate enqueue:^{ calls++; }];
        NSCAssert(calls == 3, @"Late request completes immediately");
        CGImageRelease(image);
        puts("PASS: native timing, real mask pixel checks, cancellation and ready callbacks");
    }
}
