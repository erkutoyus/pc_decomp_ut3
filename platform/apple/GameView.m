#import "GameView.h"
#import "ControllerHaptics.h"
#import <Carbon/Carbon.h>
#import <GameController/GameController.h>
#import <IOKit/hidsystem/IOLLEvent.h>
#include "input.h"
#include <math.h>
#if defined(UT3_APPLE_DXVK)
void ut3_dxvk_get_backbuffer_extent(uint32_t *, uint32_t *);
#endif

static uint8_t virtual_key(unsigned code)
{
    static const uint8_t keys[128] = {
        [kVK_ANSI_A]='A', [kVK_ANSI_B]='B', [kVK_ANSI_C]='C', [kVK_ANSI_D]='D',
        [kVK_ANSI_E]='E', [kVK_ANSI_F]='F', [kVK_ANSI_G]='G', [kVK_ANSI_H]='H',
        [kVK_ANSI_I]='I', [kVK_ANSI_J]='J', [kVK_ANSI_K]='K', [kVK_ANSI_L]='L',
        [kVK_ANSI_M]='M', [kVK_ANSI_N]='N', [kVK_ANSI_O]='O', [kVK_ANSI_P]='P',
        [kVK_ANSI_Q]='Q', [kVK_ANSI_R]='R', [kVK_ANSI_S]='S', [kVK_ANSI_T]='T',
        [kVK_ANSI_U]='U', [kVK_ANSI_V]='V', [kVK_ANSI_W]='W', [kVK_ANSI_X]='X',
        [kVK_ANSI_Y]='Y', [kVK_ANSI_Z]='Z',
        [kVK_ANSI_0]='0', [kVK_ANSI_1]='1', [kVK_ANSI_2]='2', [kVK_ANSI_3]='3', [kVK_ANSI_4]='4',
        [kVK_ANSI_5]='5', [kVK_ANSI_6]='6', [kVK_ANSI_7]='7', [kVK_ANSI_8]='8', [kVK_ANSI_9]='9',
        [kVK_ANSI_Equal]=0xBB, [kVK_ANSI_Minus]=0xBD, [kVK_ANSI_LeftBracket]=0xDB,
        [kVK_ANSI_RightBracket]=0xDD, [kVK_ANSI_Backslash]=0xDC, [kVK_ANSI_Semicolon]=0xBA,
        [kVK_ANSI_Quote]=0xDE, [kVK_ANSI_Comma]=0xBC, [kVK_ANSI_Period]=0xBE,
        [kVK_ANSI_Slash]=0xBF, [kVK_ANSI_Grave]=0xC0,
        [kVK_Return]=0x0D, [kVK_ANSI_KeypadEnter]=0x0D, [kVK_Tab]=0x09, [kVK_Space]=0x20,
        [kVK_Delete]=0x08, [kVK_ForwardDelete]=0x2E, [kVK_Escape]=0x1B,
        [kVK_Home]=0x24, [kVK_End]=0x23, [kVK_PageUp]=0x21, [kVK_PageDown]=0x22,
        [kVK_LeftArrow]=0x25, [kVK_UpArrow]=0x26, [kVK_RightArrow]=0x27, [kVK_DownArrow]=0x28,
        [kVK_F1]=0x70, [kVK_F2]=0x71, [kVK_F3]=0x72, [kVK_F4]=0x73, [kVK_F5]=0x74,
        [kVK_F6]=0x75, [kVK_F7]=0x76, [kVK_F8]=0x77, [kVK_F9]=0x78, [kVK_F10]=0x79,
        [kVK_F11]=0x7A, [kVK_F12]=0x7B,
        [kVK_ANSI_Keypad0]=0x60, [kVK_ANSI_Keypad1]=0x61, [kVK_ANSI_Keypad2]=0x62,
        [kVK_ANSI_Keypad3]=0x63, [kVK_ANSI_Keypad4]=0x64, [kVK_ANSI_Keypad5]=0x65,
        [kVK_ANSI_Keypad6]=0x66, [kVK_ANSI_Keypad7]=0x67, [kVK_ANSI_Keypad8]=0x68,
        [kVK_ANSI_Keypad9]=0x69, [kVK_ANSI_KeypadMultiply]=0x6A, [kVK_ANSI_KeypadPlus]=0x6B,
        [kVK_ANSI_KeypadMinus]=0x6D, [kVK_ANSI_KeypadDecimal]=0x6E, [kVK_ANSI_KeypadDivide]=0x6F,
        [kVK_CapsLock]=0x14, [kVK_Shift]=0xA0, [kVK_RightShift]=0xA1,
        [kVK_Control]=0xA2, [kVK_RightControl]=0xA3, [kVK_Option]=0xA4, [kVK_RightOption]=0xA5,
        [kVK_Command]=0x5B, [kVK_RightCommand]=0x5C
    };
    return code < sizeof keys ? keys[code] : 0;
}

static int16_t controller_axis(float value)
{
    return (int16_t)lrintf(fmaxf(-1, fminf(1, value)) * (value < 0 ? 32768 : 32767));
}

static uint8_t controller_trigger(float value)
{
    return (uint8_t)lrintf(fmaxf(0, fminf(1, value)) * 255);
}

@implementation UT3GameView {
    BOOL _inputActive;
    BOOL _stopped;
    BOOL _keyDown[256];
    CGFloat _mouseX, _mouseY, _scroll;
    CGFloat _lastMouseY;
    BOOL _hasLastMouse;
    GCController *_controller;
    UT3ControllerHaptics *_haptics;
    NSTimer *_hapticsTimer;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(controllerChanged:) name:GCControllerDidConnectNotification object:nil];
        [center addObserver:self selector:@selector(controllerChanged:) name:GCControllerDidDisconnectNotification object:nil];
    }
    return self;
}

- (CALayer *)makeBackingLayer { return [CAMetalLayer layer]; }
- (CAMetalLayer *)presentationLayer { return (CAMetalLayer *)self.layer; }
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)updateDrawableSize
{
    NSSize size = [self convertSizeToBacking:self.bounds.size];
    int width = (int)lround(size.width), height = (int)lround(size.height);
    self.presentationLayer.contentsScale = self.window.backingScaleFactor;
    self.presentationLayer.drawableSize = CGSizeMake(width, height);
    if (!self.presentationLayer.device) void_input_set_screen_size(width, height);
}

- (void)publishController:(GCExtendedGamepad *)pad
{
    if (!_inputActive || !pad) return;
    void_controller_state state = {
        .buttons = (pad.dpad.up.pressed ? 0x0001 : 0) | (pad.dpad.down.pressed ? 0x0002 : 0) |
                   (pad.dpad.left.pressed ? 0x0004 : 0) | (pad.dpad.right.pressed ? 0x0008 : 0) |
                   (pad.buttonMenu.pressed ? 0x0010 : 0) | (pad.buttonOptions.pressed ? 0x0020 : 0) |
                   (pad.leftThumbstickButton.pressed ? 0x0040 : 0) | (pad.rightThumbstickButton.pressed ? 0x0080 : 0) |
                   (pad.leftShoulder.pressed ? 0x0100 : 0) | (pad.rightShoulder.pressed ? 0x0200 : 0) |
                   (pad.buttonA.pressed ? 0x1000 : 0) | (pad.buttonB.pressed ? 0x2000 : 0) |
                   (pad.buttonX.pressed ? 0x4000 : 0) | (pad.buttonY.pressed ? 0x8000 : 0),
        .left_trigger = controller_trigger(pad.leftTrigger.value),
        .right_trigger = controller_trigger(pad.rightTrigger.value),
        .lx = controller_axis(pad.leftThumbstick.xAxis.value),
        .ly = controller_axis(pad.leftThumbstick.yAxis.value),
        .rx = controller_axis(pad.rightThumbstick.xAxis.value),
        .ry = controller_axis(pad.rightThumbstick.yAxis.value)
    };
    void_input_set_controller(&state);
}

- (void)selectControllerExcluding:(GCController *)disconnected
{
    if (_stopped) return;
    NSArray<GCController *> *controllers = GCController.controllers;
    if (_controller && _controller != disconnected && [controllers containsObject:_controller]) return;
    [self stopHaptics];
    _controller.extendedGamepad.valueChangedHandler = nil;
    _controller = nil;
    void_input_set_controller(NULL);
    for (GCController *controller in controllers) {
        if (controller == disconnected || !controller.extendedGamepad) continue;
        _controller = controller;
        controller.handlerQueue = dispatch_get_main_queue();
        __weak UT3GameView *weakView = self;
        controller.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *pad, GCControllerElement *element) {
            UT3GameView *view = weakView;
            if (view && view->_controller.extendedGamepad == pad) [view publishController:pad];
        };
        [self publishController:controller.extendedGamepad];
        if(_inputActive)[self startHaptics];
        break;
    }
}

- (void)stopHaptics
{
    [_hapticsTimer invalidate];_hapticsTimer=nil;
    [_haptics stop];_haptics=nil;
    void_input_clear_rumble();
}
- (void)startHaptics
{
    if(!_inputActive||!_controller||_hapticsTimer)return;
    _haptics=[[UT3ControllerHaptics alloc] initWithController:_controller];
    if(!_haptics)return;
    __weak UT3GameView *weak=self;
    _hapticsTimer=[NSTimer timerWithTimeInterval:1.0/60 repeats:YES block:^(NSTimer *timer) {
        UT3GameView *view=weak;
        if(view && view->_inputActive)[view->_haptics updateMotors:void_input_get_rumble()];
    }];
    [NSRunLoop.mainRunLoop addTimer:_hapticsTimer forMode:NSRunLoopCommonModes];
}

- (void)controllerChanged:(NSNotification *)event
{
    GCController *disconnected = [event.name isEqualToString:GCControllerDidDisconnectNotification] ? event.object : nil;
    if (NSThread.isMainThread) [self selectControllerExcluding:disconnected];
    else {
        __weak UT3GameView *view = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [view selectControllerExcluding:disconnected]; });
    }
}

- (void)setInputActive:(BOOL)active
{
    if (_stopped || active == _inputActive) return;
    _inputActive = active;
    if (active) {
        [self selectControllerExcluding:nil];
        [self publishController:_controller.extendedGamepad];
        [self startHaptics];
    } else {
        [self stopHaptics];
        void_input_release_physical();
        void_input_set_controller(NULL);
        memset(_keyDown, 0, sizeof _keyDown);
        _mouseX = _mouseY = _scroll = 0;
        _hasLastMouse = NO;
    }
}

- (void)stopInput
{
    [self setInputActive:NO];
    _stopped = YES;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    _controller.extendedGamepad.valueChangedHandler = nil;
    _controller = nil;
}
- (void)dealloc { [self stopInput]; }

- (void)recordKey:(NSEvent *)event down:(BOOL)down
{
    uint8_t key = virtual_key(event.keyCode);
    if (_inputActive && key) {
        _keyDown[key] = down;
        void_input_key(key, down);
    }
}

- (void)keyDown:(NSEvent *)event { [self recordKey:event down:YES]; }
- (void)keyUp:(NSEvent *)event { [self recordKey:event down:NO]; }

- (void)flagsChanged:(NSEvent *)event
{
    uint8_t key = virtual_key(event.keyCode);
    NSEventModifierFlags modifier;
    NSUInteger left = 0, right = 0;
    BOOL rightKey = NO;
    switch (key) {
        case 0x14: modifier = NSEventModifierFlagCapsLock; break;
        case 0xA0: case 0xA1:
            modifier = NSEventModifierFlagShift;
            left = NX_DEVICELSHIFTKEYMASK; right = NX_DEVICERSHIFTKEYMASK; rightKey = key == 0xA1;
            break;
        case 0xA2: case 0xA3:
            modifier = NSEventModifierFlagControl;
            left = NX_DEVICELCTLKEYMASK; right = NX_DEVICERCTLKEYMASK; rightKey = key == 0xA3;
            break;
        case 0xA4: case 0xA5:
            modifier = NSEventModifierFlagOption;
            left = NX_DEVICELALTKEYMASK; right = NX_DEVICERALTKEYMASK; rightKey = key == 0xA5;
            break;
        case 0x5B: case 0x5C:
            modifier = NSEventModifierFlagCommand;
            left = NX_DEVICELCMDKEYMASK; right = NX_DEVICERCMDKEYMASK; rightKey = key == 0x5C;
            break;
        default: return;
    }
    NSUInteger flags = event.modifierFlags;
    BOOL down = (flags & (left | right)) ? (flags & (rightKey ? right : left)) != 0
               : (flags & modifier) && (key == 0x14 || !_keyDown[key]);
    [self recordKey:event down:down];
}

- (NSPoint)guestPosition:(NSEvent *)event
{
    NSRect content = [self convertRect:self.bounds toView:nil];
    if (NSIsEmptyRect(content)) return NSZeroPoint;
    CGSize drawable = self.presentationLayer.drawableSize;
    // Window events use a bottom-left origin. Win32 client coordinates start at the top left.
    NSPoint point = NSMakePoint((event.locationInWindow.x - NSMinX(content)) * drawable.width / NSWidth(content),
                                (NSMaxY(content) - event.locationInWindow.y) * drawable.height / NSHeight(content));
#if defined(UT3_APPLE_DXVK)
    if (self.presentationLayer.device && drawable.width > 0 && drawable.height > 0) {
        uint32_t width, height;
        ut3_dxvk_get_backbuffer_extent(&width, &height);
        if (width && height) {
            CGFloat scale = fmin(drawable.width / width, drawable.height / height);
            CGFloat displayedWidth = lround(width * scale), displayedHeight = lround(height * scale);
            if (displayedWidth && displayedHeight) {
                // Match the integer letterbox used by the D3D9 Present bridge.
                point.x = (point.x - floor((drawable.width - displayedWidth) / 2)) * width / displayedWidth;
                point.y = (point.y - floor((drawable.height - displayedHeight) / 2)) * height / displayedHeight;
            }
        }
    }
#endif
    return point;
}

- (void)mouseMoved:(NSEvent *)event
{
    if (!_inputActive) return;
    NSPoint point = [self guestPosition:event];
    CGFloat scale = self.window.backingScaleFactor;
    _mouseX += event.deltaX * scale;
    CGFloat vertical = event.deltaY * scale;
    CGFloat windowY = event.locationInWindow.y;
    // Keep the hardware delta magnitude, using the actual cursor travel for its direction.
    // At a screen edge the location can repeat while the device is still moving.
    if (_hasLastMouse && windowY != _lastMouseY && vertical)
        vertical = copysign(fabs(vertical), _lastMouseY - windowY);
    _mouseY += vertical;
    _lastMouseY = windowY;
    _hasLastMouse = YES;
    int dx = (int)_mouseX, dy = (int)_mouseY;
    _mouseX -= dx;
    _mouseY -= dy;
    void_input_mouse_motion(dx, dy, (int)point.x, (int)point.y);
}

- (void)mouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)rightMouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)otherMouseDragged:(NSEvent *)event { [self mouseMoved:event]; }

- (void)recordButton:(NSEvent *)event down:(BOOL)down
{
    if (!_inputActive || event.buttonNumber > 7) return;
    NSPoint point = [self guestPosition:event];
    void_input_mouse_warp((int)point.x, (int)point.y);
    void_input_mouse_button((int)event.buttonNumber, down);
}

- (void)mouseDown:(NSEvent *)event { [self recordButton:event down:YES]; }
- (void)mouseUp:(NSEvent *)event { [self recordButton:event down:NO]; }
- (void)rightMouseDown:(NSEvent *)event { [self recordButton:event down:YES]; }
- (void)rightMouseUp:(NSEvent *)event { [self recordButton:event down:NO]; }
- (void)otherMouseDown:(NSEvent *)event { [self recordButton:event down:YES]; }
- (void)otherMouseUp:(NSEvent *)event { [self recordButton:event down:NO]; }

- (void)scrollWheel:(NSEvent *)event
{
    if (!_inputActive) return;
    _scroll += event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 12 : 120);
    int delta = (int)_scroll;
    _scroll -= delta;
    if (delta) void_input_mouse_wheel(delta);
}
@end
