//
//  FWARecommendationsViewController.m
//  FunWithActivity
//

#import "FWARecommendationsViewController.h"
#import "FWAGRPCClient.h"
#import "FWAAppState.h"
#import "FWAProviderStatusPresentation.h"
#import "Recommendations.pbobjc.h"
#if DEBUG
#import <os/log.h>
#endif

static NSString *const kBannerCellID = @"BannerCell";
static NSString *const kRecommendationCellID = @"RecommendationCell";
static NSString *const kConnectionErrorCellID = @"ConnectionErrorCell";

typedef NS_ENUM(NSInteger, FWARecsSection) {
    FWARecsSectionBanners = 0,
    FWARecsSectionRecommendations,
    FWARecsSectionCount,
};

// Same self-sizing three-label cell FWAResultsViewController used to use —
// title + optional details (service2-stub rows carry text, service1-stub
// rows don't) + source/score meta line.
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

@interface FWARecommendationsViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong, readonly) FWAGRPCClient *grpcClient;
@property (nonatomic, strong, readonly) FWAAppState *appState;

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<Recommendation *> *recommendations;
@property (nonatomic, strong) NSArray<FWAProviderStatusPresentation *> *banners;
@property (nonatomic, copy, nullable) NSString *connectionErrorMessage;
@property (nonatomic, assign) BOOL hasFetchedOnce;
@property (nonatomic, assign) BOOL isFetching;

@end

@implementation FWARecommendationsViewController

- (instancetype)initWithGRPCClient:(FWAGRPCClient *)grpcClient appState:(FWAAppState *)appState {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _grpcClient = grpcClient;
        _appState = appState;
        _recommendations = @[];
        _banners = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Recommendations";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 44;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // Pull-to-refresh: the manual refresh control §5.2 calls for, and the
    // one path that always fetches regardless of the dirty flag.
    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(didPullToRefresh) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = refresh;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // The refetch policy this whole tab exists to demonstrate: fetch once
    // on first appearance regardless, and on every later appearance only
    // when something in Profile changed since the last fetch. Unconditional
    // refetch would burn a vendor call on every tab switch; never
    // refetching would make edits in Profile invisible here.
    if (!self.hasFetchedOnce || self.appState.isDirty) {
        [self fetchRecommendations];
    }
}

- (void)didPullToRefresh {
    [self fetchRecommendations];
}

- (void)fetchRecommendations {
    if (self.isFetching) return;
    self.isFetching = YES;
    if (!self.tableView.refreshControl.isRefreshing) {
        [self.tableView.refreshControl beginRefreshing];
    }

    int64_t birthDateUnix = self.appState.birthDate != nil
        ? (int64_t)[self.appState.birthDate timeIntervalSince1970]
        : 0;

    __weak typeof(self) weakSelf = self;
    [self.grpcClient getRecommendationsWithHeightCm:self.appState.heightCm
                                             weightKg:self.appState.weightKg
                                        birthDateUnix:birthDateUnix
                                               faults:[self.appState faultsForRequest]
                                           completion:^(GetRecommendationsResponse * _Nullable response, NSError * _Nullable error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf handleFetchResponse:response error:error];
    }];
}

- (void)handleFetchResponse:(GetRecommendationsResponse *_Nullable)response error:(NSError *_Nullable)error {
    self.isFetching = NO;
    self.hasFetchedOnce = YES;
    [self.tableView.refreshControl endRefreshing];

    if (error || !response) {
        self.connectionErrorMessage = [NSString stringWithFormat:@"Couldn't reach the server: %@",
                                        error.localizedDescription ?: @"unknown error"];
        // Deliberately do NOT clear appState.isDirty on a transport
        // failure — a dirty edit that never actually got fetched should
        // still be retried the next time this tab appears, not silently
        // dropped. Successful fetches always clear it below.
        [self.tableView reloadData];
        return;
    }

    self.connectionErrorMessage = nil;
    self.recommendations = [response.recommendationsArray copy] ?: @[];
    self.banners = [FWAProviderStatusPresentation presentationsForStatuses:response.statusesArray ?: @[]];
    [self.appState recordResponse:response];
    [self.appState clearDirty];
#if DEBUG
    [self logRenderedContentForDemoVerification];
#endif
    [self.tableView reloadData];
}

#if DEBUG
- (void)logRenderedContentForDemoVerification {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.funwithactivity.ios", "recommendations");
    });

    os_log(log, "Recommendations refreshed — banners=%lu recommendations=%lu dirty=%d",
           (unsigned long)self.banners.count, (unsigned long)self.recommendations.count, self.appState.isDirty);
    [self.banners enumerateObjectsUsingBlock:^(FWAProviderStatusPresentation *banner, NSUInteger idx, BOOL *stop) {
        os_log(log, "banner[%lu] provider=%{public}@ severity=%ld message=%{public}@",
               (unsigned long)idx, banner.providerName, (long)banner.severity, banner.message);
    }];
    [self.recommendations enumerateObjectsUsingBlock:^(Recommendation *rec, NSUInteger idx, BOOL *stop) {
        os_log(log, "recommendation[%lu] score=%.2f source=%{public}@ title=%{public}@",
               (unsigned long)idx, rec.score, rec.source, rec.title);
    }];
}
#endif

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return FWARecsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == FWARecsSectionBanners) {
        NSInteger count = self.banners.count;
        if (self.connectionErrorMessage != nil) count += 1;
        return count;
    }
    return self.recommendations.count;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == FWARecsSectionBanners) {
        BOOL hasAny = self.banners.count > 0 || self.connectionErrorMessage != nil;
        return hasAny ? @"Notices" : nil;
    }
    return self.recommendations.count > 0 ? @"Recommendations" : @"No recommendations";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == FWARecsSectionBanners) {
        // The connection-error row (if any) always sorts first — it
        // explains why provider banners/recommendations might be stale or
        // absent, so it should be the first thing read.
        if (self.connectionErrorMessage != nil) {
            if (indexPath.row == 0) {
                return [self connectionErrorCellForTableView:tableView];
            }
            return [self bannerCellForTableView:tableView atIndex:indexPath.row - 1];
        }
        return [self bannerCellForTableView:tableView atIndex:indexPath.row];
    }
    return [self recommendationCellForTableView:tableView atIndex:indexPath.row];
}

- (UITableViewCell *)connectionErrorCellForTableView:(UITableView *)tableView {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kConnectionErrorCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kConnectionErrorCellID];
    }
    cell.textLabel.text = self.connectionErrorMessage;
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.textColor = [UIColor systemRedColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.imageView.image = [UIImage systemImageNamed:@"wifi.exclamationmark"];
    cell.imageView.tintColor = [UIColor systemRedColor];
    return cell;
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

    // Info (declined input, e.g. birth date withheld) reads calm/neutral —
    // it is not a failure. Degraded (genuine outage / fault-injected
    // failure) is flagged. Deliberately distinct styling per the demo
    // requirement that these two read as different in kind, not just in
    // wording.
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

    BOOL hasDetails = recommendation.details.length > 0;
    cell.detailsLabel.text = hasDetails ? recommendation.details : nil;
    cell.detailsLabel.hidden = !hasDetails;

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;

    return cell;
}

@end
