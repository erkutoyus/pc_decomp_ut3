#import "../DataPaths.h"
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>
#import "GameView.h"
#include "runtime.h"
#include "../ProductKey.h"
#include <stdatomic.h>
#include <mach/mach.h>
void ut3_apple_set_suspended(int);
#if defined(UT3_APPLE_OPENAL)
void ut3_openal_pause(int);
void ut3_openal_log_stats(void);
void ut3_apple_set_audio_logger(void (*)(void));
const char *ut3_apple_profile_world(void);
static void iosRuntimeStats(void)
{
    ut3_openal_log_stats();
    const char *profile=getenv("UT3_PROFILE");
    if(!profile||strcmp(profile,"1"))return;
    task_vm_info_data_t memory={0};
    mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
    kern_return_t result=task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&memory,&count);
    fprintf(stderr,"[ios-profile] world=%s thermal=%ld footprint_mib=%.1f task_info=%d\n",
            ut3_apple_profile_world(),(long)NSProcessInfo.processInfo.thermalState,
            result==KERN_SUCCESS?(double)memory.phys_footprint/(1024*1024):-1.0,result);
}
#endif
#if defined(UT3_VULKAN_PROBE_LIBRARY)
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <vulkan/vulkan.h>
int ut3_apple_validate_vulkan(CAMetalLayer *, const char *);
#if defined(UT3_APPLE_DXVK)
#include "MetalPresentation.h"
void ut3_ios_set_vulkan_loader(PFN_vkGetInstanceProcAddr);
void ut3_apple_request_guest_close(void);
#endif

@interface UT3IOSMetalView : UIView
@end
@implementation UT3IOSMetalView
+ (Class)layerClass { return CAMetalLayer.class; }
@end
#endif

static _Atomic uint32_t batteryFacts = 0xffffff;
void ut3_apple_power_status(uint8_t *ac, uint8_t *battery, uint8_t *percent)
{
    uint32_t facts = atomic_load_explicit(&batteryFacts, memory_order_relaxed);
    *ac = facts >> 16;
    *battery = facts >> 8;
    *percent = facts;
}

@interface UT3IOSScene : UIResponder <UIWindowSceneDelegate>
@property(strong, nonatomic) UIWindow *window;
@property(strong, nonatomic) UILabel *status;
@property(strong, nonatomic) UT3IOSGameView *gameView;
@property(nonatomic) BOOL audioReady;
@property(nonatomic) BOOL interrupted;
@property(nonatomic) BOOL sceneActive;
@property(nonatomic) BOOL diagnostics;
@property(nonatomic) BOOL benchmark;
@property(nonatomic) BOOL measurementComplete;
@property(strong,nonatomic) UIButton *keyboardButton;
@property(strong,nonatomic) NSTimer *keyboardTimer;
@property(strong,nonatomic) NSTimer *startupTimer;
@end

@implementation UT3IOSScene
- (BOOL)prepareAudio
{
#if defined(UT3_APPLE_OPENAL)
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSError *error = nil;
    if (![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:&error] ||
        ![session setActive:YES error:&error]) {
        self.status.text = [NSString stringWithFormat:@"Could not start audio: %@", error.localizedDescription];
        return NO;
    }
    self.audioReady = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioInterrupted:)
                                              name:AVAudioSessionInterruptionNotification object:session];
    ut3_apple_set_audio_logger(iosRuntimeStats);
    setenv("UT3_AUDIO_METRICS", "1", 1);
    fprintf(stderr, "[ios-audio] session active: rate=%.0f channels=%ld route=%s\n", session.sampleRate,
            (long)session.outputNumberOfChannels, session.currentRoute.outputs.firstObject.portType.UTF8String);
    return YES;
#else
    self.status.text = @"This build has no iOS audio backend.";
    return NO;
#endif
}
- (void)audioInterrupted:(NSNotification *)note
{
#if defined(UT3_APPLE_OPENAL)
    if(!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(),^{[self audioInterrupted:note];});return;
    }
    self.interrupted = [note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan;
    if (self.interrupted) { ut3_openal_pause(1);fprintf(stderr,"[ios-audio] interruption began\n"); }
    else if (self.sceneActive&&!self.measurementComplete) [self resumeAudio];
#endif
}
- (void)resumeAudio
{
#if defined(UT3_APPLE_OPENAL)
    if(!self.audioReady)return;
    // End notifications are not guaranteed across application suspension.
    // Re-establish the session on foreground activation rather than trusting
    // a stale interruption flag, then reopen/resume the retained AL device.
    ut3_openal_pause(1);
    NSError *error=nil;
    if([AVAudioSession.sharedInstance setActive:YES error:&error]) {
        self.interrupted=NO;
        ut3_openal_pause(0);
        fprintf(stderr,"[ios-audio] foreground recovery requested: rate=%.0f\n",AVAudioSession.sharedInstance.sampleRate);
    } else fprintf(stderr,"[ios-audio] session recovery failed: %s\n",error.localizedDescription.UTF8String);
#endif
}
- (void)hideKeyboardButton
{
    [self.keyboardTimer invalidate];self.keyboardTimer=nil;self.keyboardButton.hidden=YES;
}
- (void)holdKeyboardButton { [self.keyboardTimer invalidate];self.keyboardTimer=nil; }
- (void)revealKeyboardButton
{
    self.keyboardButton.hidden=NO;
    [self.keyboardTimer invalidate];
    __weak UT3IOSScene *weak=self;
    self.keyboardTimer=[NSTimer timerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
        [weak hideKeyboardButton];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.keyboardTimer forMode:NSRunLoopCommonModes];
}
- (void)toggleKeyboard { [self hideKeyboardButton];[self.gameView toggleKeyboard]; }
- (void)sceneWillResignActive:(UIScene *)scene
{
    self.sceneActive=NO;
    [self hideKeyboardButton];
    [self.gameView setInputActive:NO];
    ut3_apple_set_suspended(1);
#if defined(UT3_APPLE_OPENAL)
    if (self.audioReady) ut3_openal_pause(1);
#endif
    UIApplication.sharedApplication.idleTimerDisabled = NO;
    fprintf(stderr,"[ios] inactive: input released, engine and audio paused\n");
}
- (void)sceneDidEnterBackground:(UIScene *)scene
{
#if defined(UT3_APPLE_OPENAL)
    if(self.audioReady) {
        NSError *error=nil;
        [AVAudioSession.sharedInstance setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
        fprintf(stderr,"[ios-audio] background session deactivated%s\n",error?" with error":"");
    }
#endif
}
- (void)sceneDidBecomeActive:(UIScene *)scene
{
    self.sceneActive=YES;
    if (!self.gameView) {
        if(self.diagnostics)UIApplication.sharedApplication.idleTimerDisabled=YES;
        return;
    }
    if(self.measurementComplete) {
        UIApplication.sharedApplication.idleTimerDisabled=YES;
        return;
    }
    [self.gameView setInputActive:!self.benchmark];
#if defined(UT3_APPLE_OPENAL)
    [self resumeAudio];
#endif
    ut3_apple_set_suspended(0);
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    fprintf(stderr,"[ios] active: engine resumed\n");
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options
{
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    for(NSString *argument in NSProcessInfo.processInfo.arguments)
        if([argument hasPrefix:@"--validate-"]||[argument isEqualToString:@"--selftest"])self.diagnostics=YES;
    if(self.diagnostics)UIApplication.sharedApplication.idleTimerDisabled=YES;
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.blackColor;
    self.window.rootViewController = controller;
    self.status = [[UILabel alloc] initWithFrame:CGRectZero];
    self.status.numberOfLines = 0;
    self.status.textColor = UIColor.whiteColor;
    self.status.font = [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightRegular];
    self.status.translatesAutoresizingMaskIntoConstraints = NO;
    [controller.view addSubview:self.status];
    [NSLayoutConstraint activateConstraints:@[
        [self.status.leadingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.leadingAnchor constant:24],
        [self.status.trailingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.trailingAnchor constant:-24],
        [self.status.centerYAnchor constraintEqualToAnchor:controller.view.centerYAnchor]
    ]];
    [self.window makeKeyAndVisible];
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSError *pathError=nil;
    if(!UT3PrepareDataRoot(documents,[documents URLByAppendingPathComponent:@"UserData"],YES,&pathError)) {
        self.status.text=[NSString stringWithFormat:@"Could not prepare Unreal Tournament 3 folders. %@",pathError.localizedDescription];
        return;
    }
    NSURL *root=documents;
    fprintf(stderr,"[ios-paths] shared files root=%s\n",root.fileSystemRepresentation);
    NSURL *game = [root URLByAppendingPathComponent:@"Game" isDirectory:YES];
    NSURL *data = [root URLByAppendingPathComponent:@"UserData" isDirectory:YES];
    if([NSProcessInfo.processInfo.arguments containsObject:@"--validate-sha1"]) {
        int ut3_validate_sha1_rotates(void);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            int result=ut3_validate_sha1_rotates();
            fprintf(stderr,"[ios-profile] SHA1 differential fixture status %d\n",result);
            dispatch_async(dispatch_get_main_queue(),^{self.status.text=result?@"SHA1 validation failed.":@"SHA1 original/candidate validation passed.";});
        });
        return;
    }
#if defined(UT3_VULKAN_PROBE_LIBRARY)
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--validate-vulkan"]) {
        UT3IOSMetalView *view = [[UT3IOSMetalView alloc] initWithFrame:controller.view.bounds];
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [controller.view insertSubview:view atIndex:0];
        CAMetalLayer *layer = (CAMetalLayer *)view.layer;
        layer.device = MTLCreateSystemDefaultDevice();
        layer.contentsScale = self.window.screen.scale;
        layer.drawableSize = CGSizeMake(view.bounds.size.width * layer.contentsScale,
                                         view.bounds.size.height * layer.contentsScale);
        [controller.view layoutIfNeeded];
        [CATransaction flush];
        self.status.text = @"Checking Vulkan presentation…";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSURL *image = [documents URLByAppendingPathComponent:@"vulkan-clear.ppm"];
            int result = ut3_apple_validate_vulkan(layer, image.fileSystemRepresentation);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.status.text = result ? @"Vulkan presentation failed. See device console."
                                          : @"Vulkan clear, readback and presentation passed.";
            });
        });
        return;
    }
#endif
    if (![NSFileManager.defaultManager isReadableFileAtPath:[game URLByAppendingPathComponent:@"Binaries/UT3.exe"].path]) {
        self.status.text = @"Open this app in Finder → iPhone → Files, or Files → On My iPhone. Put Game and cdkey.txt directly in this app’s shared files, beside UserData. Files already calls this app Unreal Tournament 3; do not add another folder with that name.\n\nGame must contain Binaries, Engine and UTGame (Game/Binaries/UT3.exe). Then relaunch. Do not create a Documents folder.";
        fprintf(stderr, "[ut3-ios] waiting for Game/Binaries/UT3.exe in app shared files\n");
        return;
    }
    self.status.text = @"Checking the ARM64 runtime…";
    if (ut3_apple_configure_product_key(game.fileSystemRepresentation, data.fileSystemRepresentation,
                                      root.fileSystemRepresentation) < 0) {
        self.status.text = @"Could not read cdkey.txt. Use one plain-text key in XXXX-XXXX-XXXX-XXXX format, then restart.";
        return;
    }
#if defined(UT3_APPLE_DXVK)
    BOOL testD3D9 = [NSProcessInfo.processInfo.arguments containsObject:@"--validate-d3d9"];
    BOOL captureGame = [NSProcessInfo.processInfo.arguments containsObject:@"--validate-game"] ||
                       [NSProcessInfo.processInfo.arguments containsObject:@"--exit-after-frame"];
    BOOL testRuntime = [NSProcessInfo.processInfo.arguments containsObject:@"--selftest"];
    BOOL runGame = captureGame || (!testD3D9 && !testRuntime);
    if (testD3D9 || runGame) {
        UT3IOSGameView *view = [[UT3IOSGameView alloc] initWithFrame:controller.view.bounds];
        self.gameView = view;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [controller.view insertSubview:view atIndex:0];
        CAMetalLayer *layer = (CAMetalLayer *)view.layer;
        view.contentScaleFactor = self.window.screen.scale;
        layer.contentsScale = self.window.screen.scale;
        [controller.view layoutIfNeeded];
        if (!ut3_apple_metal_attach(layer)) {
            self.status.text = @"Could not create the Metal presentation target.";
            return;
        }
        layer.drawableSize = CGSizeMake(view.bounds.size.width * self.window.screen.scale,
                                         view.bounds.size.height * self.window.screen.scale);
        ut3_apple_metal_resize(layer.drawableSize.width, layer.drawableSize.height);
        ut3_ios_set_vulkan_loader(vkGetInstanceProcAddr);
        setenv("UT3_RENDERER", "dxvk", 1);
        setenv("DXVK_STATE_CACHE_PATH", data.fileSystemRepresentation, 1);
        setenv("DXVK_LOG_PATH", data.fileSystemRepresentation, 1);
        if(!getenv("UT3_SHADER_WARMUP_CACHE")) {
            NSURL *cache=[data URLByAppendingPathComponent:@"ut3-09751861-shaders-v1.bin"];
            setenv("UT3_SHADER_WARMUP_CACHE",cache.fileSystemRepresentation,1);
        }
        // Keep the saved resolution selectable; cap work instead of allowing
        // a lower resolution to turn into an unintended higher frame rate.
        setenv("UT3_FPS_LIMIT","60",0);
        // Container UUIDs change on development installs. A relative trace
        // name is resolved inside this installation's writable userdata.
        const char *trace=getenv("UT3_FRAME_TRACE");
        if(trace&&*trace&&trace[0]!='/') {
            NSURL *file=[data URLByAppendingPathComponent:[NSString stringWithUTF8String:trace]];
            setenv("UT3_FRAME_TRACE",file.fileSystemRepresentation,1);
        }
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--dynamic-samplers"])
            setenv("DXVK_CONFIG", "d3d9.forceSamplerTypeSpecConstants = True", 1);
        if (runGame) {
            if (![self prepareAudio]) return;
            UIApplication.sharedApplication.idleTimerDisabled = YES;
            [view setInputActive:YES];
            UIButton *keyboard = [UIButton buttonWithType:UIButtonTypeSystem];
            self.keyboardButton=keyboard;
            keyboard.hidden=YES;
            [keyboard setTitle:@"Keyboard" forState:UIControlStateNormal];
            keyboard.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.7];
            keyboard.tintColor = UIColor.whiteColor;
            keyboard.translatesAutoresizingMaskIntoConstraints = NO;
            [keyboard addTarget:self action:@selector(toggleKeyboard) forControlEvents:UIControlEventTouchUpInside];
            [keyboard addTarget:self action:@selector(holdKeyboardButton) forControlEvents:UIControlEventTouchDown];
            [keyboard addTarget:self action:@selector(revealKeyboardButton) forControlEvents:UIControlEventTouchUpOutside|UIControlEventTouchCancel];
            __weak UT3IOSScene *weakScene=self;
            view.touchActivity=^{[weakScene revealKeyboardButton];};
            [controller.view addSubview:keyboard];
            [NSLayoutConstraint activateConstraints:@[
                [keyboard.topAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.topAnchor constant:4],
                [keyboard.trailingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.trailingAnchor constant:-8],
                [keyboard.widthAnchor constraintEqualToConstant:96], [keyboard.heightAnchor constraintEqualToConstant:34]
            ]];
            NSURL *capture = [data URLByAppendingPathComponent:@"ut3-first-frame.ppm"];
            if (captureGame) setenv("UT3_CAPTURE_FRAME", capture.fileSystemRepresentation, 1);
            setenv("UT3_RENDER_WIDTH", "640", 1);
            setenv("UT3_RENDER_HEIGHT", "480", 1);
            const char *launch = getenv("UT3_COMMAND_LINE");
            if (!launch || !*launch)
                setenv("UT3_COMMAND_LINE", "\"C:\\Games\\UT3\\Binaries\\UT3.exe\" UTFrontEnd -nosplash -nomovie -nosteam -forcelogflush -onethread", 1);
            const char *duration=getenv("UT3_BENCHMARK_SECONDS");
            if(duration&&*duration) {
                char *end=NULL;unsigned long seconds=strtoul(duration,&end,10);
                if(end&&!*end&&seconds>=30&&seconds<=600) {
                    self.benchmark=YES;
                    [self.gameView setInputActive:NO];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)seconds*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                        self.measurementComplete=YES;
                        [self.gameView setInputActive:NO];
                        ut3_apple_set_suspended(1);
#if defined(UT3_APPLE_OPENAL)
                        ut3_openal_pause(1);
#endif
                        fprintf(stderr,"[ios-profile] measurement window complete; engine/audio paused, diagnostic screen kept awake\n");
                    });
                }
            }
            self.status.hidden = NO;
            self.status.text = @"Starting UT3…\nLoading game data and graphics. The first launch can take a minute.";
            self.status.backgroundColor=[UIColor colorWithWhite:0 alpha:0.75];
            __weak UT3IOSScene *loadingScene=self;
            self.startupTimer=[NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) {
                UT3IOSScene *scene=loadingScene;
                if(!scene || ut3_apple_metal_has_presented()) {
                    scene.status.hidden=YES;
                    [timer invalidate];scene.startupTimer=nil;
                    if(scene)fprintf(stderr,"[ut3-ios] startup message dismissed after first accepted Present\n");
                }
            }];
            if ([NSProcessInfo.processInfo.arguments containsObject:@"--exit-after-frame"]) {
                // Diagnostic-only stop: let the engine consume its own exit
                // request after a captured frame, rather than terminating it
                // in the middle of a GPU command stream.
                if ([NSFileManager.defaultManager fileExistsAtPath:capture.path] &&
                    ![NSFileManager.defaultManager removeItemAtURL:capture error:NULL]) {
                    self.status.hidden = NO;
                    self.status.text = @"Could not replace the previous frame capture.";
                    return;
                }
                __block dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
                dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
                dispatch_source_set_event_handler(timer, ^{
                    if ([NSFileManager.defaultManager isReadableFileAtPath:capture.path]) {
                        ut3_apple_request_guest_close();
                        dispatch_source_cancel(timer);
                        timer = nil;
                    }
                });
                dispatch_resume(timer);
            }
        }
    }
#endif
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
#if defined(UT3_APPLE_DXVK)
        int result = runGame ? ut3_game_main(game.fileSystemRepresentation, data.fileSystemRepresentation, 0)
                             : testD3D9 ? ut3_validate_d3d9(game.fileSystemRepresentation, data.fileSystemRepresentation)
                             : ut3_validate_startup(game.fileSystemRepresentation, data.fileSystemRepresentation);
        if (testD3D9 || runGame) ut3_apple_metal_detach();
#else
        int result = ut3_validate_startup(game.fileSystemRepresentation, data.fileSystemRepresentation);
#endif
        #if defined(UT3_APPLE_DXVK)
        fprintf(stderr, "[ut3-ios] %s finished with status %d\n", runGame ? "UT3 game" : testD3D9 ? "D3D9 probe" : "runtime self-test", result);
#else
        fprintf(stderr, "[ut3-ios] runtime self-test finished with status %d\n", result);
#endif
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.startupTimer invalidate];self.startupTimer=nil;
            [self.gameView stopInput];
            UIApplication.sharedApplication.idleTimerDisabled = self.diagnostics && self.sceneActive;
#if defined(UT3_APPLE_DXVK)
            if (runGame) {
                self.status.hidden = NO;
                self.status.text = [NSString stringWithFormat:@"UT3 returned status %d. See device logs.", result];
                return;
            }
            if (testD3D9) {
                self.status.text = result ? [NSString stringWithFormat:@"D3D9 probe failed (%d). See device logs.", result]
                                          : @"D3D9 fixture passed. This is not a UT3 game frame.";
                return;
            }
#endif
            self.status.text = result ? [NSString stringWithFormat:@"Runtime self-test failed (%d). See UserData/ut3.log.", result]
                                      : @"Native ARM64 runtime self-test passed.";
        });
    });
    return;
}
- (void)sceneDidDisconnect:(UIScene *)scene
{
    [self.startupTimer invalidate];self.startupTimer=nil;
    [self hideKeyboardButton];
    self.gameView.touchActivity=nil;
    [self.gameView stopInput];
    [NSNotificationCenter.defaultCenter removeObserver:self];
#if defined(UT3_APPLE_DXVK)
    ut3_apple_request_guest_close();
#endif
    ut3_apple_set_suspended(0);
    UIApplication.sharedApplication.idleTimerDisabled = NO;
}
@end

@interface UT3IOSApplication : UIResponder <UIApplicationDelegate>
@end
@implementation UT3IOSApplication
- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options
{
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"UT3" sessionRole:session.role];
    configuration.delegateClass = UT3IOSScene.class;
    return configuration;
}
@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(UT3IOSApplication.class));
    }
}
