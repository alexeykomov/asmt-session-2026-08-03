//
//  FWAResultsViewController.h
//  FunWithActivity
//
//  Results screen: a banner area for provider statuses (info/degraded,
//  never rendered for ok==true) above a table of recommendations
//  (title, optional details, source, score).
//

#import <UIKit/UIKit.h>

@class GetRecommendationsResponse;

NS_ASSUME_NONNULL_BEGIN

@interface FWAResultsViewController : UIViewController

- (instancetype)initWithResponse:(GetRecommendationsResponse *)response NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                          bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
