// An isolated application exercising Sparkle's real install/relaunch path.
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <Sparkle/Sparkle.h>

static void finish(BOOL success, NSString *message) {
  NSString *path = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"TestResultPath"];
  NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"success": @(success), @"message": message}
      options:NSJSONWritingPrettyPrinted error:nil];
  [data writeToFile:path atomically:YES];
  [NSApp terminate:nil];
}

@interface InstallDriver : NSObject <SPUUserDriver>
@end
@implementation InstallDriver
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply {
  reply([[[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO sendSystemProfile:NO] autorelease]);
}
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancel {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply { reply(SPUUserUpdateChoiceInstall); }
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error { finish(NO, error.description); }
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))ack { ack(); finish(NO, error.description); }
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))ack { ack(); finish(NO, error.description); }
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancel {}
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate {}
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply { reply(SPUUserUpdateChoiceInstall); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))ack { ack(); }
- (void)dismissUpdateInstallation {}
- (void)showUpdateInFocus {}
@end

@interface InstallApp : NSObject <NSApplicationDelegate>
@property(retain) SPUUpdater *updater;
@end
@implementation InstallApp
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSBundle *bundle = [NSBundle mainBundle];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  // Match the real app: initialize a webview before using its persistent store.
  static WKWebView *webview = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
  [webview loadHTMLString:@"<p>Isolated updater test</p>" baseURL:nil];
  WKWebsiteDataStore *store = webview.configuration.websiteDataStore;
  if ([[bundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqualToString:@"2.0.0"]) {
    [store.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
      BOOL cookieFound = NO;
      for (NSHTTPCookie *cookie in cookies) {
        if ([cookie.name isEqualToString:@"update-test-session"] && [cookie.value isEqualToString:@"retained"])
          cookieFound = YES;
      }
      BOOL preferenceFound = [[defaults stringForKey:@"update-test-preference"] isEqualToString:@"retained"];
      BOOL success = cookieFound && preferenceFound;
      NSString *detail = [NSString stringWithFormat:@"Preference retained: %@; cookie retained: %@; cookies: %lu",
          preferenceFound ? @"yes" : @"no", cookieFound ? @"yes" : @"no", (unsigned long)cookies.count];
      [defaults removePersistentDomainForName:bundle.bundleIdentifier];
      [store removeDataOfTypes:[WKWebsiteDataStore allWebsiteDataTypes] modifiedSince:[NSDate distantPast] completionHandler:^{
        finish(success, success ? @"Installed and relaunched; preferences and WebKit cookie retained." : detail);
      }];
    }];
    return;
  }
  [defaults setObject:@"retained" forKey:@"update-test-preference"];
  [defaults synchronize];
  NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:@{
    NSHTTPCookieName: @"update-test-session", NSHTTPCookieValue: @"retained",
    NSHTTPCookieDomain: @"update-test.invalid", NSHTTPCookiePath: @"/",
    NSHTTPCookieExpires: [NSDate dateWithTimeIntervalSinceNow:3600]
  }];
  [store.httpCookieStore setCookie:cookie completionHandler:^{
    self.updater = [[[SPUUpdater alloc] initWithHostBundle:bundle applicationBundle:bundle
        userDriver:[[[InstallDriver alloc] init] autorelease] delegate:nil] autorelease];
    NSError *error = nil;
    if (![self.updater startUpdater:&error]) { finish(NO, error.description); return; }
    // Give WebKit's network process time to commit the newly seeded cookie.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      [self.updater checkForUpdates];
    });
  }];
}
@end

int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    InstallApp *delegate = [[InstallApp alloc] init];
    NSApp.delegate = delegate;
    [NSApp run];
  }
}
