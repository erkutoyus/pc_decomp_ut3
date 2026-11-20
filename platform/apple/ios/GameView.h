#import <UIKit/UIKit.h>

@interface UT3IOSGameView : UIView <UIKeyInput>
@property(copy,nonatomic) void (^touchActivity)(void);
- (void)setInputActive:(BOOL)active;
- (void)toggleKeyboard;
- (void)stopInput;
@end
