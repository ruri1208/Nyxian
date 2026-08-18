#import <UIKit/UIKit.h>

@interface NXFloatingBallWindow : UIWindow

+ (instancetype)sharedInstance;
- (void)show;
- (void)hide;
- (void)updateVisibility; 

@end
