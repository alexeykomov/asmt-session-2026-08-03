//
//  FWARecommendationDetailViewController.m
//  FunWithActivity
//

#import "FWARecommendationDetailViewController.h"

#import "FWAProviderStatusPresentation.h"
#import "FWASourceStatusFormatting.h"
#import "Recommendations.pbobjc.h"

typedef NS_ENUM(NSInteger, FWARecDetailSection) {
    FWARecDetailSectionRecommendation = 0,
    FWARecDetailSectionProvenance,
    FWARecDetailSectionRanking,
    FWARecDetailSectionCount,
};

typedef NS_ENUM(NSInteger, FWARecDetailRankingRow) {
    FWARecDetailRankingRowScore = 0,
    FWARecDetailRankingRowRank,
    FWARecDetailRankingRowCount,
};

static NSString *const kDetailsCellID = @"FWARecDetailDetailsCell";
static NSString *const kProvenanceCellID = @"FWARecDetailProvenanceCell";
static NSString *const kRankingCellID = @"FWARecDetailRankingCell";

/// The server joins every contributing provider into `source` with ", "
/// (ExactTitleDeduper sets Source to the joined display string and keeps the
/// winner's own provider in PrimarySource). Splitting it back apart is the
/// only way to show per-provider status, and it is safe because provider
/// names are registry keys, not free text, so they cannot contain a comma.
static NSString *const kSourceSeparator = @", ";

/// Shown when the vendor supplied no details. Service 1 has no details field
/// at all, so this is its data rather than a rendering failure.
static NSString *const kNoDetailsText = @"This provider supplied no detail text.";

@interface FWARecommendationDetailViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) Recommendation *recommendation;
/// One entry per provider named in `recommendation.source`, in the order the
/// server listed them (first-seen order from the fan-out). `status` is nil
/// when the response carried no status for a provider that nonetheless
/// contributed — which should not happen, and is rendered as "no data"
/// rather than an invented "ok".
@property (nonatomic, strong) NSArray<NSString *> *providerNames;
@property (nonatomic, strong) NSDictionary<NSString *, ProviderStatus *> *statusesByName;
@property (nonatomic, assign) NSInteger rank;
@property (nonatomic, assign) NSInteger total;
@end

@implementation FWARecommendationDetailViewController

- (instancetype)initWithRecommendation:(Recommendation *)recommendation
                              statuses:(NSArray<ProviderStatus *> *)statuses
                                  rank:(NSInteger)rank
                                 total:(NSInteger)total {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _recommendation = recommendation;
        _rank = rank;
        _total = total;

        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSString *raw in [recommendation.source componentsSeparatedByString:kSourceSeparator]) {
            NSString *name = [raw stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceCharacterSet]];
            // Drop empties so a trailing or doubled separator cannot
            // produce a blank provenance row.
            if (name.length > 0) {
                [names addObject:name];
            }
        }
        _providerNames = [names copy];

        NSMutableDictionary<NSString *, ProviderStatus *> *byName =
            [NSMutableDictionary dictionaryWithCapacity:statuses.count];
        for (ProviderStatus *status in statuses) {
            if (status.name.length > 0) {
                byName[status.name] = status;
            }
        }
        _statusesByName = [byName copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.recommendation.title;
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    // Same UITableViewStyleInsetGrouped style as FWAProfileViewController
    // and FWASourceDetailViewController (see this file's header doc).
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero
                                                  style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    // Details text wraps to several lines; without automatic sizing the row
    // height stays fixed and the text overlaps the row below it.
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
    return FWARecDetailSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case FWARecDetailSectionRecommendation:
            return 1;
        case FWARecDetailSectionProvenance:
            // Always at least one row: a recommendation with an empty
            // source would otherwise render an empty section with a footer
            // explaining a merge that is not shown.
            return MAX((NSInteger)self.providerNames.count, (NSInteger)1);
        case FWARecDetailSectionRanking:
            return FWARecDetailRankingRowCount;
        default:
            return 0;
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case FWARecDetailSectionRecommendation: return @"RECOMMENDATION";
        case FWARecDetailSectionProvenance:     return @"PROVENANCE";
        case FWARecDetailSectionRanking:        return @"RANKING";
        default: return nil;
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == FWARecDetailSectionProvenance) {
        if (self.providerNames.count > 1) {
            return [NSString stringWithFormat:
                    @"Returned independently by %lu providers and merged into one entry. "
                    @"The highest-scoring instance won; any details only the other supplied "
                    @"were carried across.",
                    (unsigned long)self.providerNames.count];
        }
        return @"Returned by a single provider.";
    }
    if (section == FWARecDetailSectionRanking) {
        return @"Final score only. Raw and normalised scores stay server-side by design — "
               @"exposing them would make the ranker's internals part of the wire contract.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case FWARecDetailSectionRecommendation:
            return [self detailsCellForTableView:tableView];
        case FWARecDetailSectionProvenance:
            return [self provenanceCellForTableView:tableView atIndex:indexPath.row];
        default:
            return [self rankingCellForTableView:tableView atRow:indexPath.row];
    }
}

- (UITableViewCell *)detailsCellForTableView:(UITableView *)tableView {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kDetailsCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:kDetailsCellID];
    }
    BOOL hasDetails = self.recommendation.details.length > 0;
    cell.textLabel.text = hasDetails ? self.recommendation.details : kNoDetailsText;
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.textColor = hasDetails ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (UITableViewCell *)provenanceCellForTableView:(UITableView *)tableView atIndex:(NSInteger)index {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kProvenanceCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                      reuseIdentifier:kProvenanceCellID];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (self.providerNames.count == 0) {
        cell.textLabel.text = @"Unknown";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.text = @"—";
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        return cell;
    }

    NSString *name = self.providerNames[index];
    ProviderStatus *status = self.statusesByName[name];
    cell.textLabel.text = name;
    cell.textLabel.textColor = [UIColor labelColor];

    if (status == nil) {
        // Contributed a recommendation but reported no status in the same
        // response. Say so rather than inventing an "ok" the data does not
        // support.
        cell.detailTextLabel.text = @"no data";
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        return cell;
    }

    // Same single source of truth for the skipped-vs-degraded decision the
    // list and Source detail use — never re-derived here.
    FWAProviderStatusPresentation *presentation =
        [FWAProviderStatusPresentation presentationsForStatuses:@[status]].firstObject;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@",
                                 FWAStatusWord(presentation),
                                 FWALatencyText(status.latencyMs)];
    cell.detailTextLabel.textColor = FWAStatusColor(presentation);
    return cell;
}

- (UITableViewCell *)rankingCellForTableView:(UITableView *)tableView atRow:(NSInteger)row {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kRankingCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                      reuseIdentifier:kRankingCellID];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    if (row == FWARecDetailRankingRowScore) {
        cell.textLabel.text = @"Final score";
        // Same "%.2f" the list cell uses, so the two screens cannot show a
        // different number for the same recommendation.
        cell.detailTextLabel.text =
            [NSString stringWithFormat:@"%.2f", self.recommendation.score];
    } else {
        cell.textLabel.text = @"Rank";
        cell.detailTextLabel.text = self.rank > 0
            ? [NSString stringWithFormat:@"%ld of %ld", (long)self.rank, (long)self.total]
            : @"—";
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // Every row here is read-only; nothing navigates further. Deselect so a
    // stray tap does not leave a row highlighted.
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
