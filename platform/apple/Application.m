#import "DataPaths.h"
#import "GameView.h"
#import "ShellValidation.h"
#if defined(UT3_APPLE_DXVK)
#import "MetalPresentation.h"
void ut3_apple_set_adapter_identity(const char *);
#endif
#include "runtime.h"
#include "ProductKey.h"
#include <errno.h>
#include <dlfcn.h>
#include <os/log.h>
#include <unistd.h>
void ut3_apple_request_guest_close(void);
void ut3_apple_set_exit_callback(void (*)(uint32_t));
#if defined(UT3_APPLE_OPENAL)
void ut3_apple_set_audio_logger(void (*)(void));
void ut3_openal_log_stats(void);
#endif

typedef NS_ENUM(NSUInteger, UT3Validation) {
    UT3ValidationNone, UT3ValidationWindow, UT3ValidationEarlyQuit,
    UT3ValidationD3D9, UT3ValidationGame
};

@interface UT3Application : NSObject <NSApplicationDelegate, NSWindowDelegate>
- (instancetype)initWithGame:(NSURL *)game data:(NSURL *)data validation:(UT3Validation)validation;
- (void)guestDidExit:(uint32_t)code;
@end

static void guest_did_exit(uint32_t code)
{
    void (^finish)(void) = ^{
        id delegate = NSApp.delegate;
        if ([delegate isKindOfClass:UT3Application.class]) [delegate guestDidExit:code];
    };
    if (NSThread.isMainThread) finish();
    else dispatch_sync(dispatch_get_main_queue(), finish);
}

#if defined(UT3_APPLE_DXVK)
static NSString *graphics_backend(void)
{
    NSString *choice=[NSUserDefaults.standardUserDefaults stringForKey:@"UT3VulkanBackend"];
    return [choice isEqual:@"moltenvk"] ? @"moltenvk" : @"kosmickrisp";
}
static NSString *prepare_vulkan(void)
{
    NSString *sdk = [NSBundle.mainBundle objectForInfoDictionaryKey:@"UT3VulkanSDKPath"];
    if (sdk.length && !sdk.isAbsolutePath)
        sdk = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:sdk];
    const char *loader = getenv("UT3_VULKAN_LOADER");
    if (!loader || !*loader) {
        NSString *path = [sdk stringByAppendingPathComponent:@"lib/libvulkan.1.dylib"];
        if (!path.length || ![NSFileManager.defaultManager isReadableFileAtPath:path] ||
            setenv("UT3_VULKAN_LOADER", path.fileSystemRepresentation, 1))
            return @"The configured Vulkan SDK is unavailable. Set UT3_VULKAN_SDK when building the app.";
        loader = getenv("UT3_VULKAN_LOADER");
    }
    const char *driver = getenv("VK_DRIVER_FILES");
    const char *legacyDriver = getenv("VK_ICD_FILENAMES");
    if ((!driver || !*driver) && (!legacyDriver || !*legacyDriver)) {
        NSString *icd=[graphics_backend() isEqual:@"moltenvk"] ? @"MoltenVK_icd.json" : @"libkosmickrisp_icd.json";
        NSString *path = [[sdk stringByAppendingPathComponent:@"share/vulkan/icd.d"] stringByAppendingPathComponent:icd];
        if (!path.length || ![NSFileManager.defaultManager isReadableFileAtPath:path] ||
            setenv("VK_DRIVER_FILES", path.fileSystemRepresentation, 1))
            return @"The selected graphics backend is missing. Rebuild or reinstall the app.";
    }
    void *library = dlopen(loader, RTLD_NOW | RTLD_LOCAL);
    if (!library || !dlsym(library, "vkGetInstanceProcAddr")) {
        const char *detail = dlerror();
        NSString *message = [NSString stringWithFormat:@"Could not load Vulkan: %s", detail ?: loader];
        if (library) dlclose(library);
        return message;
    }
    dlclose(library);
    return nil;
}
#endif

@implementation UT3Application {
    NSURL *_game, *_data, *_defaultRoot;
    NSWindow *_window;
    UT3GameView *_view;
    NSTextField *_status;
    NSButton *_choose;
    FILE *_logFile;
    UT3Validation _validation;
    BOOL _workerStarted, _workerRunning, _terminationPending, _validationPassed;
}

- (instancetype)initWithGame:(NSURL *)game data:(NSURL *)data validation:(UT3Validation)validation
{
    self = [super init];
    if (self) {
        _game = game;
        _data = data;
        _validation = validation;
    }
    return self;
}

- (void)log:(NSString *)message
{
    os_log(OS_LOG_DEFAULT, "UT3 AppKit: %{public}@", message);
    fprintf(stderr, "[ut3-shell] %s\n", message.UTF8String);
    if (_logFile) {
        fprintf(_logFile, "[ut3-shell] %s\n", message.UTF8String);
        fflush(_logFile);
    }
}

- (void)installMenu
{
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *applicationItem = [[NSMenuItem alloc] init];
    [menu addItem:applicationItem];
    NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:@"Unreal Tournament 3"];
    [applicationMenu addItemWithTitle:@"Quit Unreal Tournament 3" action:@selector(terminate:) keyEquivalent:@"q"];
    applicationItem.submenu = applicationMenu;
    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    [menu addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    NSMenuItem *open = [fileMenu addItemWithTitle:@"Choose Game Folder…" action:@selector(chooseGame:) keyEquivalent:@"o"];
    open.target = self;
    [fileMenu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];
    fileItem.submenu = fileMenu;
#if defined(UT3_APPLE_DXVK)
    NSMenuItem *graphicsItem=[[NSMenuItem alloc] init];
    [menu addItem:graphicsItem];
    NSMenu *graphics=[[NSMenu alloc] initWithTitle:@"Graphics"];
    for(NSString *backend in @[@"moltenvk",@"kosmickrisp"]) {
        NSMenuItem *item=[graphics addItemWithTitle:[backend isEqual:@"moltenvk"] ? @"MoltenVK" : @"KosmicKrisp"
            action:@selector(chooseGraphicsBackend:) keyEquivalent:@""];
        item.target=self;item.representedObject=backend;
    }
    [graphics addItem:NSMenuItem.separatorItem];
    NSMenuItem *sync=[graphics addItemWithTitle:@"Vertical Sync" action:@selector(toggleGraphicsSync:) keyEquivalent:@""];
    sync.target=self;
    graphicsItem.submenu=graphics;
#endif
    NSApp.mainMenu = menu;
}

#if defined(UT3_APPLE_DXVK)
- (void)graphicsSettingsChanged
{
    if(!_workerStarted)return;
    NSAlert *alert=[NSAlert new];
    alert.messageText=@"Graphics settings saved";
    alert.informativeText=@"Restart Unreal Tournament 3 to apply these settings.";
    [alert beginSheetModalForWindow:_window completionHandler:nil];
}
- (void)chooseGraphicsBackend:(NSMenuItem *)item
{
    [NSUserDefaults.standardUserDefaults setObject:item.representedObject forKey:@"UT3VulkanBackend"];
    [self graphicsSettingsChanged];
}
- (void)toggleGraphicsSync:(NSMenuItem *)item
{
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    [defaults setBool:![defaults boolForKey:@"UT3DisableVSync"] forKey:@"UT3DisableVSync"];
    [self graphicsSettingsChanged];
}
#endif

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
#if defined(UT3_APPLE_DXVK)
    if(item.action==@selector(chooseGraphicsBackend:))item.state=[item.representedObject isEqual:graphics_backend()] ? NSControlStateValueOn : NSControlStateValueOff;
    if(item.action==@selector(toggleGraphicsSync:))item.state=[NSUserDefaults.standardUserDefaults boolForKey:@"UT3DisableVSync"] ? NSControlStateValueOff : NSControlStateValueOn;
#endif
    return item.action != @selector(chooseGame:) || !_workerStarted;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self installMenu];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 960, 540)
                                         styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                           backing:NSBackingStoreBuffered defer:NO];
    _window.title = @"Unreal Tournament 3";
    _window.releasedWhenClosed = NO;
    _window.delegate = self;
    _window.acceptsMouseMovedEvents = YES;
    _view = [[UT3GameView alloc] initWithFrame:NSMakeRect(0, 0, 960, 540)];
    _window.contentView = _view;

    _status = [NSTextField wrappingLabelWithString:@"Choose your Unreal Tournament 3 installation once. Settings and profiles are in Documents/Unreal Tournament 3/UserData; put cdkey.txt in Documents/Unreal Tournament 3."];
    _status.alignment = NSTextAlignmentCenter;
    _choose = [NSButton buttonWithTitle:@"Choose Game Folder…" target:self action:@selector(chooseGame:)];
    NSStackView *content = [NSStackView stackViewWithViews:@[_status, _choose]];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.spacing = 12;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [_view addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:_view.centerXAnchor],
        [content.centerYAnchor constraintEqualToAnchor:_view.centerYAnchor],
        [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:_view.leadingAnchor constant:28],
        [content.trailingAnchor constraintLessThanOrEqualToAnchor:_view.trailingAnchor constant:-28]
    ]];
    [_window center];
    [NSApp activate];
    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_view];
    [_view updateDrawableSize];
    [_view setInputActive:_window.keyWindow];

    if(!_data) {
        NSError *error=nil;
        NSURL *documents=[NSFileManager.defaultManager URLForDirectory:NSDocumentDirectory
            inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
        NSURL *support=[NSFileManager.defaultManager URLForDirectory:NSApplicationSupportDirectory
            inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
        NSURL *legacy=[support URLByAppendingPathComponent:@"Unreal Tournament 3" isDirectory:YES];
        if(!documents || !UT3PrepareDataRoot(documents,legacy,NO,&error)) {
            [self startupFailed:[NSString stringWithFormat:@"Could not prepare Documents/Unreal Tournament 3. %@",error.localizedDescription ?: @""]];
            return;
        }
        _defaultRoot=UT3DataRoot(documents);
        _data=[_defaultRoot URLByAppendingPathComponent:@"UserData" isDirectory:YES];
        if(!_game && _validation==UT3ValidationNone) {
            _game=UT3RememberedGameFolder(_defaultRoot);
            if(_game)[self log:@"Using saved game folder location."];
        }
    }
    if (_game) [self startWithGame:_game];
}

- (void)chooseGame:(id)sender
{
    if (_workerStarted || _window.attachedSheet) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Select the folder containing Binaries, Engine, and UTGame.";
    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) {
            NSURL *game = panel.URL;
            dispatch_async(dispatch_get_main_queue(), ^{ [self startWithGame:game]; });
        }
    }];
}

- (void)startupFailed:(NSString *)message
{
    _status.stringValue = message;
    _status.hidden = NO;
    if (!_workerStarted) _choose.hidden = NO;
    [self log:message];
    if (_validation != UT3ValidationNone) [NSApp terminate:self];
}

- (void)startWithGame:(NSURL *)game
{
    if (_workerStarted) return;
    NSFileManager *files = NSFileManager.defaultManager;
    game = game.URLByStandardizingPath.URLByResolvingSymlinksInPath;
    if (![files isReadableFileAtPath:[game URLByAppendingPathComponent:@"Binaries/UT3.exe"].path]) {
        [self startupFailed:@"Choose a UT3 installation containing Binaries/UT3.exe."];
        return;
    }

    NSError *error = nil;
    NSURL *data = _data;
    data = data.URLByStandardizingPath.URLByResolvingSymlinksInPath;
    if ([data.path isEqualToString:game.path] || [data.path hasPrefix:[game.path stringByAppendingString:@"/"]]) {
        [self startupFailed:@"Choose a user-data directory outside the game installation."];
        return;
    }
    if (!data || ![files createDirectoryAtURL:data withIntermediateDirectories:YES attributes:nil error:&error]) {
        [self startupFailed:[NSString stringWithFormat:@"Could not create user data. %@", error.localizedDescription ?: @""]];
        return;
    }
    _logFile = fopen([data URLByAppendingPathComponent:@"shell.log"].fileSystemRepresentation, "w");
    if (!_logFile) {
        [self startupFailed:[NSString stringWithFormat:@"Could not open shell.log in %@.", data.path]];
        return;
    }
    _status.stringValue = @"Checking the game files and starting the ARM64 runtime…";
    if (ut3_apple_configure_product_key(game.fileSystemRepresentation, data.fileSystemRepresentation, _defaultRoot.fileSystemRepresentation) < 0) {
        [self startupFailed:@"Could not read cdkey.txt. Use one plain-text key in XXXX-XXXX-XXXX-XXXX format, then restart."];
        fclose(_logFile);
        _logFile = NULL;
        return;
    }
    if(_validation==UT3ValidationNone && _defaultRoot) {
        if(!UT3RememberGameFolder(_defaultRoot,game,&error))
            [self log:[NSString stringWithFormat:@"Could not remember game folder: %@",error.localizedDescription]];
        _game=game;
    }
    _choose.hidden = YES;
#if defined(UT3_APPLE_DXVK)
    if (_validation == UT3ValidationNone || _validation == UT3ValidationD3D9 || _validation == UT3ValidationGame) {
        NSString *graphicsError = prepare_vulkan();
        if (graphicsError) {
            [self startupFailed:graphicsError];
            fclose(_logFile);
            _logFile = NULL;
            return;
        }
        ut3_apple_set_adapter_identity(data.fileSystemRepresentation);
        ut3_apple_set_exit_callback(guest_did_exit);
#if defined(UT3_APPLE_OPENAL)
        ut3_apple_set_audio_logger(ut3_openal_log_stats);
#endif
        if (!ut3_apple_metal_attach(_view.presentationLayer)) {
            [self startupFailed:@"Could not attach the Metal presentation target."];
            return;
        }
        [self updatePresentation];
        setenv("DXVK_LOG_PATH", data.fileSystemRepresentation, 1);
        setenv("DXVK_STATE_CACHE_PATH", data.fileSystemRepresentation, 1);
        setenv("UT3_RENDERER", "dxvk", 1);
        if (_validation == UT3ValidationNone) {
            // The stock PC game requests immediate presentation with VSync
            // disabled. Default to synchronized presentation, with explicit
            // DXVK_CONFIG / UT3_FPS_LIMIT overrides retained for diagnostics.
            setenv("DXVK_CONFIG", [NSUserDefaults.standardUserDefaults boolForKey:@"UT3DisableVSync"] ? "d3d9.presentInterval = 0" : "d3d9.presentInterval = 1", 0);
            setenv("UT3_FPS_LIMIT", "60", 0);
            setenv("UT3_RENDER_WIDTH", "960", 0);
            setenv("UT3_RENDER_HEIGHT", "540", 0);
            setenv("UT3_COMMAND_LINE", "\"C:\\Games\\UT3\\Binaries\\UT3.exe\" UTFrontEnd -nosplash -nomovie -onethread", 0);
        }
        _status.hidden = YES;
        if (_validation == UT3ValidationGame) {
            NSURL *capture = [data URLByAppendingPathComponent:@"ut3-first-frame.ppm"];
            if (unlink(capture.fileSystemRepresentation) && errno != ENOENT) {
                [self startupFailed:@"Could not clear the previous frame capture."];
                return;
            }
            setenv("UT3_CAPTURE_FRAME", capture.fileSystemRepresentation, 1);
            setenv("UT3_COMMAND_LINE", "\"C:\\Games\\UT3\\Binaries\\UT3.exe\" UTFrontEnd -nosplash -nomovie -nosound -nosteam -forcelogflush -onethread -ResX=640 -ResY=480", 0);
        }
    }
#endif
    _workerStarted = YES;
    _workerRunning = YES;
    [self log:[NSString stringWithFormat:@"Window ready (%ld), %.0fx%.0f backing pixels; user data %@",
               (long)_window.windowNumber, _view.presentationLayer.drawableSize.width,
               _view.presentationLayer.drawableSize.height, data.path]];
    dispatch_group_t worker = dispatch_group_create();
    __block int result;
    dispatch_group_async(worker, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
#if defined(UT3_APPLE_DXVK)
        if (self->_validation == UT3ValidationD3D9) {
            result = ut3_validate_d3d9(game.fileSystemRepresentation, data.fileSystemRepresentation);
            return;
        }
        if (self->_validation == UT3ValidationGame || self->_validation == UT3ValidationNone) {
            result = ut3_game_main(game.fileSystemRepresentation, data.fileSystemRepresentation, 0);
            return;
        }
#endif
        result = ut3_validate_startup(game.fileSystemRepresentation, data.fileSystemRepresentation);
    });
    dispatch_group_notify(worker, dispatch_get_main_queue(), ^{
        self->_workerRunning = NO;
        [self log:[NSString stringWithFormat:@"Runtime worker completed with status %d", result]];
        if (self->_terminationPending) {
            self->_validationPassed = self->_validation == UT3ValidationEarlyQuit && result == 0;
            [NSApp replyToApplicationShouldTerminate:YES];
            return;
        }
        if (result) {
            [self startupFailed:[NSString stringWithFormat:@"Runtime startup failed (%d). See ut3.log in %@.", result, data.path]];
            return;
        }
        self->_status.stringValue = @"Runtime startup passed.";
        if (self->_validation == UT3ValidationD3D9 || self->_validation == UT3ValidationGame) {
            self->_validationPassed = self->_validation == UT3ValidationD3D9 ||
                [files isReadableFileAtPath:[data URLByAppendingPathComponent:@"ut3-first-frame.ppm"].path];
            [self->_window performClose:nil];
        }
        if (self->_validation == UT3ValidationWindow) {
            self->_validationPassed = UT3ValidateWindowAndInput(self->_window, self->_view);
            [self log:self->_validationPassed ? @"Window, drawable sizing, keyboard, mouse, focus release and XInput snapshot PASS"
                                             : @"Window or input validation FAILED"];
            [self->_window performClose:nil];
        }
    });
    if (_validation == UT3ValidationEarlyQuit) [NSApp terminate:self];
}

- (void)updatePresentation
{
    [_view updateDrawableSize];
#if defined(UT3_APPLE_DXVK)
    CGSize size = _view.presentationLayer.drawableSize;
    ut3_apple_metal_resize((uint32_t)size.width, (uint32_t)size.height);
#endif
}

- (void)windowDidResize:(NSNotification *)notification { [self updatePresentation]; }
- (void)windowDidChangeBackingProperties:(NSNotification *)notification { [self updatePresentation]; }
- (void)windowDidBecomeKey:(NSNotification *)notification { [_view setInputActive:YES]; }
- (void)windowDidResignKey:(NSNotification *)notification { [_view setInputActive:NO]; }
- (void)applicationWillResignActive:(NSNotification *)notification { [_view setInputActive:NO]; }
- (void)applicationDidBecomeActive:(NSNotification *)notification { [_view setInputActive:_window.keyWindow]; }
- (BOOL)windowShouldClose:(NSWindow *)window
{
#if defined(UT3_APPLE_DXVK)
    if (_workerRunning && (_validation == UT3ValidationNone || _validation == UT3ValidationGame)) {
        [NSApp terminate:self];
        return NO;
    }
#endif
    return YES;
}
- (void)windowWillClose:(NSNotification *)notification { [_view stopInput]; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application { return YES; }

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)application
{
    [_view stopInput];
    if (!_workerRunning) return NSTerminateNow;
    _terminationPending = YES;
#if defined(UT3_APPLE_DXVK)
    if (_validation == UT3ValidationNone || _validation == UT3ValidationGame)
        ut3_apple_request_guest_close();
#endif
    [self log:@"Termination deferred until the runtime worker completes"];
    return NSTerminateLater;
}

- (void)guestDidExit:(uint32_t)code
{
    _workerRunning = NO;
    [self log:[NSString stringWithFormat:@"Guest ExitProcess completed with status %u", code]];
    [self tearDown];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [self tearDown];
}

- (void)tearDown
{
    [_view stopInput];
#if defined(UT3_APPLE_DXVK)
    ut3_apple_metal_detach();
#endif
    _window.delegate = nil;
    _window.contentView = nil;
    [_window close];
    BOOL released = _view.window == nil && !_workerRunning && !_window.visible;
    _view = nil;
    _window = nil;
    _choose = nil;
    _status = nil;
    [self log:released ? @"Window, view and input disconnected; no runtime worker outstanding"
                       : @"Shell resource teardown FAILED"];
    if (_validation != UT3ValidationNone) {
        BOOL graphics = _validation == UT3ValidationD3D9 || _validation == UT3ValidationGame;
        [self log:[NSString stringWithFormat:@"PHASE %d VALIDATION %@",
                   graphics ? 3 : 2, released && _validationPassed ? @"PASS" : @"FAILED"]];
    }
    if (_logFile) {
        fclose(_logFile);
        _logFile = NULL;
    }
}
@end

int main(int argc, const char **argv)
{
    @autoreleasepool {
        NSURL *game = nil, *data = nil;
        UT3Validation validation = UT3ValidationNone;
        for (int i = 1; i < argc; ++i) {
            if ((!strcmp(argv[i], "--game") || !strcmp(argv[i], "--data")) && i + 1 < argc) {
                BOOL isGame = !strcmp(argv[i], "--game");
                NSString *path = [NSFileManager.defaultManager stringWithFileSystemRepresentation:argv[i+1] length:strlen(argv[i+1])];
                NSURL *url = [NSURL fileURLWithPath:path isDirectory:YES];
                if (isGame) game = url; else data = url;
                ++i;
            } else if (!strcmp(argv[i], "--validate-shell")) validation = UT3ValidationWindow;
            else if (!strcmp(argv[i], "--validate-early-quit")) validation = UT3ValidationEarlyQuit;
#if defined(UT3_APPLE_DXVK)
            else if (!strcmp(argv[i], "--validate-d3d9")) validation = UT3ValidationD3D9;
            else if (!strcmp(argv[i], "--capture-first-frame")) validation = UT3ValidationGame;
#endif
            else if (!strncmp(argv[i], "-psn_", 5)) continue;
            else {
                fputs("usage: UT3 [--game PATH] [--data PATH] [--validate-shell | --validate-early-quit"
#if defined(UT3_APPLE_DXVK)
                      " | --validate-d3d9 | --capture-first-frame"
#endif
                      "]\n", stderr);
                return 64;
            }
        }
        if (validation != UT3ValidationNone && !game) {
            fputs("Validation requires --game PATH.\n", stderr);
            return 64;
        }
        [NSApplication sharedApplication];
        if (!NSScreen.screens.count) {
            fputs("AppKit requires a graphical login session.\n", stderr);
            return 69;
        }
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        __attribute__((objc_precise_lifetime)) UT3Application *delegate =
            [[UT3Application alloc] initWithGame:game data:data validation:validation];
        NSApp.delegate = delegate;
        [NSApp run];
    }
    return 0;
}
