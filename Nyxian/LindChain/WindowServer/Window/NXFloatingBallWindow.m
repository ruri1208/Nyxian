#import "NXFloatingBallWindow.h"
#import <LindChain/WindowServer/NXWindowServer.h>
#import <objc/runtime.h>
#import <objc/message.h>


@interface NXFloatingBallRootView : UIView
@property (nonatomic, weak) id controller;
@end

@implementation NXFloatingBallRootView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) {
       
        if ([self.controller respondsToSelector:NSSelectorFromString(@"isExpanded")] &&
            [self.controller respondsToSelector:NSSelectorFromString(@"toggleExpand")]) {
            BOOL isExpanded = ((BOOL (*)(id, SEL))objc_msgSend)(self.controller, NSSelectorFromString(@"isExpanded"));
            if (isExpanded) {
                ((void (*)(id, SEL))objc_msgSend)(self.controller, NSSelectorFromString(@"toggleExpand"));
            }
        }
        return nil; 
    }
    return hitView;
}



@end

@interface NXFloatingBallViewController : UIViewController

@property (nonatomic, strong) UIView *ballView;          
@property (nonatomic, strong) UIView *menuContainerView; 
@property (nonatomic, assign) BOOL isExpanded;

- (void)setupBallView;
- (void)setupMenuContainerView;
- (void)toggleExpand;
- (void)closeCurrentApp;
- (void)handlePan:(UIPanGestureRecognizer *)pan;

@end

@implementation NXFloatingBallViewController

- (void)loadView {
    NXFloatingBallRootView *rootView = [[NXFloatingBallRootView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    rootView.controller = self;
    self.view = rootView;
}

- (void)viewDidLoad {
    [super viewDidLoad]; 
    self.view.backgroundColor = [UIColor clearColor];
    
    [self setupBallView];
    [self setupMenuContainerView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
   
    _menuContainerView.center = CGPointMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0);
    
    
    if (!_isExpanded && CGAffineTransformIsIdentity(_ballView.transform)) {
        [self updateBallToBottomRightAnimated:NO];
    }
}

- (void)setupBallView {
   
    _ballView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
    _ballView.layer.cornerRadius = 16;
    _ballView.layer.masksToBounds = YES;
    
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blurView.frame = _ballView.bounds;
    blurView.userInteractionEnabled = NO;
    [_ballView addSubview:blurView];
    
    UIView *innerCircle = [[UIView alloc] initWithFrame:CGRectMake(15, 15, 30, 30)];
    innerCircle.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    innerCircle.layer.cornerRadius = 15;
    innerCircle.userInteractionEnabled = NO;
    [_ballView addSubview:innerCircle];
    
    [self.view addSubview:_ballView];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleExpand)];
    [_ballView addGestureRecognizer:tap];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [_ballView addGestureRecognizer:pan];
}

- (void)setupMenuContainerView {
    CGFloat menuWidth = 280;
    CGFloat menuHeight = 280;
    
    _menuContainerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, menuWidth, menuHeight)];
    _menuContainerView.center = CGPointMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0);
    _menuContainerView.layer.cornerRadius = 28;
    _menuContainerView.layer.masksToBounds = YES;
    _menuContainerView.alpha = 0.0;
    _menuContainerView.transform = CGAffineTransformMakeScale(0.3, 0.3);
    
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blurView.frame = _menuContainerView.bounds;
    [_menuContainerView addSubview:blurView];

    CGFloat btnSize = 70.0;
    CGFloat spacing = 30.0;
    CGFloat totalWidth = (btnSize * 2) + spacing;
    CGFloat startX = (menuWidth - totalWidth) / 2.0;
    CGFloat btnY = (menuHeight - btnSize) / 2.0 - 15.0; 

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightBold];

    UIButton *closeMenuBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeMenuBtn.frame = CGRectMake(startX, btnY, btnSize, btnSize);
    closeMenuBtn.backgroundColor = [[UIColor systemGrayColor] colorWithAlphaComponent:0.6];
    closeMenuBtn.layer.cornerRadius = btnSize / 2.0;
    [closeMenuBtn setImage:[UIImage systemImageNamed:@"chevron.down" withConfiguration:config] forState:UIControlStateNormal];
    closeMenuBtn.tintColor = [UIColor whiteColor];
    [closeMenuBtn addTarget:self action:@selector(toggleExpand) forControlEvents:UIControlEventTouchUpInside];
    [_menuContainerView addSubview:closeMenuBtn];

    UILabel *closeMenuLabel = [[UILabel alloc] initWithFrame:CGRectMake(startX - 10, CGRectGetMaxY(closeMenuBtn.frame) + 8, btnSize + 20, 20)];
    closeMenuLabel.text = @"Close Menu";
    closeMenuLabel.textColor = [UIColor whiteColor];
    closeMenuLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    closeMenuLabel.textAlignment = NSTextAlignmentCenter;
    [_menuContainerView addSubview:closeMenuLabel];

    CGFloat closeAppX = startX + btnSize + spacing;
    UIButton *closeAppBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeAppBtn.frame = CGRectMake(closeAppX, btnY, btnSize, btnSize);
    closeAppBtn.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.8];
    closeAppBtn.layer.cornerRadius = btnSize / 2.0;
    [closeAppBtn setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:config] forState:UIControlStateNormal];
    closeAppBtn.tintColor = [UIColor whiteColor];
    [closeAppBtn addTarget:self action:@selector(closeCurrentApp) forControlEvents:UIControlEventTouchUpInside];
    [_menuContainerView addSubview:closeAppBtn];
    
    UILabel *closeAppLabel = [[UILabel alloc] initWithFrame:CGRectMake(closeAppX - 10, CGRectGetMaxY(closeAppBtn.frame) + 8, btnSize + 20, 20)];
    closeAppLabel.text = @"Close App";
    closeAppLabel.textColor = [UIColor whiteColor];
    closeAppLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    closeAppLabel.textAlignment = NSTextAlignmentCenter;
    [_menuContainerView addSubview:closeAppLabel];
    
    [self.view addSubview:_menuContainerView];
}

- (void)toggleExpand {
    _isExpanded = !_isExpanded;
    
    if (_isExpanded) {
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.ballView.alpha = 0.0;
            self.ballView.transform = CGAffineTransformMakeScale(0.3, 0.3);
            
            self.menuContainerView.alpha = 1.0;
            self.menuContainerView.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.ballView.alpha = 1.0;
            self.ballView.transform = CGAffineTransformIdentity;
            
            self.menuContainerView.alpha = 0.0;
            self.menuContainerView.transform = CGAffineTransformMakeScale(0.3, 0.3);
        } completion:nil];
    }
}

- (void)closeCurrentApp {
    [self toggleExpand];
    
    NXWindowServer *server = [NXWindowServer shared];
    if (server.windowOrder.count > 0) {
        NSNumber *activeID = server.windowOrder.firstObject;
        [server closeWindowWithIdentifier:activeID.intValue withCompletion:nil];
    }
}



- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (_isExpanded) return;
    
    CGPoint translation = [pan translationInView:self.view];
    
    
    CGPoint newCenter = CGPointMake(_ballView.center.x + translation.x, _ballView.center.y + translation.y);
    
    
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGFloat ballRadius = 30.0;
    
    CGFloat minX = insets.left + ballRadius + 10;
    CGFloat maxX = self.view.bounds.size.width - insets.right - ballRadius - 10;
    CGFloat minY = insets.top + ballRadius + 10;
    CGFloat maxY = self.view.bounds.size.height - insets.bottom - ballRadius - 10;
    
    newCenter.x = MAX(minX, MIN(maxX, newCenter.x));
    newCenter.y = MAX(minY, MIN(maxY, newCenter.y));
    
    _ballView.center = newCenter;
    [pan setTranslation:CGPointZero inView:self.view];
    
    
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGFloat targetX = (newCenter.x < self.view.bounds.size.width / 2.0) ? minX : maxX;
        
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.ballView.center = CGPointMake(targetX, newCenter.y);
        } completion:nil];
    }
}



- (void)updateBallToBottomRightAnimated:(BOOL)animated {
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGFloat ballRadius = 30.0;
    
    
    CGFloat targetX = self.view.bounds.size.width - insets.right - ballRadius - 40.0;
    CGFloat targetY = self.view.bounds.size.height - insets.bottom - ballRadius - 40.0;
    
   
    CGFloat minX = insets.left + ballRadius + 10;
    CGFloat minY = insets.top + ballRadius + 10;
    targetX = MAX(minX, targetX);
    targetY = MAX(minY, targetY);
    
    CGPoint targetCenter = CGPointMake(targetX, targetY);
    
    if (animated) {
        [UIView animateWithDuration:0.3 animations:^{
            self.ballView.center = targetCenter;
        }];
    } else {
        self.ballView.center = targetCenter;
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
        self.menuContainerView.center = CGPointMake(size.width / 2.0, size.height / 2.0);
        if (!self.isExpanded) {
            [self updateBallToBottomRightAnimated:NO];
        }
    } completion:nil];
}

@end






@implementation NXFloatingBallWindow

+ (instancetype)sharedInstance {
    static NXFloatingBallWindow *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIWindowScene *scene = (UIWindowScene *)[UIApplication sharedApplication].connectedScenes.anyObject;
        if (scene) {
            instance = [[NXFloatingBallWindow alloc] initWithWindowScene:scene];
        } else {
            instance = [[NXFloatingBallWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
        

        instance.windowLevel = CGFLOAT_MAX;
        instance.rootViewController = [[NXFloatingBallViewController alloc] init];
        instance.hidden = YES;
        

        [[NSNotificationCenter defaultCenter] addObserver:instance
                                                 selector:@selector(handleWindowDidBecomeVisible:)
                                                     name:UIWindowDidBecomeVisibleNotification
                                                   object:nil];
    });
    return instance;
}


- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (void)handleWindowDidBecomeVisible:(NSNotification *)notification {

    if (notification.object == self) return;
    
    if (!self.hidden) {
        self.windowLevel = CGFLOAT_MAX;
        [self makeKeyAndVisible]; 
    }
}

- (void)show {
    self.hidden = NO;
    [self makeKeyAndVisible];
}

- (void)hide {
    self.hidden = YES;
}

- (void)updateVisibility {
    BOOL isModeEnabled = [NXWindowServer isFullscreenEnabled] || [NXWindowServer isSimulatorEnabled];
    BOOL hasRunningApps = ([NXWindowServer shared].windows.count > 0);
    
    if (isModeEnabled && hasRunningApps) {
        [self show];
    } else {
        [self hide];
    }
}

@end
