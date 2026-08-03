//
//  FWAAddSourceViewController.h
//  FunWithActivity
//
//  Sources → "+". A stub add-source form: name, base URL, auth token, and
//  provider type (REST / gRPC), per the tabbed-UI design §5.3. Presented as
//  an inset-grouped UITableView — SOURCE (fields) / TYPE (checkmark rows) /
//  submit — matching Profile and the source detail screen, the only other
//  table-based screens in the app. Validates its fields, then explains —
//  rather than pretending to succeed — that a new source needs an adapter
//  (Go code implementing the Provider interface) before it can be called.
//  Persists nothing. In particular, the auth token is never stored anywhere
//  beyond the text field itself: a credential for a source that can never
//  be called is pure liability.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FWAAddSourceViewController : UIViewController

#if DEBUG
/// Headless-verification-only: fills valid, non-empty values into every
/// field and taps Submit — exactly what a person would do to reach the
/// "not supported yet" explanation. See FWAProfileViewController's
/// equivalent hook for why this project drives demo states this way
/// instead of via XCUITest. Not compiled into Release.
- (void)debug_fillValidFormAndSubmit;
#endif

@end

NS_ASSUME_NONNULL_END
