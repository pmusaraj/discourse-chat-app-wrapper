// WebKit exposes video Live Text only through its internal feature API.
// Keep normal text interaction enabled so chat selection/copying still works.
@interface WKPreferences (ChatLiveText)
+ (NSArray *)_features;
- (void)_setEnabled:(BOOL)enabled forFeature:(id)feature;
@end

@protocol ChatWebKitFeature
- (NSString *)key;
@end

static void chat_configure_webview(WKWebView *webview) {
  WKPreferences *preferences = webview.configuration.preferences;
  if (![WKPreferences respondsToSelector:@selector(_features)] ||
      ![preferences respondsToSelector:@selector(_setEnabled:forFeature:)])
    return;

  for (id<ChatWebKitFeature> feature in [WKPreferences _features]) {
    if ([(id)feature respondsToSelector:@selector(key)] &&
        [feature.key isEqualToString:@"TextRecognitionInVideosEnabled"]) {
      [preferences _setEnabled:NO forFeature:feature];
      break;
    }
  }
}
