//
//  FWASourcesViewController.h
//  FunWithActivity
//
//  Tab 2 — Sources. A grouped list of the configured providers, from the
//  most recent GetRecommendations response: name, status (ok / skipped /
//  degraded), and last observed latency (rendered "—" when zero — the stub
//  fallback returns in microseconds and a column of "0 ms" reads as
//  broken). A "+" bar button pushes a stub add-source form.
//
//  Phase 1 only: this screen reads the provider list from the most recent
//  response via FWAAppState; there is no separate registry RPC yet, and
//  nothing here is persisted. See FWAAddSourceViewController.
//

#import <UIKit/UIKit.h>

@class FWAAppState;

NS_ASSUME_NONNULL_BEGIN

@interface FWASourcesViewController : UIViewController

- (instancetype)initWithAppState:(FWAAppState *)appState NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                          bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
