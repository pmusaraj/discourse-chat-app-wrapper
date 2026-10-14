// Loaded only inside the packaged app, so `tinyjs dev` never updates itself.
#import <Sparkle/Sparkle.h>

static SPUStandardUpdaterController *chat_updater = nil;

@interface ChatUpdaterMenu : NSObject <NSMenuItemValidation>
- (void)toggleAutomaticUpdates:(id)sender;
@end
@implementation ChatUpdaterMenu
- (void)toggleAutomaticUpdates:(id)sender {
  chat_updater.updater.automaticallyChecksForUpdates =
      !chat_updater.updater.automaticallyChecksForUpdates;
}
- (BOOL)validateMenuItem:(NSMenuItem *)item {
  item.state = chat_updater.updater.automaticallyChecksForUpdates
      ? NSControlStateValueOn : NSControlStateValueOff;
  return chat_updater != nil;
}
@end

static void chat_start_updater() {
  if (!g_bundle_mode) return;
  NSBundle *app = [NSBundle mainBundle];
  if (![app objectForInfoDictionaryKey:@"SUPublicEDKey"] ||
      ![app objectForInfoDictionaryKey:@"SUFeedURL"]) return;
  NSString *path = [[app privateFrameworksPath] stringByAppendingPathComponent:@"Sparkle.framework"];
  NSError *error = nil;
  if (![[NSBundle bundleWithPath:path] loadAndReturnError:&error]) {
    NSLog(@"Could not load the update framework: %@", error);
    return;
  }
  // Resolve dynamically to keep the standalone dev launcher independent of
  // the framework. The packaged app contains its own signed copy.
  Class controller = NSClassFromString(@"SPUStandardUpdaterController");
  chat_updater = [[controller alloc] initWithStartingUpdater:YES
      updaterDelegate:nil userDriverDelegate:nil];
}

static void chat_add_update_menu(NSMenu *menu) {
  if (!chat_updater) return;
  NSMenuItem *check = [menu addItemWithTitle:@"Check for Updates…"
      action:@selector(checkForUpdates:) keyEquivalent:@""];
  check.target = chat_updater;
  static ChatUpdaterMenu *target = [[ChatUpdaterMenu alloc] init];
  NSMenuItem *automatic = [menu addItemWithTitle:@"Automatically Check for Updates"
      action:@selector(toggleAutomaticUpdates:) keyEquivalent:@""];
  automatic.target = target;
  [menu addItem:[NSMenuItem separatorItem]];
}
