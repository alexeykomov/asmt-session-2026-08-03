//
//  FWASourceDetailViewController.h
//  FunWithActivity
//
//  Sources → row detail. Pushed when a source row in FWASourcesViewController
//  is tapped. Uses the SAME UITableViewStyleInsetGrouped style as
//  FWAProfileViewController — an explicit design requirement, so this reads
//  as the same app rather than a bolted-on screen.
//
//  Two sections:
//   CONFIGURATION — name, type, base URL. Phase 1 (see
//     FWASourcesViewController's header doc: no separate registry RPC yet)
//     only ever reaches this screen for one of the two built-in providers,
//     so it is always rendered read-only: plain, non-editable rows plus a
//     footer explaining that built-in sources are configured at deployment
//     time and cannot be edited in the app. `type` ("REST") is a genuine,
//     known property of the built-in adapters that is NOT on the wire and
//     stays static text. `baseURL` IS on the wire as of
//     ProviderStatus.baseURL (field 7, base_url in recommendations.proto —
//     see Recommendations.pbobjc.h) — the provider's real configured
//     endpoint, populated server-side from PROVIDER1_URL/PROVIDER2_URL. A
//     server predating this field, or a provider with nothing configured,
//     yields an empty string; that renders as the honest "Not exposed to
//     clients" placeholder (see FWASourceConfig), never a fabricated
//     value. It is not parsed out of `error`, which only happens to carry
//     a URL on some failures and would leave this row blank for a healthy
//     provider.
//   STATUS — status word, latency, and `error` verbatim — the FULL text,
//     including any vendor URL it embeds. This is the one place in the app
//     an operator should see it uncut; FWASourcesViewController truncates
//     this to a short reason for the list. Status/latency are runtime state
//     from the most recent fetch, exactly as FWAAppState documents them —
//     nothing here is persisted.
//
//  Read-only end to end right now. `FWASourceConfig.isEditable` exists so a
//  future user-added source (once FWAAddSourceViewController's "not
//  supported yet" stub becomes real) can render an editable form here
//  instead — no editing UI is built in this pass.
//

#import <UIKit/UIKit.h>

@class ProviderStatus;

NS_ASSUME_NONNULL_BEGIN

@interface FWASourceDetailViewController : UIViewController

- (instancetype)initWithProviderName:(NSString *)providerName
                                status:(nullable ProviderStatus *)status NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                          bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
