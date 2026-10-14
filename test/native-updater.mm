#import <AppKit/AppKit.h>
#include <cassert>
static bool g_bundle_mode = false;
#include "../native/chat-updater.inc"

int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp finishLaunching];
    chat_start_updater();
    assert(chat_updater == nil); // A standalone/dev launcher must never update.
    g_bundle_mode = true;
    chat_start_updater();
    assert(chat_updater != nil);
    assert([chat_updater.updater.feedURL.absoluteString isEqualToString:
        @"https://pmusaraj.github.io/discourse-chat-wrapper/appcast.xml"]);
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    assert(chat_updater.updater.canCheckForUpdates);
    NSMenu *menu = [[[NSMenu alloc] init] autorelease];
    chat_add_update_menu(menu);
    assert(menu.numberOfItems == 3);
    NSMenuItem *check = [menu itemAtIndex:0];
    assert(check.target == chat_updater);
    assert(check.action == @selector(checkForUpdates:));
    NSMenuItem *automatic = [menu itemAtIndex:1];
    BOOL previous = chat_updater.updater.automaticallyChecksForUpdates;
    [automatic.target toggleAutomaticUpdates:automatic];
    assert(chat_updater.updater.automaticallyChecksForUpdates != previous);
    assert([automatic.target validateMenuItem:automatic]);
    assert(automatic.state == (previous ? NSControlStateValueOff : NSControlStateValueOn));
    [automatic.target toggleAutomaticUpdates:automatic];
    assert(chat_updater.updater.automaticallyChecksForUpdates == previous);
    NSMenu *rebuilt = [[[NSMenu alloc] init] autorelease];
    chat_add_update_menu(rebuilt);
    assert([rebuilt itemAtIndex:0].target == chat_updater);
    puts("Sparkle loaded; native menu actions, preference toggle, and dev guard passed.");
  }
}
