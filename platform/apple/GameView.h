#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>

@interface UT3GameView : NSView
@property(nonatomic, readonly) CAMetalLayer *presentationLayer;
- (void)updateDrawableSize;
- (void)setInputActive:(BOOL)active;
- (void)stopInput;
@end
