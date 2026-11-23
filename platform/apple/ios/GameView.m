#import "GameView.h"
#import "../ControllerHaptics.h"
#import <QuartzCore/CAMetalLayer.h>
#import <GameController/GameController.h>
#include "input.h"
#include <math.h>
#include "../Pointer.h"
#if defined(UT3_APPLE_DXVK)
void ut3_dxvk_get_backbuffer_extent(uint32_t *,uint32_t *);
void ut3_apple_metal_resize(uint32_t,uint32_t);
void void_input_clip_bounds(int32_t[4]);
#endif

static int16_t axis(float value) { return (int16_t)lrintf(fmaxf(-1, fminf(1, value)) * 32767); }
static uint8_t trigger(float value) { return (uint8_t)lrintf(fmaxf(0, fminf(1, value)) * 255); }

@implementation UT3IOSGameView {
    GCController *_controller;
    BOOL _active, _stopped, _chord, _reportedInput;
    id _connected, _disconnected, _shown, _hidden;
    UITouch *_mouseTouch;
    int _mouseX, _mouseY;
    uint32_t _reportedWidth, _reportedHeight;
    UT3ControllerHaptics *_haptics;
    NSTimer *_hapticsTimer;
}
+ (Class)layerClass { return CAMetalLayer.class; }
- (instancetype)initWithFrame:(CGRect)frame
{
    if (!(self = [super initWithFrame:frame])) return nil;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    __weak UT3IOSGameView *weak = self;
    _connected = [center addObserverForName:GCControllerDidConnectNotification object:nil queue:NSOperationQueue.mainQueue
                               usingBlock:^(NSNotification *note) { [weak selectController:nil]; }];
    _disconnected = [center addObserverForName:GCControllerDidDisconnectNotification object:nil queue:NSOperationQueue.mainQueue
                                  usingBlock:^(NSNotification *note) { [weak selectController:note.object]; }];
    _shown = [center addObserverForName:UIKeyboardDidShowNotification object:nil queue:NSOperationQueue.mainQueue
                           usingBlock:^(NSNotification *note) { fprintf(stderr, "[ios-input] keyboard shown\n"); }];
    _hidden = [center addObserverForName:UIKeyboardDidHideNotification object:nil queue:NSOperationQueue.mainQueue
                            usingBlock:^(NSNotification *note) { fprintf(stderr, "[ios-input] keyboard hidden\n"); [weak publish]; }];
    return self;
}
- (BOOL)canBecomeFirstResponder { return YES; }
- (BOOL)hasText { return YES; } // The guest owns the text, including deletion.
- (UIKeyboardType)keyboardType { return UIKeyboardTypeDefault; }
- (UIReturnKeyType)returnKeyType { return UIReturnKeyDone; }
- (UITextAutocorrectionType)autocorrectionType { return UITextAutocorrectionTypeNo; }
- (UITextSpellCheckingType)spellCheckingType { return UITextSpellCheckingTypeNo; }
- (UITextAutocapitalizationType)autocapitalizationType { return UITextAutocapitalizationTypeNone; }
- (UITextSmartQuotesType)smartQuotesType { return UITextSmartQuotesTypeNo; }
- (UITextSmartDashesType)smartDashesType { return UITextSmartDashesTypeNo; }
- (void)insertText:(NSString *)text
{
    if (!_active || _stopped) return;
    if ([text isEqualToString:@"\n"] || [text isEqualToString:@"\r"]) {
        void_input_key(13, 1); void_input_key(13, 0);
        [self resignFirstResponder]; [self publish]; return;
    }
    // UITextInput may deliver a composed character or paste in one callback.
    // Preserve UTF-16 pairs and never log user-entered text.
    if (text.length > 256) { UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"Text is too long"); return; }
    uint16_t characters[256];
    [text getCharacters:characters range:NSMakeRange(0, text.length)];
    if (!void_input_text_utf16(characters, (int)text.length))
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"Input is busy. Please try again.");
}
- (void)deleteBackward
{
    if (!_active || _stopped) return;
    void_input_key(8, 1); void_input_key(8, 0);
}
- (void)toggleKeyboard
{
    if (!_active || _stopped) return;
    [self cancelPointer];
    if (self.isFirstResponder) [self resignFirstResponder];
    else [self becomeFirstResponder];
    [self publish];
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    CAMetalLayer *layer=(CAMetalLayer *)self.layer;
    layer.drawableSize=CGSizeMake(self.bounds.size.width*self.contentScaleFactor,
                                  self.bounds.size.height*self.contentScaleFactor);
#if defined(UT3_APPLE_DXVK)
    ut3_apple_metal_resize((uint32_t)layer.drawableSize.width,(uint32_t)layer.drawableSize.height);
#endif
}
- (BOOL)position:(UITouch *)touch captured:(BOOL)captured x:(int *)x y:(int *)y
{
#if defined(UT3_APPLE_DXVK)
    uint32_t width=0,height=0;ut3_dxvk_get_backbuffer_extent(&width,&height);
    if(width!=_reportedWidth||height!=_reportedHeight) {
        int32_t clip[4];void_input_clip_bounds(clip);
        fprintf(stderr,"[ios-input] touch surface %ux%u clip=%d,%d..%d,%d\n",
                width,height,clip[0],clip[1],clip[2],clip[3]);
        _reportedWidth=width;_reportedHeight=height;
    }
    CGPoint point=[touch locationInView:self];
    CGSize pixels=((CAMetalLayer *)self.layer).drawableSize;
    if(!ut3_apple_pointer_position(point.x-self.bounds.origin.x,point.y-self.bounds.origin.y,
        self.bounds.size.width,self.bounds.size.height,(uint32_t)lround(pixels.width),
        (uint32_t)lround(pixels.height),width,height,captured,x,y))return NO;
    return YES;
#else
    return NO;
#endif
}
- (void)cancelPointer
{
    if(_mouseTouch) void_input_mouse_button(0,0);
    _mouseTouch=nil;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if(!_active||_stopped)return;
    if(self.touchActivity)self.touchActivity();
    if(_mouseTouch)return;
    if(self.isFirstResponder) { [self resignFirstResponder];[self publish]; }
    UITouch *touch=touches.anyObject;
    int x,y;if(![self position:touch captured:NO x:&x y:&y])return;
    _mouseTouch=touch;_mouseX=x;_mouseY=y;
    void_input_mouse_motion(0,0,x,y);
    void_input_mouse_button(0,1);
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if(!_active||!_mouseTouch||![touches containsObject:_mouseTouch])return;
    int x,y;if([self position:_mouseTouch captured:YES x:&x y:&y]) {
        void_input_mouse_motion(x-_mouseX,y-_mouseY,x,y);_mouseX=x;_mouseY=y;
    }
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if(!_mouseTouch||![touches containsObject:_mouseTouch])return;
    [self touchesMoved:touches withEvent:event];
    [self cancelPointer];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if(_mouseTouch&&[touches containsObject:_mouseTouch])[self cancelPointer];
}
- (void)publish
{
    GCExtendedGamepad *p = _controller.extendedGamepad;
    if (!_active || _stopped || !p) { void_input_set_controller(NULL); return; }
    void_controller_state state = {0};
    if (!self.isFirstResponder) {
        state = (void_controller_state){
            .buttons = (p.dpad.up.pressed?1:0) | (p.dpad.down.pressed?2:0) |
                (p.dpad.left.pressed?4:0) | (p.dpad.right.pressed?8:0) |
                (p.buttonMenu.pressed?0x10:0) | (p.buttonOptions.pressed?0x20:0) |
                (p.leftThumbstickButton.pressed?0x40:0) | (p.rightThumbstickButton.pressed?0x80:0) |
                (p.leftShoulder.pressed?0x100:0) | (p.rightShoulder.pressed?0x200:0) |
                (p.buttonA.pressed?0x1000:0) | (p.buttonB.pressed?0x2000:0) |
                (p.buttonX.pressed?0x4000:0) | (p.buttonY.pressed?0x8000:0),
            .left_trigger=trigger(p.leftTrigger.value), .right_trigger=trigger(p.rightTrigger.value),
            .lx=axis(p.leftThumbstick.xAxis.value), .ly=axis(p.leftThumbstick.yAxis.value),
            .rx=axis(p.rightThumbstick.xAxis.value), .ry=axis(p.rightThumbstick.yAxis.value)
        };
        if (_chord) state.buttons &= ~(0x10 | 0x8000);
    }
    void_input_set_controller(&state);
}
- (void)selectController:(GCController *)removed
{
    if (_stopped) return;
    if (_controller && _controller != removed && [GCController.controllers containsObject:_controller]) return;
    [self stopHaptics];
    _controller.extendedGamepad.valueChangedHandler = nil;
    _controller = nil; _chord = NO; _reportedInput = NO;
    void_input_set_controller(NULL);
    for (GCController *candidate in GCController.controllers) {
        if (candidate == removed || !candidate.extendedGamepad) continue;
        _controller = candidate;
        candidate.handlerQueue = dispatch_get_main_queue();
        fprintf(stderr, "[ios-input] controller connected: %s\n", candidate.vendorName.UTF8String ?: "MFi");
        __weak UT3IOSGameView *weak = self;
        candidate.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *pad, GCControllerElement *element) {
            UT3IOSGameView *view = weak;
            if (!view || view->_controller.extendedGamepad != pad) return;
            if (!view->_reportedInput) { view->_reportedInput=YES; fprintf(stderr,"[ios-input] physical controller events received\n"); }
            BOOL chord = pad.buttonMenu.pressed && pad.buttonY.pressed;
            if (chord && !view->_chord) { view->_chord = YES; [view toggleKeyboard]; }
            if (!pad.buttonMenu.pressed && !pad.buttonY.pressed) view->_chord = NO;
            [view publish];
        };
        break;
    }
    if (!_controller) fprintf(stderr, "[ios-input] no extended MFi controller connected\n");
    [self publish];
    if(_active)[self startHaptics];
}
- (void)stopHaptics
{
    [_hapticsTimer invalidate];_hapticsTimer=nil;
    [_haptics stop];_haptics=nil;
    void_input_clear_rumble();
}
- (void)startHaptics
{
    if(!_active||!_controller||_hapticsTimer)return;
    _haptics=[[UT3ControllerHaptics alloc] initWithController:_controller];
    if(!_haptics)return;
    __weak UT3IOSGameView *weak=self;
    _hapticsTimer=[NSTimer timerWithTimeInterval:1.0/60 repeats:YES block:^(NSTimer *timer) {
        UT3IOSGameView *view=weak;
        if(view && view->_active)[view->_haptics updateMotors:void_input_get_rumble()];
    }];
    [NSRunLoop.mainRunLoop addTimer:_hapticsTimer forMode:NSRunLoopCommonModes];
}
- (void)setInputActive:(BOOL)active
{
    _active = active;
    if (!active) { [self stopHaptics];[self cancelPointer];[self resignFirstResponder]; void_input_release_physical(); void_input_set_controller(NULL); }
    else { [self selectController:nil]; [self publish]; [self startHaptics]; }
}
- (void)stopInput
{
    if (_stopped) return;
    [self setInputActive:NO]; _stopped = YES;
    _controller.extendedGamepad.valueChangedHandler = nil; _controller = nil;
    for (id observer in @[_connected ?: NSNull.null, _disconnected ?: NSNull.null,
                          _shown ?: NSNull.null, _hidden ?: NSNull.null])
        if (observer != NSNull.null) [NSNotificationCenter.defaultCenter removeObserver:observer];
    _connected=_disconnected=_shown=_hidden=nil;
}
- (void)dealloc { [self stopInput]; }
@end
