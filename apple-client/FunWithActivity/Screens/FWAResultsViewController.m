//
//  FWAResultsViewController.m
//  FunWithActivity
//

#import "FWAResultsViewController.h"
#import "FWAProviderStatusPresentation.h"
#import "Recommendations.pbobjc.h"
#if DEBUG
#import <os/log.h>
#endif

static NSString *const kBannerCellID = @"BannerCell";
static NSString *const kRecommendationCellID = @"RecommendationCell";

typedef NS_ENUM(NSInteger, FWAResultsSection) {
    FWAResultsSectionBanners = 0,
    FWAResultsSectionRecommendations,
    FWAResultsSectionCount,
};

// Custom cell so a recommendation can show title + (optional) details +
// source/score as three independently-sized labels stacked in a
// UIStackView. UITableViewCellStyleSubtitle only offers two text slots, not
// enough once `details` needs to render. The stack view is pinned to the
// content view's margins on all four edges, so with the table's row height
// set to UITableViewAutomaticDimension the row self-sizes to fit whatever
// is visible — and hiding detailsLabel (for rows with no details) removes
// it from the stack's layout entirely, leaving no gap.
@interface FWARecommendationCell : UITableViewCell
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *detailsLabel;
@property (nonatomic, strong, readonly) UILabel *metaLabel;
@end

@implementation FWARecommendationCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _titleLabel.numberOfLines = 0;

        // Subordinate to the title: smaller text style + secondary colour,
        // matching Android's body2-under-subtitle1 treatment for details.
        _detailsLabel = [UILabel new];
        _detailsLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _detailsLabel.textColor = [UIColor secondaryLabelColor];
        _detailsLabel.numberOfLines = 0;

        _metaLabel = [UILabel new];
        _metaLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _metaLabel.textColor = [UIColor secondaryLabelColor];
        _metaLabel.numberOfLines = 0;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.detailsLabel, self.metaLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 4;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];

        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:margins.topAnchor constant:8],
            [stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-8],
            [stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        ]];
    }
    return self;
}

@end

@interface FWAResultsViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong, readonly) NSArray<Recommendation *> *recommendations;
@property (nonatomic, strong, readonly) NSArray<FWAProviderStatusPresentation *> *banners;
@property (nonatomic, strong) UITableView *tableView;

@end

@implementation FWAResultsViewController

- (instancetype)initWithResponse:(GetRecommendationsResponse *)response {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _recommendations = [response.recommendationsArray copy] ?: @[];
        _banners = [FWAProviderStatusPresentation presentationsForStatuses:response.statusesArray ?: @[]];
#if DEBUG
        [self logRenderedContentForDemoVerification];
#endif
    }
    return self;
}

#if DEBUG
// DEBUG-only readout of exactly what this screen is about to render, in
// array order (== the order the table will show them in, since neither
// section re-sorts). Exists so headless verification (no XCUITest/UI
// automation in this project) can confirm titles/sources/scores/details
// via `os_log` instead of guessing from a screenshot — see
// docs/task-mobile-verification-report.md.
- (void)logRenderedContentForDemoVerification {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.funwithactivity.ios", "results");
    });

    os_log(log, "Results screen — banners=%lu recommendations=%lu",
           (unsigned long)self.banners.count, (unsigned long)self.recommendations.count);
    [self.banners enumerateObjectsUsingBlock:^(FWAProviderStatusPresentation *banner, NSUInteger idx, BOOL *stop) {
        os_log(log, "banner[%lu] provider=%{public}@ severity=%ld message=%{public}@",
               (unsigned long)idx, banner.providerName, (long)banner.severity, banner.message);
    }];
    [self.recommendations enumerateObjectsUsingBlock:^(Recommendation *rec, NSUInteger idx, BOOL *stop) {
        os_log(log, "recommendation[%lu] score=%.2f source=%{public}@ title=%{public}@ hasDetails=%d",
               (unsigned long)idx, rec.score, rec.source, rec.title, rec.details.length > 0);
    }];
}
#endif

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Recommendations";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    // Self-sizing rows: recommendation rows vary in height depending on
    // whether `details` is present (service2-stub rows) or not
    // (service1-stub rows) — a fixed rowHeight would either clip the
    // details text or leave every row artificially tall.
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 44;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return FWAResultsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == FWAResultsSectionBanners) {
        return self.banners.count;
    }
    return self.recommendations.count;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == FWAResultsSectionBanners) {
        return self.banners.count > 0 ? @"Notices" : nil;
    }
    return self.recommendations.count > 0 ? @"Recommendations" : @"No recommendations";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == FWAResultsSectionBanners) {
        return [self bannerCellForTableView:tableView atIndex:indexPath.row];
    }
    return [self recommendationCellForTableView:tableView atIndex:indexPath.row];
}

- (UITableViewCell *)bannerCellForTableView:(UITableView *)tableView atIndex:(NSInteger)index {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kBannerCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kBannerCellID];
    }
    FWAProviderStatusPresentation *banner = self.banners[index];

    cell.textLabel.text = banner.message;
    cell.textLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    // ok==true statuses never reach here (presentationsForStatuses: omits
    // them), so only the two "something's not normal" severities render —
    // deliberately styled differently: Info is calm/neutral (it's not a
    // failure), Degraded is flagged (it is).
    if (banner.severity == FWAProviderStatusSeverityInfo) {
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.backgroundColor = [UIColor secondarySystemBackgroundColor];
        cell.imageView.image = [UIImage systemImageNamed:@"info.circle"];
        cell.imageView.tintColor = [UIColor systemBlueColor];
    } else {
        cell.textLabel.textColor = [UIColor systemOrangeColor];
        cell.backgroundColor = [UIColor systemBackgroundColor];
        cell.imageView.image = [UIImage systemImageNamed:@"exclamationmark.triangle"];
        cell.imageView.tintColor = [UIColor systemOrangeColor];
    }

    return cell;
}

- (UITableViewCell *)recommendationCellForTableView:(UITableView *)tableView atIndex:(NSInteger)index {
    FWARecommendationCell *cell = (FWARecommendationCell *)[tableView dequeueReusableCellWithIdentifier:kRecommendationCellID];
    if (!cell) {
        cell = [[FWARecommendationCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kRecommendationCellID];
    }
    Recommendation *recommendation = self.recommendations[index];

    cell.titleLabel.text = recommendation.title;
    cell.metaLabel.text = [NSString stringWithFormat:@"%@ · score %.2f", recommendation.source, recommendation.score];

    // Mirrors Android's RecommendationAdapter: show details only when the
    // field is non-empty (service2-stub rows); service1-stub rows carry an
    // empty string on the wire and must render with no label and no gap.
    BOOL hasDetails = recommendation.details.length > 0;
    cell.detailsLabel.text = hasDetails ? recommendation.details : nil;
    cell.detailsLabel.hidden = !hasDetails;

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;

    return cell;
}

@end
