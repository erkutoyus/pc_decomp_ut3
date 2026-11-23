#import <Foundation/Foundation.h>
#include <assert.h>
#import "../platform/apple/ControllerConfig.m"
static NSString *observedOverlay;
void void_files_set_overlay(const char *path) { observedOverlay=[NSString stringWithUTF8String:path]; }
void void_log(const char *format,...) { (void)format; }
int main(void)
{
    @autoreleasepool {
        NSFileManager *files=NSFileManager.defaultManager;
        NSURL *root=[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSURL *game=[root URLByAppendingPathComponent:@"Game"];
        NSURL *data=[root URLByAppendingPathComponent:@"UserData"];
        NSURL *source=[game URLByAppendingPathComponent:@"UTGame/Config/DefaultGame.ini"];
        NSURL *user=[data URLByAppendingPathComponent:@"Documents/My Games/Unreal Tournament 3/UTGame/Config/UTGame.ini"];
        assert([files createDirectoryAtURL:source.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]);
        NSString *defaults=@"[Other]\r\nbRemoveOnPC=1\r\nVolume=0.42\r\n[UTGame.UTPlayerController]\r\nOtherSetting=Keep\r\n[ControllerVibration UTUIDataProvider_MenuOption]\r\nbRemoveOnPC=1\r\n";
        assert([defaults writeToURL:source atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
        NSData *original=[NSData dataWithContentsOfURL:source];
        assert(ut3_apple_controller_config(game.fileSystemRepresentation,data.fileSystemRepresentation));
        assert([original isEqual:[NSData dataWithContentsOfURL:source]]);
        assert(![files fileExistsAtPath:user.path]); // Let UE3 generate its full config.
        NSString *derived=[NSString stringWithContentsOfFile:[observedOverlay stringByAppendingPathComponent:@"UTGame/Config/DefaultGame.ini"] encoding:NSUTF8StringEncoding error:NULL];
        assert([derived containsString:@"ForceFeedbackManagerClassName=WinDrv.XnaForceFeedbackManager"]);
        assert([derived containsString:@"[Other]\r\nbRemoveOnPC=1"]);
        assert([derived containsString:@"[ControllerVibration UTUIDataProvider_MenuOption]\r\nbRemoveOnPC=0"]);
        NSString *overlayPath=[observedOverlay stringByAppendingPathComponent:@"UTGame/Config/DefaultGame.ini"];
        NSDate *sentinel=[NSDate dateWithTimeIntervalSince1970:1000000];
        assert([files setAttributes:@{NSFileModificationDate:sentinel} ofItemAtPath:overlayPath error:NULL]);
        assert([files createDirectoryAtURL:user.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]);
        NSString *settings=@"[UTGame.UTPlayerController]\nForceFeedbackManagerClassName=\nKeepSetting=7\n";
        assert([settings writeToURL:user atomically:YES encoding:NSUTF16StringEncoding error:NULL]);
        NSData *before=[NSData dataWithContentsOfURL:user];
        assert(ut3_apple_controller_config(game.fileSystemRepresentation,data.fileSystemRepresentation));
        assert([[[files attributesOfItemAtPath:overlayPath error:NULL] objectForKey:NSFileModificationDate] isEqual:sentinel]);
        NSURL *backup=[user URLByAppendingPathExtension:@"before-controller-haptics"];
        assert([before isEqual:[NSData dataWithContentsOfURL:backup]]);
        NSString *updated=[NSString stringWithContentsOfURL:user encoding:NSUTF16StringEncoding error:NULL];
        assert([updated containsString:@"ForceFeedbackManagerClassName=WinDrv.XnaForceFeedbackManager"]);
        assert([updated containsString:@"KeepSetting=7"]);
        NSData *after=[NSData dataWithContentsOfURL:user];
        assert(ut3_apple_controller_config(game.fileSystemRepresentation,data.fileSystemRepresentation));
        assert([after isEqual:[NSData dataWithContentsOfURL:user]]);
        assert([before isEqual:[NSData dataWithContentsOfURL:backup]]);
        NSString *custom=@"[UTGame.UTPlayerController]\nForceFeedbackManagerClassName=Custom.MyManager\n";
        assert([controllerConfig(custom) isEqual:custom]);
        NSString *inherited=@"[Engine.PlayerController]\nForceFeedbackManagerClassName=Custom.Inherited\n[UTGame.UTPlayerController]\n";
        NSString *patched=controllerConfig(inherited);
        assert(![patched containsString:@"WinDrv.XnaForceFeedbackManager"]);
        assert([patched containsString:@"[UTGame.UTPlayerController]\n\nForceFeedbackManagerClassName=Custom.Inherited"]);
        assert([files removeItemAtURL:root error:NULL]);
        puts("PASS original config unchanged, first-launch overlay, scoped menu visibility, UTF16 empty-backend repair, settings preservation, backup and idempotent relaunch");
    }
}
