//
//  FWAAddSourceViewController.m
//  FunWithActivity
//

#import "FWAAddSourceViewController.h"

typedef NS_ENUM(NSInteger, FWASourceType) {
    FWASourceTypeREST = 0,
    FWASourceTypeGRPC,
};

typedef NS_ENUM(NSInteger, FWAAddSourceSection) {
    FWAAddSourceSectionSource = 0,
    FWAAddSourceSectionType,
    FWAAddSourceSectionSubmit,
    FWAAddSourceSectionCount,
};

typedef NS_ENUM(NSInteger, FWAAddSourceRow) {
    FWAAddSourceRowName = 0,
    FWAAddSourceRowBaseURL,
    FWAAddSourceRowAuthToken,
    FWAAddSourceRowCount,
};

// Kept as the literal note text so the "never stored" promise below is
// provably the same string regardless of whether a validation error is
// also showing above it in the footer.
static NSString *const kAuthTokenNeverStoredNote =
    @"Never stored — a credential for a source that can't be called yet is pure liability.";

static NSString *const kAdapterExplanationText =
    @"A new source needs an adapter — Go code implementing the Provider interface — before it can be called. This form validates and explains that; it does not add a working source.";

static NSString *const kSourceFieldCellID = @"SourceFieldCell";
static NSString *const kSourceTypeCellID = @"SourceTypeCell";
static NSString *const kSourceSubmitCellID = @"SourceSubmitCell";

#pragma mark - FWAAddSourceFieldCell

// Settings.app-style row: a leading label plus a UITextField that fills the
// rest of the cell (as opposed to FWAProfileViewController's
// FWAMeasurementFieldCell, which uses a fixed-width right-aligned
// accessoryView — that reads right for a short numeric value, but Name/Base
// URL/Auth token are free text that can run long, so the field needs the
// room a filling layout gives it).
@interface FWAAddSourceFieldCell : UITableViewCell
@property (nonatomic, strong, readonly) UILabel *fieldLabel;
@property (nonatomic, strong, readonly) UITextField *textField;
@end

@implementation FWAAddSourceFieldCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _fieldLabel = [UILabel new];
        _fieldLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        [_fieldLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_fieldLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        _textField = [[UITextField alloc] init];
        _textField.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _textField.textAlignment = NSTextAlignmentRight;
        _textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        [_textField setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.fieldLabel, self.textField]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 12;
        row.alignment = UIStackViewAlignmentCenter;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:row];

        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [row.topAnchor constraintEqualToAnchor:margins.topAnchor constant:6],
            [row.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-6],
            [row.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        ]];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

@end

#pragma mark - FWAAddSourceFooterView

// The SOURCE section footer. Normally just the "never stored" note; when a
// validation error fires, the error is prepended in red above it — the
// footer stays the single place that promise lives, so it can never say
// something different from what the field cells actually did.
@interface FWAAddSourceFooterView : UIView
@property (nonatomic, copy, nullable) NSString *errorText;
@end

@implementation FWAAddSourceFooterView {
    UILabel *_label;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _label = [UILabel new];
        _label.numberOfLines = 0;
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_label.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],
            [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6],
            [_label.leadingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.leadingAnchor],
            [_label.trailingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.trailingAnchor],
        ]];
        [self refresh];
    }
    return self;
}

- (void)setErrorText:(nullable NSString *)errorText {
    _errorText = [errorText copy];
    [self refresh];
}

- (void)refresh {
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
    if (self.errorText.length > 0) {
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:self.errorText
            attributes:@{
                NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote],
                NSForegroundColorAttributeName: [UIColor systemRedColor],
            }]];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
    }
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:kAuthTokenNeverStoredNote
        attributes:@{
            NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote],
            NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
        }]];
    _label.attributedText = text;
}

@end

#pragma mark - FWAAddSourceViewController

@interface FWAAddSourceViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

@property (nonatomic, strong) UITableView *tableView;

// The three field cells are created once and cached rather than dequeued
// per row-reload: this table never reloads the SOURCE section's rows (only
// its footer, via -refreshFooter), but caching removes any risk of a future
// reload silently discarding whatever the user has typed or dropping first
// responder mid-edit.
@property (nonatomic, strong) FWAAddSourceFieldCell *nameCell;
@property (nonatomic, strong) FWAAddSourceFieldCell *baseURLCell;
@property (nonatomic, strong) FWAAddSourceFieldCell *authTokenCell;

@property (nonatomic, strong) FWAAddSourceFooterView *sourceFooterView;
@property (nonatomic, assign) FWASourceType selectedType;

@end

@implementation FWAAddSourceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Add Source";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.selectedType = FWASourceTypeREST;
    [self buildUI];
}

- (void)buildUI {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        // Pinned to the keyboard's own layout guide (iOS 15+, matching this
        // target's deployment target) rather than the view's bottomAnchor:
        // the table shrinks to end exactly above the keyboard instead of
        // being covered by it, with no notification-observer plumbing.
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
    ]];

    [self buildFieldCells];

    self.sourceFooterView = [[FWAAddSourceFooterView alloc] initWithFrame:CGRectZero];

    [self configureTableHeaderView];
}

- (void)buildFieldCells {
    self.nameCell = [[FWAAddSourceFieldCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kSourceFieldCellID];
    self.nameCell.fieldLabel.text = @"Name";
    self.nameCell.textField.placeholder = @"e.g. service3";
    self.nameCell.textField.tag = FWAAddSourceRowName;
    self.nameCell.textField.delegate = self;
    self.nameCell.textField.returnKeyType = UIReturnKeyNext;

    self.baseURLCell = [[FWAAddSourceFieldCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kSourceFieldCellID];
    self.baseURLCell.fieldLabel.text = @"Base URL";
    self.baseURLCell.textField.placeholder = @"https://example.com/services/service3";
    self.baseURLCell.textField.keyboardType = UIKeyboardTypeURL;
    self.baseURLCell.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.baseURLCell.textField.tag = FWAAddSourceRowBaseURL;
    self.baseURLCell.textField.delegate = self;
    self.baseURLCell.textField.returnKeyType = UIReturnKeyNext;

    self.authTokenCell = [[FWAAddSourceFieldCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kSourceFieldCellID];
    self.authTokenCell.fieldLabel.text = @"Auth token";
    self.authTokenCell.textField.placeholder = @"optional";
    self.authTokenCell.textField.secureTextEntry = YES;
    self.authTokenCell.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.authTokenCell.textField.tag = FWAAddSourceRowAuthToken;
    self.authTokenCell.textField.delegate = self;
    self.authTokenCell.textField.returnKeyType = UIReturnKeyDone;
}

// Standard self-sizing-table-header-view dance: tableHeaderView does not
// participate in Auto Layout on its own, so its height has to be computed
// from the label's wrapped height and re-applied whenever the table's width
// is known (first layout, and rotation).
- (void)configureTableHeaderView {
    UILabel *label = [UILabel new];
    label.text = kAdapterExplanationText;
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = [UIColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-16],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20],
    ]];
    self.tableView.tableHeaderView = container;
    [self layoutTableHeaderView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutTableHeaderView];
}

- (void)layoutTableHeaderView {
    UIView *header = self.tableView.tableHeaderView;
    if (!header) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0) return;
    CGSize fitSize = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                     withHorizontalFittingPriority:UILayoutPriorityRequired
                                           verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (header.frame.size.height != fitSize.height || header.frame.size.width != width) {
        header.frame = CGRectMake(0, 0, width, fitSize.height);
        self.tableView.tableHeaderView = header;
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return FWAAddSourceSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case FWAAddSourceSectionSource: return FWAAddSourceRowCount;
        case FWAAddSourceSectionType: return 2;
        case FWAAddSourceSectionSubmit:
        default: return 1;
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == FWAAddSourceSectionSource) return @"Source";
    if (section == FWAAddSourceSectionType) return @"Type";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case FWAAddSourceSectionSource:
            return [self sourceCellForRow:indexPath.row];
        case FWAAddSourceSectionType:
            return [self typeCellForRow:indexPath.row];
        case FWAAddSourceSectionSubmit:
        default:
            return [self submitCell];
    }
}

- (FWAAddSourceFieldCell *)sourceCellForRow:(NSInteger)row {
    switch (row) {
        case FWAAddSourceRowName: return self.nameCell;
        case FWAAddSourceRowBaseURL: return self.baseURLCell;
        case FWAAddSourceRowAuthToken:
        default: return self.authTokenCell;
    }
}

// Checkmark rows rather than a segmented control: more table-native, and
// consistent with how the rest of the app expresses a single selection
// among rows (there is no other segmented-control-in-a-cell anywhere else
// in this table-based UI).
- (UITableViewCell *)typeCellForRow:(NSInteger)row {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kSourceTypeCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kSourceTypeCellID];
    }
    FWASourceType rowType = row == 0 ? FWASourceTypeREST : FWASourceTypeGRPC;
    cell.textLabel.text = rowType == FWASourceTypeREST ? @"REST" : @"gRPC";
    cell.accessoryType = rowType == self.selectedType ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UITableViewCell *)submitCell {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kSourceSubmitCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kSourceSubmitCellID];
    }
    cell.textLabel.text = @"Add Source";
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return section == FWAAddSourceSectionSource ? self.sourceFooterView : nil;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == FWAAddSourceSectionType) {
        [self didSelectTypeRow:indexPath.row];
    } else if (indexPath.section == FWAAddSourceSectionSubmit) {
        [self didTapSubmit];
    }
}

- (void)didSelectTypeRow:(NSInteger)row {
    FWASourceType newType = row == 0 ? FWASourceTypeREST : FWASourceTypeGRPC;
    if (newType == self.selectedType) return;
    self.selectedType = newType;
    // Only the two TYPE rows reload — this never touches the SOURCE
    // section's cached field cells, so in-progress typing there is
    // unaffected.
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:FWAAddSourceSectionType]
                   withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - Submit

- (void)didTapSubmit {
    [self.view endEditing:YES];
    [self setValidationError:nil];

    NSString *name = [self.nameCell.textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *baseURL = [self.baseURLCell.textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (name.length == 0) {
        [self setValidationError:@"Name is required."];
        return;
    }
    if (baseURL.length == 0) {
        [self setValidationError:@"Base URL is required."];
        return;
    }
    NSURL *url = [NSURL URLWithString:baseURL];
    if (url == nil || url.scheme == nil || url.host == nil) {
        [self setValidationError:@"Base URL must be a valid absolute URL, e.g. https://example.com/services/name."];
        return;
    }

    // The auth token field is read only long enough to be discarded here —
    // it is never assigned to an ivar, a model object, or anything that
    // outlives this method, matching "do not store the auth token."
    NSString *type = self.selectedType == FWASourceTypeGRPC ? @"gRPC" : @"REST";

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Not supported yet"
                         message:[NSString stringWithFormat:
            @"“%@” (%@, %@) validated, but adding a source isn't supported yet. It needs an adapter — Go code implementing the Provider interface for %@'s request/response shape — before it can be called. Nothing was saved, and the auth token you entered was not stored.",
            name, baseURL, type, type]
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// Updates only the SOURCE section's footer view in place, then asks the
// table to re-measure it (beginUpdates/endUpdates re-queries the
// automatic-dimension footer height without calling back into
// cellForRowAtIndexPath for the field rows) — so a validation error can
// never wipe out whatever the user has already typed.
- (void)setValidationError:(nullable NSString *)message {
    self.sourceFooterView.errorText = message;
    [self.tableView beginUpdates];
    [self.tableView endUpdates];
}

#if DEBUG
- (void)debug_fillValidFormAndSubmit {
    self.nameCell.textField.text = @"service3";
    self.baseURLCell.textField.text = @"https://example.com/services/service3";
    self.authTokenCell.textField.text = @"demo-token-not-stored";
    self.selectedType = FWASourceTypeGRPC;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:FWAAddSourceSectionType]
                   withRowAnimation:UITableViewRowAnimationNone];
    [self didTapSubmit];
}
#endif

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    switch (textField.tag) {
        case FWAAddSourceRowName:
            [self.baseURLCell.textField becomeFirstResponder];
            break;
        case FWAAddSourceRowBaseURL:
            [self.authTokenCell.textField becomeFirstResponder];
            break;
        case FWAAddSourceRowAuthToken:
        default:
            [textField resignFirstResponder];
            break;
    }
    return YES;
}

// Scrolls the row for the field that just became first responder into
// view. Combined with the tableView bottom being pinned to
// view.keyboardLayoutGuide.topAnchor (see -buildUI), this keeps the active
// field visible above the keyboard rather than letting it end up hidden
// underneath.
- (void)textFieldDidBeginEditing:(UITextField *)textField {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:textField.tag inSection:FWAAddSourceSectionSource];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionNone animated:YES];
    });
}

@end
