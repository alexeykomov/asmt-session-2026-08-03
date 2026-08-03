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

// Client-side, deployment-time-known configuration for a source. NOT on the
// wire — ProviderStatus carries only name/ok/skipped/error/count/latencyMs
// (Recommendations.pbobjc.h) — there is no baseURL field, and adding one is
// out of scope (the wire contract is frozen for this release).
//
// `type` is a genuine, known property of a built-in adapter (both vendors
// are Lambda-fronted REST endpoints — see app-server's
// providers/envelope.go) and is safe to state plainly.
//
// `baseURL` is deliberately NOT a fabricated address. A mobile binary is an
// artifact a customer can extract, inspect, or side-load (see
// docs/mobile/fault-injection-decision.md for the same reasoning applied to
// fault injection) — shipping a real per-vendor endpoint inside one is a
// liability with no benefit, and inventing a fake-looking one to fill the
// row is worse: it reads as real configuration to anyone who doesn't know
// better. The honest value is that provider endpoints are deployment
// configuration the client was never told, and the footer says so.
//
// `editable` exists so a future user-added source (once
// FWAAddSourceViewController's "not supported yet" stub becomes real) has
// somewhere to record that it CAN be edited — nothing reads it yet, and no
// editing UI exists.
@interface FWASourceConfig : NSObject
@property (nonatomic, copy, readonly) NSString *type;
@property (nonatomic, copy, readonly) NSString *baseURL;
@property (nonatomic, assign, readonly, getter=isEditable) BOOL editable;
+ (instancetype)configWithType:(NSString *)type baseURL:(NSString *)baseURL editable:(BOOL)editable;
@end

@implementation FWASourceConfig

+ (instancetype)configWithType:(NSString *)type baseURL:(NSString *)baseURL editable:(BOOL)editable {
    FWASourceConfig *config = [self new];
    config->_type = [type copy];
    config->_baseURL = [baseURL copy];
    config->_editable = editable;
    return config;
}

// Both built-in providers, identically: real REST adapters, endpoint not
// exposed to the client. Not name-keyed — unlike a fabricated per-vendor
// URL, this fact does not vary between service1 and service2.
+ (instancetype)builtInSourceConfig {
    return [self configWithType:@"REST" baseURL:@"Not exposed to clients" editable:NO];
}

@end

#pragma mark - FWACopyableWrappingCell

// `error` genuinely can run long — a real vendor error can embed a full URL
// (see FWASourcesViewController's header doc) — so Last error uses
// UITableViewCellStyleSubtitle (label on top, full-width wrapping value
// below, like Settings' Wi-Fi/IP address rows) rather than
// UITableViewCellStyleValue1: Value1's side-by-side layout does not size
// correctly with a multi-line detailTextLabel (its baked-in constraints
// assume one line for both labels), so a wrapped value either clips or
// overlaps the row below it. Name/Type/Base URL/Status/Latency stay plain
// Value1 cells; they are short, single-line, and already correct.
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
        // 2. Explains the Base URL row's value: provider endpoints are
        //    deployment configuration, deliberately never shipped to a
        //    client binary — see FWASourceConfig's header doc.
        return @"Built-in sources are configured at deployment time and cannot be edited in the app. Provider endpoints are deployment configuration and are not exposed to the client.";
    }
    if (section == FWASourceDetailSectionStatus) {
        return @"Status and latency come from the most recent Recommendations fetch and are not saved.";
    }
    return nil;
}

// Only Last error is a wrapping row now: Base URL's value ("Not exposed to
// clients" — see FWASourceConfig's header doc) is short and fixed, same
// shape as Name/Type, so it stays a plain right-aligned Value1 row.
// `error`, on the other hand, genuinely can be long — a real vendor error
// can embed a full URL (see FWASourcesViewController's header doc) — so it
// keeps the self-sizing wrapping cell.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL isWrappingRow = indexPath.section == FWASourceDetailSectionStatus
        && indexPath.row == FWASourceDetailStatusRowLastError;

    if (isWrappingRow) {
        FWACopyableWrappingCell *cell = [tableView dequeueReusableCellWithIdentifier:kWrappingCellID];
        if (!cell) {
            cell = [[FWACopyableWrappingCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kWrappingCellID];
        }
        [self configureLastErrorCell:cell];
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
            cell.textLabel.text = @"Name";
            cell.detailTextLabel.text = self.providerName;
            break;
        case FWASourceDetailConfigurationRowType:
            cell.textLabel.text = @"Type";
            cell.detailTextLabel.text = self.config.type;
            break;
        case FWASourceDetailConfigurationRowBaseURL:
        default:
            cell.textLabel.text = @"Base URL";
            cell.detailTextLabel.text = self.config.baseURL;
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
