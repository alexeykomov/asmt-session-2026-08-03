//
//  FWAChartsViewController.h
//  FunWithActivity
//
//  The Charts tab: a steps bar chart, a sleep-stage pie, and a grouped bar
//  of active minutes by intensity, drawn with CoreGraphics via FWAChartView.
//
//  Uses the same visit policy the Recommendations tab does — fetch on first
//  appearance, refetch on return only when the profile changed, always fetch
//  on pull-to-refresh — and repaints from the last response when the fetch is
//  skipped. That repaint is not incidental: omitting it on Recommendations
//  shipped as a real defect, where declining to fetch and losing the data
//  looked identical to the user.
//
//  Deliberately does NOT clear AppState's dirty flag on success. That flag
//  means "the profile changed since the last recommendations fetch", and the
//  Recommendations tab owns clearing it; consuming it here would let a visit
//  to Charts silently skip the refetch Recommendations was about to perform.
//
//  The data is generated server-side and labelled as sample data on screen.
//  Nothing here is measured, and the footer says so — the rest of this
//  project refuses to imply otherwise.
//

#import <UIKit/UIKit.h>

@class FWAAppState;
@class FWAGRPCClient;

NS_ASSUME_NONNULL_BEGIN

@interface FWAChartsViewController : UIViewController

- (instancetype)initWithGRPCClient:(FWAGRPCClient *)grpcClient
                           appState:(FWAAppState *)appState NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                          bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
