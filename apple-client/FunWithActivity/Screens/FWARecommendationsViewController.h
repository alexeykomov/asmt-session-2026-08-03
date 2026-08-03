//
//  FWARecommendationsViewController.h
//  FunWithActivity
//
//  Tab 1 — Recommendations. A banner area for provider statuses (info for
//  a declined-input skip, degraded for a genuine failure — never rendered
//  for ok==true) above a table of recommendations (title, optional
//  details, source, score). Populated by a background fetch rather than a
//  form submit: fetches once on first appearance, and again on every later
//  appearance only when FWAAppState.isDirty — see -viewWillAppear:.
//

#import <UIKit/UIKit.h>

@class FWAGRPCClient;
@class FWAAppState;

NS_ASSUME_NONNULL_BEGIN

@interface FWARecommendationsViewController : UIViewController

- (instancetype)initWithGRPCClient:(FWAGRPCClient *)grpcClient
                            appState:(FWAAppState *)appState NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                          bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
