//
//  FWASourcesViewController.m
//  FunWithActivity
//

#import "FWASourcesViewController.h"
#import "FWAAddSourceViewController.h"
#import "FWASourceDetailViewController.h"
#import "FWASourceStatusFormatting.h"
#import "FWAAppState.h"
#import "FWAProviderStatusPresentation.h"
#import "Recommendations.pbobjc.h"

static NSString *const kSourceCellID = @"SourceCell";
static NSString *const kPlaceholderCellID = @"PlaceholderCell";

// Same three-line stacked-label convention as the recommendation cell:
// name, then a status+latency meta line, then an optional error line.
@interface FWASourceCell : UITableViewCell
@property (nonatomic, strong, readonly) UILabel *nameLabel;
@property (nonatomic, strong, readonly) UILabel *statusLabel;
@property (nonatomic, strong, readonly) UILabel *errorLabel;
@end

@implementation FWASourceCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _nameLabel = [UILabel new];
        _nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];

        _statusLabel = [UILabel new];
        _statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];

        _errorLabel = [UILabel new];
        _errorLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _errorLabel.textColor = [UIColor secondaryLabelColor];
        _errorLabel.numberOfLines = 0;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameLabel, self.statusLabel, self.errorLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 4;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];

        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:margins.topAnchor constant:10],
            [stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-10],
            [stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        ]];
    }
    return self;
}

@end

@interface FWASourcesViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong, readonly) FWAAppState *appState;
@property (nonatomic, strong) UITableView *tableView;

@end

@implementation FWASourcesViewController

- (instancetype)initWithAppState:(FWAAppState *)appState {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _appState = appState;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Sources";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                        target:self
                                                        action:@selector(didTapAdd)];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // Reload whenever the Recommendations tab records a new response, even
    // while this screen is the visible one — Sources does not trigger its
    // own fetch, it only ever reflects the most recent one.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(didUpdateStatuses)
                                                  name:FWAAppStateDidUpdateStatusesNotification
                                                object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)didUpdateStatuses {
    [self.tableView reloadData];
}

- (void)didTapAdd {
    FWAAddSourceViewController *addVC = [[FWAAddSourceViewController alloc] init];
    [self.navigationController pushViewController:addVC animated:YES];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray<ProviderStatus *> *statuses = self.appState.lastStatuses;
    return statuses.count > 0 ? statuses.count : 1;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Providers";
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Status and latency come from the most recent Recommendations fetch.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<ProviderStatus *> *statuses = self.appState.lastStatuses;
    if (statuses.count == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPlaceholderCellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kPlaceholderCellID];
        }
        cell.textLabel.text = @"Waiting for the first fetch — check the Recommendations tab.";
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    FWASourceCell *cell = (FWASourceCell *)[tableView dequeueReusableCellWithIdentifier:kSourceCellID];
    if (!cell) {
        cell = [[FWASourceCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kSourceCellID];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    ProviderStatus *status = statuses[indexPath.row];
    cell.nameLabel.text = status.name;

    NSString *latencyText = FWALatencyText(status.latencyMs);

    // The skipped-vs-degraded decision is NOT re-derived here. It is made
    // exactly once, by FWAProviderStatusPresentation (see its header doc:
    // branch on `skipped` before `error` — inverting that has already
    // caused four defects on this project). This screen only asks that
    // object for the answer and renders it; an empty result means `ok` was
    // true, which is the one case that object doesn't need to be asked
    // about because it isn't a decision — it's the input already saying
    // "no notice needed".
    NSArray<FWAProviderStatusPresentation *> *presentations =
        [FWAProviderStatusPresentation presentationsForStatuses:@[status]];

    if (presentations.count == 0) {
        cell.statusLabel.text = [NSString stringWithFormat:@"● ok · %@", latencyText];
        cell.statusLabel.textColor = FWAStatusColor(nil);
        cell.errorLabel.text = nil;
        cell.errorLabel.hidden = YES;
    } else {
        FWAProviderStatusPresentation *presentation = presentations.firstObject;
        cell.statusLabel.text = [NSString stringWithFormat:@"● %@ · %@", FWAStatusWord(presentation), latencyText];
        cell.statusLabel.textColor = FWAStatusColor(presentation);

        // Short, list-safe reason only — never the full `error`, which can
        // embed an entire vendor URL (that URL got captured live and
        // projected during a demo once already). The full text moves to
        // FWASourceDetailViewController's STATUS section, where an
        // operator genuinely needs it.
        cell.errorLabel.text = FWAShortStatusReason(presentation, status);
        cell.errorLabel.hidden = NO;
    }

    return cell;
}

#pragma mark - UITableViewDelegate (selection)

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSArray<ProviderStatus *> *statuses = self.appState.lastStatuses;
    if (statuses.count == 0) {
        return; // the "waiting for the first fetch" placeholder row — not tappable
    }

    ProviderStatus *status = statuses[indexPath.row];
    FWASourceDetailViewController *detailVC =
        [[FWASourceDetailViewController alloc] initWithProviderName:status.name status:status];
    [self.navigationController pushViewController:detailVC animated:YES];
}

@end
