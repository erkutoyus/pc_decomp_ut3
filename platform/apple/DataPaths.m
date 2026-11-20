#import "DataPaths.h"

static NSString *const GameBookmark = @"GameFolder.bookmark";
NSURL *UT3DataRoot(NSURL *documents)
{
    return [documents URLByAppendingPathComponent:@"Unreal Tournament 3" isDirectory:YES];
}
static BOOL directory(NSURL *url, NSError **error)
{
    return [NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES
                                                   attributes:nil error:error];
}
static BOOL adopt(NSURL *source, NSURL *target, NSError **error)
{
    NSFileManager *files=NSFileManager.defaultManager;
    if(!source || [source.URLByStandardizingPath.path isEqual:target.URLByStandardizingPath.path] ||
       ![files fileExistsAtPath:source.path])return YES;
    BOOL sourceDirectory=NO;
    [files fileExistsAtPath:source.path isDirectory:&sourceDirectory];
    if(!sourceDirectory) {
        if(error)*error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError
            userInfo:@{NSLocalizedDescriptionKey:@"A legacy game/user-data path is a file, not a folder. It was left unchanged."}];
        return NO;
    }
    BOOL isDirectory=NO;
    if([files fileExistsAtPath:target.path isDirectory:&isDirectory]) {
        if(!isDirectory)return YES; // The caller reports invalid directory layouts.
        NSArray *items=[files contentsOfDirectoryAtURL:target includingPropertiesForKeys:nil options:0 error:error];
        if(!items)return NO;
        if(items.count)return YES; // Never overwrite or silently merge owner data.
        if(![files removeItemAtURL:target error:error])return NO; // Known-empty destination only.
    }
    return [files moveItemAtURL:source toURL:target error:error];
}
static BOOL flattenIOS(NSURL *documents, NSError **error)
{
    NSFileManager *files=NSFileManager.defaultManager;
    NSURL *nested=UT3DataRoot(documents);
    if(![files fileExistsAtPath:nested.path])return YES;
    // Version 9 added an unnecessary inner folder. Move files within the same
    // container; never copy multi-GB game data or overwrite populated saves.
    for(NSString *name in @[@"Game",@"UserData"]) {
        if(!adopt([nested URLByAppendingPathComponent:name],
                  [documents URLByAppendingPathComponent:name],error))return NO;
    }
    NSArray<NSURL *> *remaining=[files contentsOfDirectoryAtURL:nested includingPropertiesForKeys:nil options:0 error:error];
    if(!remaining)return NO;
    for(NSURL *source in remaining) {
        NSURL *target=[documents URLByAppendingPathComponent:source.lastPathComponent];
        if(![files fileExistsAtPath:target.path] && ![files moveItemAtURL:source toURL:target error:error])return NO;
    }
    remaining=[files contentsOfDirectoryAtURL:nested includingPropertiesForKeys:nil options:0 error:error];
    if(!remaining)return NO;
    if(!remaining.count)return [files removeItemAtURL:nested error:error];
    // Both layouts had content. Keep the flat layout active and retain every
    // conflicting original in a clearly named backup, rather than duplicating
    // the app's own visible name or silently merging profiles.
    NSURL *backup=[documents URLByAppendingPathComponent:@"Previous Layout Backup" isDirectory:YES];
    if([files fileExistsAtPath:backup.path])backup=[documents URLByAppendingPathComponent:
        [@"Previous Layout Backup " stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    return [files moveItemAtURL:nested toURL:backup error:error];
}
BOOL UT3PrepareDataRoot(NSURL *documents, NSURL *legacyData, BOOL ios, NSError **error)
{
    NSURL *root=ios ? documents : UT3DataRoot(documents);
    if(!directory(root,error))return NO;
    if(ios) {
        if(!flattenIOS(documents,error))return NO;
    } else if(!adopt(legacyData,[root URLByAppendingPathComponent:@"UserData"],error))return NO;
    if(!directory([root URLByAppendingPathComponent:@"UserData"],error))return NO;
    if(ios && !directory([root URLByAppendingPathComponent:@"Game"],error))return NO;
    // Retain the old key as a compatibility fallback. Copying is bounded by
    // the original reader; never log key bytes or overwrite a chosen new key.
    NSURL *key=[root URLByAppendingPathComponent:@"cdkey.txt"];
    if(![NSFileManager.defaultManager fileExistsAtPath:key.path]) {
        for(NSURL *parent in @[documents,legacyData ?: documents,[root URLByAppendingPathComponent:@"UserData"]]) {
            NSURL *old=[parent URLByAppendingPathComponent:@"cdkey.txt"];
            if([old.path isEqual:key.path] || ![NSFileManager.defaultManager fileExistsAtPath:old.path])continue;
            NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:old.path error:error];
            if(!attributes)return NO;
            if(![attributes[NSFileType] isEqual:NSFileTypeRegular] ||
               [attributes[NSFileSize] unsignedLongLongValue]<1 || [attributes[NSFileSize] unsignedLongLongValue]>256) {
                if(error)*error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError
                    userInfo:@{NSLocalizedDescriptionKey:@"Legacy cdkey.txt must be a regular plain-text file of at most 256 bytes. It was left unchanged."}];
                return NO;
            }
            if(![NSFileManager.defaultManager copyItemAtURL:old toURL:key error:error])return NO;
            [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:key.path error:nil];
            break;
        }
    }
    NSURL *readme=[root URLByAppendingPathComponent:@"READ ME.txt"];
    if(![NSFileManager.defaultManager fileExistsAtPath:readme.path]) {
        NSString *text=ios
          ? @"Unreal Tournament 3\n\nPut your owned game files in Game/Binaries, Game/Engine and Game/UTGame.\nThe executable must be Game/Binaries/UT3.exe.\nPut your private one-line cdkey.txt next to Game.\nUserData contains saves, profiles, configuration and logs.\nProfiles: UserData/Documents/My Games/Unreal Tournament 3/UTGame/SaveData\nINI files: UserData/Documents/My Games/Unreal Tournament 3/UTGame/Config\nRelaunch the app after copying. Do not create a folder named Documents or another Unreal Tournament 3 folder. Files already shows this app as Unreal Tournament 3.\n"
          : @"Unreal Tournament 3\n\nPut your private one-line cdkey.txt here.\nUserData contains saves, profiles, configuration and logs.\nProfiles: UserData/Documents/My Games/Unreal Tournament 3/UTGame/SaveData\nINI files: UserData/Documents/My Games/Unreal Tournament 3/UTGame/Config\nChoose your original game installation in the app; its location is remembered.\nThe game installation is not copied into UserData.\n";
        if(![text writeToURL:readme atomically:YES encoding:NSUTF8StringEncoding error:error])return NO;
    }
    return YES;
}
BOOL UT3RememberGameFolder(NSURL *root, NSURL *game, NSError **error)
{
    NSData *bookmark=[game bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:error];
    if(!bookmark)return NO;
    NSURL *path=[root URLByAppendingPathComponent:GameBookmark];
    if(![bookmark writeToURL:path options:NSDataWritingAtomic error:error])return NO;
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path.path error:nil];
    return YES;
}
NSURL *UT3RememberedGameFolder(NSURL *root)
{
    NSData *bookmark=[NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:GameBookmark]];
    if(!bookmark)return nil;
    BOOL stale=NO;
    NSURL *game=[NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithoutUI
                                 relativeToURL:nil bookmarkDataIsStale:&stale error:nil];
    if(!game || ![NSFileManager.defaultManager isReadableFileAtPath:[game URLByAppendingPathComponent:@"Binaries/UT3.exe"].path])return nil;
    if(stale)UT3RememberGameFolder(root,game,nil);
    return game;
}
