#import "ControllerHaptics.h"
#import <CoreHaptics/CoreHaptics.h>
#import <QuartzCore/QuartzCore.h>
extern void void_log(const char *, ...);

@interface UT3HapticMotor : NSObject
@property(strong) CHHapticEngine *engine;
@property(strong) id<CHHapticPatternPlayer> player;
@property(nonatomic) uint16_t speed;
@property(nonatomic) CFTimeInterval started;
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL failed;
- (instancetype)initWithDevice:(GCDeviceHaptics *)device locality:(GCHapticsLocality)locality;
- (BOOL)update:(uint16_t)speed;
- (void)stop;
@end

@implementation UT3HapticMotor
- (instancetype)initWithDevice:(GCDeviceHaptics *)device locality:(GCHapticsLocality)locality
{
    if(!(self=[super init]))return nil;
    _engine=[device createEngineWithLocality:locality];
    if(!_engine)return nil;
    _engine.playsHapticsOnly=YES;
    __weak UT3HapticMotor *weak=self;
    _engine.stoppedHandler=^(CHHapticEngineStoppedReason reason) {
        dispatch_async(dispatch_get_main_queue(),^{
            UT3HapticMotor *motor=weak;
            motor.ready=NO;motor.player=nil;motor.speed=0;
        });
    };
    _engine.resetHandler=^{
        dispatch_async(dispatch_get_main_queue(),^{
            UT3HapticMotor *motor=weak;
            motor.ready=NO;motor.player=nil;motor.speed=0;
        });
    };
    return self;
}
- (BOOL)update:(uint16_t)speed
{
    NSError *error=nil;
    if(!speed) {
        if(self.player && ![self.player stopAtTime:CHHapticTimeImmediate error:&error])goto failed;
        self.player=nil;self.speed=0;
        return YES;
    }
    if(!self.ready) {
        if(![self.engine startAndReturnError:&error])goto failed;
        self.ready=YES;
    }
    CFTimeInterval now=CACurrentMediaTime();
    // Every hardware event expires after 200 ms even if the run loop stalls.
    // Renew only while the shared runtime supplies a fresh nonzero command.
    if(!self.player || now-self.started>=.15) {
        if(self.player && ![self.player stopAtTime:CHHapticTimeImmediate error:&error])goto failed;
        CHHapticEventParameter *intensity=[[CHHapticEventParameter alloc]
            initWithParameterID:CHHapticEventParameterIDHapticIntensity value:1.0f];
        CHHapticEvent *event=[[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous
            parameters:@[intensity] relativeTime:0 duration:.20];
        CHHapticDynamicParameter *initial=[[CHHapticDynamicParameter alloc]
            initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl value:speed/65535.0f relativeTime:0];
        CHHapticPattern *pattern=[[CHHapticPattern alloc] initWithEvents:@[event] parameters:@[initial] error:&error];
        self.player=pattern ? [self.engine createPlayerWithPattern:pattern error:&error] : nil;
        if(!self.player || ![self.player startAtTime:CHHapticTimeImmediate error:&error])goto failed;
        self.started=now;
    } else if(speed!=self.speed) {
        CHHapticDynamicParameter *intensity=[[CHHapticDynamicParameter alloc]
            initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl value:speed/65535.0f relativeTime:0];
        if(![self.player sendParameters:@[intensity] atTime:CHHapticTimeImmediate error:&error])goto failed;
    }
    self.speed=speed;self.failed=NO;
    return YES;
failed:
    if(!self.failed)void_log("[apple-haptics] controller output error: %s",error.localizedDescription.UTF8String ?: "unknown");
    self.failed=YES;
    [self.player stopAtTime:CHHapticTimeImmediate error:nil];self.player=nil;
    self.ready=NO;self.speed=0;
    return NO;
}
- (void)stop
{
    [self.player stopAtTime:CHHapticTimeImmediate error:nil];self.player=nil;
    self.engine.stoppedHandler=^(CHHapticEngineStoppedReason reason) {};self.engine.resetHandler=^{};
    [self.engine stopWithCompletionHandler:nil];self.engine=nil;
    self.ready=NO;self.speed=0;
}
- (void)dealloc { [self stop]; }
@end

@implementation UT3ControllerHaptics {
    UT3HapticMotor *_left,*_right;
    BOOL _combined,_reported;
}
- (instancetype)initWithController:(GCController *)controller
{
    if(!(self=[super init]))return nil;
    GCDeviceHaptics *device=controller.haptics;
    NSSet<GCHapticsLocality> *locations=device.supportedLocalities;
    void_log("[apple-haptics] controller=%s haptics=%s localities=%s",
        controller.vendorName.UTF8String ?: "unknown",device?"available":"unsupported",
        locations.description.UTF8String ?: "none");
    if(!device)return nil;
    if([locations containsObject:GCHapticsLocalityLeftHandle] &&
       [locations containsObject:GCHapticsLocalityRightHandle]) {
        _left=[[UT3HapticMotor alloc] initWithDevice:device locality:GCHapticsLocalityLeftHandle];
        _right=[[UT3HapticMotor alloc] initWithDevice:device locality:GCHapticsLocalityRightHandle];
        if(!_left||!_right) { [_left stop];[_right stop];_left=nil;_right=nil; }
    }
    if(!_left) {
        _combined=YES;
        _left=[[UT3HapticMotor alloc] initWithDevice:device locality:GCHapticsLocalityDefault];
    }
    if(!_left) {
        void_log("[apple-haptics] controller did not provide a usable haptic engine");
        return nil;
    }
    return self;
}
- (void)updateMotors:(uint32_t)motors
{
    uint16_t left=motors>>16,right=motors;
    BOOL ok=YES;
    if(_combined)ok=[_left update:MAX(left,right)];
    else { ok=[_left update:left];ok=[_right update:right]&&ok; }
    if(motors && _left && ok && !_reported) {
        _reported=YES;
        void_log("[apple-haptics] first game rumble submitted to controller: %u/%u (%s)",
            left,right,_combined?"combined":"separate handles");
    }
}
- (void)stop { [_left stop];[_right stop];_left=nil;_right=nil; }
- (void)dealloc { [self stop]; }
@end
