#import <UIKit/UIKit.h>

@interface NFBClassicLaunchSession : NSObject
- (instancetype)initWithLaunchView:(UIView *)view maskImage:(UIImage *)image;
- (void)revealWithCompletion:(void (^)(void))completion;
- (void)updateForLaunchView;
- (void)finish;
@end
