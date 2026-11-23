#import <Foundation/Foundation.h>
#import <GameController/GameController.h>

// Main-thread owner. Targets only the selected controller, never phone haptics.
@interface UT3ControllerHaptics : NSObject
- (instancetype)initWithController:(GCController *)controller;
- (void)updateMotors:(uint32_t)motors;
- (void)stop;
@end
