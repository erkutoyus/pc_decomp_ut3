#import <Foundation/Foundation.h>

// documents is the platform's real Documents URL, never a display label.
// Named macOS root / legacy build-9 iOS child. Current iOS uses Documents itself.
NSURL *UT3DataRoot(NSURL *documents);
// iOS uses Documents directly (Files already labels the app); macOS uses the
// named Documents child. Creates UserData and, on iOS, Game. Moves directories only
// into absent/empty destinations; conflicting populated trees are never merged.
BOOL UT3PrepareDataRoot(NSURL *documents, NSURL *legacyData, BOOL ios,
                        NSError **error);
// Ordinary bookmarks track a selected folder without enabling App Sandbox.
BOOL UT3RememberGameFolder(NSURL *root, NSURL *game, NSError **error);
NSURL *UT3RememberedGameFolder(NSURL *root);
