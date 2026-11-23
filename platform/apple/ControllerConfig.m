#import <Foundation/Foundation.h>
#include "ControllerConfig.h"
extern void void_files_set_overlay(const char *);
extern void void_log(const char *, ...);

// Keep all lines and unrelated settings. Fill only the missing PC backend;
// a nonempty custom class and the player's profile vibration preference win.
static NSString *controllerConfig(NSString *source)
{
    NSString *newline=[source containsString:@"\r\n"] ? @"\r\n" : @"\n";
    NSMutableArray<NSString *> *lines=[[source componentsSeparatedByString:newline] mutableCopy];
    NSMutableArray<NSString *> *out=[NSMutableArray array];
    BOOL controller=NO,vibration=NO,found=NO,hasSection=NO;
    NSCharacterSet *space=NSCharacterSet.whitespaceCharacterSet;
    NSString *backend=@"WinDrv.XnaForceFeedbackManager";
    BOOL engineSection=NO;
    for(NSString *__strong line in lines) {
        NSString *trim=[line stringByTrimmingCharactersInSet:space];
        if([trim hasPrefix:@"["])engineSection=[trim caseInsensitiveCompare:@"[Engine.PlayerController]"]==NSOrderedSame;
        NSRange equal=[trim rangeOfString:@"="];
        if(engineSection&&equal.location!=NSNotFound &&
           [[[trim substringToIndex:equal.location] stringByTrimmingCharactersInSet:space]
            caseInsensitiveCompare:@"ForceFeedbackManagerClassName"]==NSOrderedSame) {
            NSString *value=[[trim substringFromIndex:equal.location+1] stringByTrimmingCharactersInSet:space];
            if(value.length && ![value isEqual:@"\"\""])backend=value;
        }
    }
    NSString *backendLine=[@"ForceFeedbackManagerClassName=" stringByAppendingString:backend];
    for(NSString *__strong line in lines) {
        NSString *trim=[line stringByTrimmingCharactersInSet:space];
        if([trim hasPrefix:@"["] && [trim hasSuffix:@"]"]) {
            if(controller&&!found)[out addObject:backendLine];
            controller=[trim caseInsensitiveCompare:@"[UTGame.UTPlayerController]"]==NSOrderedSame ||
                       [trim caseInsensitiveCompare:@"[Engine.PlayerController]"]==NSOrderedSame;
            vibration=[trim caseInsensitiveCompare:@"[ControllerVibration UTUIDataProvider_MenuOption]"]==NSOrderedSame;
            found=NO;
            if([trim caseInsensitiveCompare:@"[UTGame.UTPlayerController]"]==NSOrderedSame)hasSection=YES;
        }
        NSRange equal=[trim rangeOfString:@"="];
        if(equal.location!=NSNotFound) {
            NSString *key=[[trim substringToIndex:equal.location] stringByTrimmingCharactersInSet:space];
            NSString *value=[[trim substringFromIndex:equal.location+1] stringByTrimmingCharactersInSet:space];
            if(controller&&[key caseInsensitiveCompare:@"ForceFeedbackManagerClassName"]==NSOrderedSame) {
                found=YES;
                if(!value.length || [value isEqual:@"\"\""])
                    line=backendLine;
            }
            if(vibration&&[key caseInsensitiveCompare:@"bRemoveOnPC"]==NSOrderedSame)line=@"bRemoveOnPC=0";
        }
        [out addObject:line];
    }
    if(controller&&!found)[out addObject:backendLine];
    if(!hasSection)[out addObjectsFromArray:@[@"",@"[UTGame.UTPlayerController]",backendLine]];
    return [out componentsJoinedByString:newline];
}

static BOOL writeConfig(NSURL *source,NSURL *destination,BOOL backup,NSError **error)
{
    NSStringEncoding encoding;
    NSString *original=[NSString stringWithContentsOfURL:source usedEncoding:&encoding error:error];
    if(!original)return NO;
    NSString *updated=controllerConfig(original);
    NSFileManager *files=NSFileManager.defaultManager;
    if([source isEqual:destination] && [original isEqual:updated])return YES;
    // An unchanged default overlay must retain its mtime: UE3 uses config
    // timestamps to decide when to regenerate the player's configuration.
    if(![source isEqual:destination] &&
       [[NSString stringWithContentsOfURL:destination encoding:encoding error:NULL] isEqual:updated])return YES;
    if(backup) {
        NSURL *saved=[source URLByAppendingPathExtension:@"before-controller-haptics"];
        if(![files fileExistsAtPath:saved.path] && ![files copyItemAtURL:source toURL:saved error:error])return NO;
    }
    if(![files createDirectoryAtURL:destination.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error])return NO;
    return [updated writeToURL:destination atomically:YES encoding:encoding error:error];
}
int ut3_apple_controller_config(const char *game,const char *data)
{
    @autoreleasepool {
        NSURL *root=[NSURL fileURLWithFileSystemRepresentation:data isDirectory:YES relativeToURL:nil];
        NSURL *installation=[NSURL fileURLWithFileSystemRepresentation:game isDirectory:YES relativeToURL:nil];
        NSURL *overlay=[root URLByAppendingPathComponent:@"AppleConfig" isDirectory:YES];
        NSURL *source=[installation URLByAppendingPathComponent:@"UTGame/Config/DefaultGame.ini"];
        NSURL *target=[overlay URLByAppendingPathComponent:@"UTGame/Config/DefaultGame.ini"];
        NSError *error=nil;
        if(!writeConfig(source,target,NO,&error)) {
            void_log("[rumble-config] could not prepare default configuration: %s",error.localizedDescription.UTF8String);
            return 0;
        }
        NSURL *user=[root URLByAppendingPathComponent:@"Documents/My Games/Unreal Tournament 3/UTGame/Config/UTGame.ini"];
        if([NSFileManager.defaultManager fileExistsAtPath:user.path] && !writeConfig(user,user,YES,&error)) {
            void_log("[rumble-config] could not update player configuration: %s",error.localizedDescription.UTF8String);
            return 0;
        }
        void_files_set_overlay(overlay.fileSystemRepresentation);
        void_log("[rumble-config] native Xna backend defaults prepared; original game inputs unchanged");
        return 1;
    }
}
