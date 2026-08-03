//
//  FWARecommendationDetailViewController.h
//  FunWithActivity
//
//  Recommendations → row detail. Pushed when a recommendation row in
//  FWARecommendationsViewController is tapped. Uses the SAME
//  UITableViewStyleInsetGrouped style as FWAProfileViewController and
//  FWASourceDetailViewController, so this reads as the same app rather
//  than a bolted-on screen.
//
//  Three sections:
//   RECOMMENDATION — the details text in full. The list cell truncates it
//     to two lines; this is where it is read whole. Service 1 has no
//     details field at all, so an empty string here is the vendor's data
//     rather than a rendering failure, and it says so instead of showing a
//     bare dash a presenter would have to explain.
//   PROVENANCE — one row per contributing provider, each with the status
//     and latency that provider reported on the fetch that produced this
//     recommendation. This is the point of the screen: the list row can
//     only show the joined `source` string ("service1, service2"), which
//     states that a merge happened but not what each side contributed.
//     Two providers independently returning the same tip is the merge this
//     product exists to perform, so the footer says so outright.
//   RANKING — the final score and the rank within the response.
//
//  Deliberately shows the final score only. Raw and normalised scores stay
//  server-side — recommendations.proto reserves those field numbers
//  precisely so the ranker's internals never become wire contract — and the
//  section footer states that rather than leaving a reader wondering why
//  the arithmetic is missing.
//
//  Nothing here is fetched. The screen is constructed with the
//  recommendation and the statuses from the response the user is already
//  looking at; re-fetching would call the vendors again and could return a
//  different set, leaving the user reading an explanation of a
//  recommendation that is no longer the one they tapped. This mirrors
//  FWASourceDetailViewController, which takes its ProviderStatus the same
//  way.
//
//  No wire change was needed for any of it: title, details, source and
//  score come from Recommendation, and per-provider status and latency come
//  from the ProviderStatus values already in the same response.
//

#import <UIKit/UIKit.h>

@class Recommendation;
@class ProviderStatus;

NS_ASSUME_NONNULL_BEGIN

@interface FWARecommendationDetailViewController : UIViewController

/// @param recommendation The tapped row.
/// @param statuses Every provider status from the same response, used to
///     resolve each contributing provider named in `recommendation.source`.
/// @param rank 1-based position in the response's ranked order.
/// @param total Number of recommendations in the response.
- (instancetype)initWithRecommendation:(Recommendation *)recommendation
                              statuses:(NSArray<ProviderStatus *> *)statuses
                                  rank:(NSInteger)rank
                                 total:(NSInteger)total NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
