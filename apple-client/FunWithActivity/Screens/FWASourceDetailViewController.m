//
//  FWASourceDetailViewController.m
//  FunWithActivity
//

#import "FWASourceDetailViewController.h"
#import "FWASourceStatusFormatting.h"
#import "FWAProviderStatusPresentation.h"
#import "Recommendations.pbobjc.h"
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, FWASourceDetailSection) {
    FWASourceDetailSectionConfiguration = 0,
    FWASourceDetailSectionStatus,
    FWASourceDetailSectionCount,
};

typedef NS_ENUM(NSInteger, FWASourceDetailConfigurationRow) {
    FWASourceDetailConfigurationRowName = 0,
    FWASourceDetailConfigurationRowType,
    FWASourceDetailConfigurationRowBaseURL,
    FWASourceDetailConfigurationRowCount,
};

typedef NS_ENUM(NSInteger, FWASourceDetailStatusRow) {
    FWASourceDetailStatusRowStatus = 0,
    FWASourceDetailStatusRowLatency,
    FWASourceDetailStatusRowLastError,
    FWASourceDetailStatusRowCount,
};

static NSString *const kValueCellID = @"SourceDetailValueCell";
static NSString *const kWrappingCellID = @"SourceDetailWrappingCell";

#pragma mark - FWASourceConfig

// Client-side, deployment-time-known configuration for a source. `baseURL`
// is NOT here: it used to be a client-side fabrication (or a fixed "not
// exposed" string) precisely because ProviderStatus carried no such field.
// As of recommendations.proto field 7 (base_url), the real endpoint IS on
// the wire — see FWABaseURLDisplayValue below — so this type now only
// holds the one property genuinely unknown to the wire.
//
// `type` is a genuine, known property of a built-in adapter (both vendors
// are Lambda-fronted REST endpoints — see app-server's
// providers/envelope.go) and is safe to state plainly.
//
// `editable` exists so a future user-added source (once
// FWAAddSourceViewController's "not supported yet" stub becomes real) has
// somewhere to record that it CAN be edited — nothing reads it yet, and no
// editing UI exists.
@interface FWASourceConfig : NSObject
@property (nonatomic, copy, readonly) NSString *type;
@property (nonatomic, assign, readonly, getter=isEditable) BOOL editable;
+ (instancetype)configWithType:(NSString *)type editable:(BOOL)editable;
@end

@implementation FWASourceConfig

+ (instancetype)configWithType:(NSString *)type editable:(BOOL)editable {
    FWASourceConfig *config = [self new];
    config->_type = [type copy];
    config->_editable = editable;
    return config;
}

// Both built-in providers, identically: real REST adapters. Not name-keyed
// — this fact does not vary between service1 and service2.
+ (instancetype)builtInSourceConfig {
    return [self configWithType:@"REST" editable:NO];
}

@end

// The fallback text for an empty ProviderStatus.baseURL. A new field: a
// server predating it, or a provider with nothing configured, yields "".
// This is the one place that string is chosen — never fabricate a URL to
// fill the row, which is exactly the invented data this feature replaced.
static NSString *const kBaseURLNotExposedText = @"Not exposed to clients";

static NSString *FWABaseURLDisplayValue(NSString *_Nullable baseURL) {
    return baseURL.length > 0 ? baseURL : kBaseURLNotExposedText;
}

#pragma mark - FWACopyableWrappingCell

// `error` and the real `baseURL` both genuinely can run long — a real
// vendor error can embed a full URL (see FWASourcesViewController's header
// doc), and a real base URL is a full Lambda function URL — so Last error
// and Base URL use UITableViewCellStyleSubtitle (label on top, full-width
// wrapping value below, like Settings' Wi-Fi/IP address rows) rather than
// UITableViewCellStyleValue1: Value1's side-by-side layout does not size
// correctly with a multi-line detailTextLabel (its baked-in constraints
// assume one line for both labels), so a wrapped value either clips or
// overlaps the row below it. Name/Type/Status/Latency stay plain Value1
// cells; they are short, single-line, and already correct.
//
// Long-press → Copy on the value, for an operator who wants it in the
// clipboard rather than retyped.
@interface FWACopyableWrappingCell : UITableViewCell
- (void)setCopyableValue:(nullable NSString *)value;
@end

@implementation FWACopyableWrappingCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self) {
        self.detailTextLabel.numberOfLines = 0;
        self.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        UILongPressGestureRecognizer *longPress =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        [self addGestureRecognizer:longPress];
    }
    return self;
}

- (void)setCopyableValue:(nullable NSString *)value {
    objc_setAssociatedObject(self, @selector(copyableValue), value, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (nullable NSString *)copyableValue {
    return objc_getAssociatedObject(self, @selector(copyableValue));
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan || self.copyableValue.length == 0) {
        return;
    }
    [self becomeFirstResponder];
    UIMenuController *menu = [UIMenuController sharedMenuController];
    [menu showMenuFromView:self rect:self.bounds];
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (BOOL)canPerformAction:(SEL)action withSender:(nullable id)sender {
    return action == @selector(copy:) && self.copyableValue.length > 0;
}

- (void)copy:(nullable id)sender {
    [UIPasteboard generalPasteboard].string = self.copyableValue;
}

@end

#pragma mark - FWASourceDetailViewController

@interface FWASourceDetailViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, copy, readonly) NSString *providerName;
@property (nonatomic, strong, readonly, nullable) ProviderStatus *status;
@property (nonatomic, strong, readonly) FWASourceConfig *config;
@property (nonatomic, strong, readonly, nullable) FWAProviderStatusPresentation *presentation;
@property (nonatomic, strong) UITableView *tableView;

@end

@implementation FWASourceDetailViewController

- (instancetype)initWithProviderName:(NSString *)providerName status:(nullable ProviderStatus *)status {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _providerName = [providerName copy];
        _status = status;
        // Phase 1 only ever reaches this screen for a built-in provider —
        // see FWASourcesViewController's header doc (no separate registry
        // RPC yet) — so there is exactly one config to hand out.
        _config = [FWASourceConfig builtInSourceConfig];

        // The skipped-vs-degraded decision is NOT re-derived here — see
        // FWAProviderStatusPresentation's header doc. This screen only asks
        // it the same question FWASourcesViewController does and renders
        // its answer; nil (ok, or no status yet) is a valid outcome.
        _presentation = status != nil
            ? [FWAProviderStatusPresentation presentationsForStatuses:@[status]].firstObject
            : nil;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.providerName;
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    // Same UITableViewStyleInsetGrouped style as FWAProfileViewController —
    // explicit design requirement (see this file's header doc).
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    // Last error wraps to multiple lines (see FWACopyableWrappingCell
    // above) — without automatic sizing the row height stays fixed and
    // wrapped text overlaps the row below it.
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
    return FWASourceDetailSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == FWASourceDetailSectionConfiguration
        ? FWASourceDetailConfigurationRowCount
        : FWASourceDetailStatusRowCount;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == FWASourceDetailSectionConfiguration ? @"Configuration" : @"Status";
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == FWASourceDetailSectionConfiguration && !self.config.isEditable) {
        // Two things this footer is doing on purpose:
        // 1. The explicit "do not silently ignore taps" requirement: these
        //    rows are plain (no accessory, no selection) rather than
        //    looking like disabled controls, and this says why in words.
        // 2. Explains the Base URL row's value when it IS empty: some
        //    servers/providers still have nothing to report there — see
        //    FWABaseURLDisplayValue.
        return @"Built-in sources are configured at deployment time and cannot be edited in the app. If Base URL shows \"Not exposed to clients\", this server or provider has nothing configured for it.";
    }
    if (section == FWASourceDetailSectionStatus) {
        return @"Status and latency come from the most recent Recommendations fetch and are not saved.";
    }
    return nil;
}

// Base URL and Last error are both wrapping rows: Base URL now carries the
// real ProviderStatus.baseURL (a full Lambda function URL, not the old
// fixed "Not exposed to clients" stand-in), and `error` genuinely can be
// long — a real vendor error can embed a full URL (see
// FWASourcesViewController's header doc). Name/Type/Status/Latency stay
// plain right-aligned Value1 rows; they are short, single-line, and
// already correct.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL isBaseURLRow = indexPath.section == FWASourceDetailSectionConfiguration
        && indexPath.row == FWASourceDetailConfigurationRowBaseURL;
    BOOL isLastErrorRow = indexPath.section == FWASourceDetailSectionStatus
        && indexPath.row == FWASourceDetailStatusRowLastError;

    if (isBaseURLRow || isLastErrorRow) {
        FWACopyableWrappingCell *cell = [tableView dequeueReusableCellWithIdentifier:kWrappingCellID];
        if (!cell) {
            cell = [[FWACopyableWrappingCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kWrappingCellID];
        }
        if (isBaseURLRow) {
            [self configureBaseURLCell:cell];
        } else {
            [self configureLastErrorCell:cell];
        }
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kValueCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kValueCellID];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    if (indexPath.section == FWASourceDetailSectionConfiguration) {
        [self configureConfigurationValueCell:cell atRow:indexPath.row];
    } else {
        [self configureStatusValueCell:cell atRow:indexPath.row];
    }
    return cell;
}

- (void)configureConfigurationValueCell:(UITableViewCell *)cell atRow:(NSInteger)row {
    switch (row) {
        case FWASourceDetailConfigurationRowName:
        default:
            cell.textLabel.text = @"Name";
            cell.detailTextLabel.text = self.providerName;
            break;
        case FWASourceDetailConfigurationRowType:
            cell.textLabel.text = @"Type";
            cell.detailTextLabel.text = self.config.type;
            break;
    }
}

- (void)configureStatusValueCell:(UITableViewCell *)cell atRow:(NSInteger)row {
    switch (row) {
        case FWASourceDetailStatusRowStatus:
            cell.textLabel.text = @"Status";
            cell.detailTextLabel.text = FWAStatusWord(self.presentation);
            cell.detailTextLabel.textColor = FWAStatusColor(self.presentation);
            break;
        case FWASourceDetailStatusRowLatency:
        default:
            cell.textLabel.text = @"Latency";
            cell.detailTextLabel.text = FWALatencyText(self.status.latencyMs);
            break;
    }
}

// Monospace: a URL/hostname is an identifier, not prose — easier to scan
// and to eyeball-diff against another environment's value than proportional
// text would be (matches Android's activity_source_detail.xml treatment of
// the same field). Never fabricate a value: an empty baseURL (server
// predating field 7, or a provider with nothing configured) renders the
// honest "Not exposed to clients" placeholder via FWABaseURLDisplayValue,
// and that placeholder is not offered for copy.
- (void)configureBaseURLCell:(FWACopyableWrappingCell *)cell {
    cell.textLabel.text = @"Base URL";
    NSString *baseURL = self.status.baseURL;
    cell.detailTextLabel.text = FWABaseURLDisplayValue(baseURL);
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:UIFont.smallSystemFontSize weight:UIFontWeightRegular];
    [cell setCopyableValue:baseURL.length > 0 ? baseURL : nil];
}

- (void)configureLastErrorCell:(FWACopyableWrappingCell *)cell {
    cell.textLabel.text = @"Last error";
    // The FULL text, uncut, including any vendor URL it embeds — this is
    // the one place in the app an operator should see it;
    // FWASourcesViewController truncates this to a short reason for the
    // list (see that file's header doc).
    NSString *error = self.status.error;
    cell.detailTextLabel.text = error.length > 0 ? error : @"—";
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    [cell setCopyableValue:error.length > 0 ? error : nil];
}

@end
