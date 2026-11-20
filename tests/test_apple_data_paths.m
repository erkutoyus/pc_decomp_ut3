#import "../platform/apple/DataPaths.h"
#include <assert.h>
static NSURL *child(NSURL *base,NSString *name) { return [base URLByAppendingPathComponent:name]; }
static void mkdirp(NSURL *url) { assert([NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil]); }
static void write_text(NSURL *url,NSString *text) { assert([text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil]); }
static NSString *read_text(NSURL *url) { return [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil]; }
int main(void) { @autoreleasepool {
 NSURL *temp=child([NSURL fileURLWithPath:NSTemporaryDirectory()],NSUUID.UUID.UUIDString);mkdirp(temp);
 NSURL *docs=child(temp,@"Documents");mkdirp(docs);NSError *error=nil;
 assert(UT3PrepareDataRoot(docs,nil,YES,&error));NSURL *root=docs;
 assert([NSFileManager.defaultManager fileExistsAtPath:child(root,@"Game").path]);
 assert([NSFileManager.defaultManager fileExistsAtPath:child(root,@"UserData").path]);
 assert(![NSFileManager.defaultManager fileExistsAtPath:UT3DataRoot(docs).path]);
 assert([read_text(child(root,@"READ ME.txt")) containsString:@"Do not create a folder named Documents"]);
 // Version 9 nested content moves to the already-created empty flat folders.
 NSURL *nested=UT3DataRoot(docs);mkdirp(child(nested,@"Game/Binaries"));
 write_text(child(nested,@"Game/Binaries/UT3.exe"),@"fixture");
 mkdirp(child(nested,@"UserData/SaveData"));write_text(child(nested,@"UserData/SaveData/profile"),@"keep");
 write_text(child(nested,@"cdkey.txt"),@"synthetic fixture only");
 write_text(child(nested,@"capture.ppm"),@"keep diagnostic");
 assert(UT3PrepareDataRoot(docs,child(docs,@"UserData"),YES,&error));
 assert([read_text(child(root,@"Game/Binaries/UT3.exe")) isEqual:@"fixture"]);
 assert([read_text(child(root,@"UserData/SaveData/profile")) isEqual:@"keep"]);
 assert([read_text(child(root,@"cdkey.txt")) isEqual:@"synthetic fixture only"]);
 assert([read_text(child(root,@"capture.ppm")) isEqual:@"keep diagnostic"]);
 assert(![NSFileManager.defaultManager fileExistsAtPath:nested.path]);
 // Conflicting trees/keys remain intact in a backup; no duplicate named folder remains.
 mkdirp(child(nested,@"UserData"));write_text(child(nested,@"UserData/other"),@"old separate");
 write_text(child(nested,@"cdkey.txt"),@"different synthetic fixture");
 assert(UT3PrepareDataRoot(docs,child(docs,@"UserData"),YES,&error));
 assert([read_text(child(root,@"Previous Layout Backup/UserData/other")) isEqual:@"old separate"]);
 assert([read_text(child(root,@"Previous Layout Backup/cdkey.txt")) isEqual:@"different synthetic fixture"]);
 assert([read_text(child(root,@"UserData/SaveData/profile")) isEqual:@"keep"]);
 assert([read_text(child(root,@"cdkey.txt")) isEqual:@"synthetic fixture only"]);
 assert(![NSFileManager.defaultManager fileExistsAtPath:nested.path]);
 assert(UT3PrepareDataRoot(docs,child(docs,@"UserData"),YES,&error));
 // macOS migrates Application Support into Documents/.../UserData and remembers a folder atomically.
 NSURL *macDocs=child(temp,@"MacDocuments"),*legacy=child(temp,@"Application Support/Unreal Tournament 3");
 mkdirp(legacy);write_text(child(legacy,@"settings.ini"),@"owner settings");write_text(child(legacy,@"cdkey.txt"),@"synthetic legacy key");
 assert(UT3PrepareDataRoot(macDocs,legacy,NO,&error));NSURL *macRoot=UT3DataRoot(macDocs);
 assert([read_text(child(macRoot,@"UserData/settings.ini")) isEqual:@"owner settings"]);
 assert([read_text(child(macRoot,@"cdkey.txt")) isEqual:@"synthetic legacy key"]);
 assert(![NSFileManager.defaultManager fileExistsAtPath:child(macRoot,@"Game").path]);
 assert(UT3RememberGameFolder(macRoot,child(root,@"Game"),&error));
 assert([UT3RememberedGameFolder(macRoot).URLByResolvingSymlinksInPath.path isEqual:child(root,@"Game").URLByResolvingSymlinksInPath.path]);
 assert([NSFileManager.defaultManager removeItemAtURL:child(root,@"Game/Binaries/UT3.exe") error:nil]);
 assert(UT3RememberedGameFolder(macRoot)==nil);
 // A file where a required directory belongs reports failure rather than dropping state.
 NSURL *badDocs=child(temp,@"BadDocuments");mkdirp(badDocs);write_text(child(badDocs,@"Unreal Tournament 3"),@"do not delete");
 assert(!UT3PrepareDataRoot(badDocs,nil,NO,&error));assert([read_text(child(badDocs,@"Unreal Tournament 3")) isEqual:@"do not delete"]);
 assert([NSFileManager.defaultManager removeItemAtURL:temp error:nil]);
 puts("PASS Apple data paths: first launch, legacy migrations, conflict preservation, key placement, bookmark reload and missing-folder recovery");
} return 0; }
