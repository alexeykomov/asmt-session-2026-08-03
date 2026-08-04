//
//  FWAProfileViewController.m
//  FunWithActivity
//

#import "FWAProfileViewController.h"
#import "FWAAppState.h"
#import "FWAServerConfig.h"

/// Rows the DEVELOPER section shows before the per-provider fault toggles.
/// The endpoint is here because it is baked in at build time from .env and
/// cannot be inferred by looking at the app: the .env -> xcconfig -> pbxproj
/// chain is only re-run by `make ios`, so an ordinary Xcode build happily
/// ships a stale host. Showing the value it actually resolved removes the
/// guesswork.
typedef NS_ENUM(NSInteger, FWADeveloperRow) {
    FWADeveloperRowHost = 0,
    FWADeveloperRowTransport,
    FWADeveloperRowFixedCount,
};

typedef NS_ENUM(NSInteger, FWAProfileSection) {
    FWAProfileSectionMeasurements = 0,
    FWAProfileSectionDeveloper,
    FWAProfileSectionCount,
};

// MEASUREMENTS section rows. BirthDatePicker only exists (and only counts
// toward numberOfRowsInSection:) while the picker is expanded.
typedef NS_ENUM(NSInteger, FWAMeasurementsRow) {
    FWAMeasurementsRowHeight = 0,
    FWAMeasurementsRowWeight,
    FWAMeasurementsRowBirthDate,
    FWAMeasurementsRowBirthDatePicker,
};

static NSString *const kFieldCellID = @"FieldCell";
static NSString *const kBirthDateCellID = @"BirthDateCell";
static NSString *const kDatePickerCellID = @"DatePickerCell";
static NSString *const kFaultCellID = @"FaultCell";

#pragma mark - FWAMeasurementFieldCell

// Settings-style row: label leading, right-aligned numeric text field
// trailing, as an accessoryView so the cell's own content view stays free
// for the label (matches the Apple "Cellular" / "Display & Brightness"
// row convention for a labeled numeric input).
@interface FWAMeasurementFieldCell : UITableViewCell
@property (nonatomic, strong, readonly) UITextField *textField;
@end

@implementation FWAMeasurementFieldCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _textField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 120, 30)];
        _textField.textAlignment = NSTextAlignmentRight;
        _textField.keyboardType = UIKeyboardTypeDecimalPad;
        self.accessoryView = _textField;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

@end

#pragma mark - FWADatePickerCell

@interface FWADatePickerCell : UITableViewCell
@property (nonatomic, strong, readonly) UIDatePicker *datePicker;
@end

@implementation FWADatePickerCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _datePicker = [[UIDatePicker alloc] init];
        _datePicker.datePickerMode = UIDatePickerModeDate;
        if (@available(iOS 13.4, *)) {
            _datePicker.preferredDatePickerStyle = UIDatePickerStyleWheels;
        }
        _datePicker.maximumDate = [NSDate date];
        _datePicker.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_datePicker];
        [NSLayoutConstraint activateConstraints:@[
            [_datePicker.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_datePicker.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [_datePicker.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_datePicker.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        ]];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

@end

#pragma mark - FWAFaultCell

// DEVELOPER row: provider name + fault switch on top, a mode segmented
// control below — disabled until the switch is on, per §5.4 ("Mode
// selectors are disabled until their toggle is on"). A debug-tool section
// at the foot of a settings table, honestly labelled as such.
@interface FWAFaultCell : UITableViewCell
@property (nonatomic, strong, readonly) UILabel *nameLabel;
@property (nonatomic, strong, readonly) UISwitch *faultSwitch;
@property (nonatomic, strong, readonly) UISegmentedControl *modeControl;
@end

@implementation FWAFaultCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _nameLabel = [UILabel new];
        _nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

        _faultSwitch = [[UISwitch alloc] init];

        UIStackView *topRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameLabel, self.faultSwitch]];
        topRow.axis = UILayoutConstraintAxisHorizontal;
        topRow.distribution = UIStackViewDistributionEqualSpacing;
        topRow.alignment = UIStackViewAlignmentCenter;

        _modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Error", @"Timeout", @"Malformed"]];

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[topRow, self.modeControl]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 10;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];

        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:margins.topAnchor constant:10],
            [stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-10],
            [stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        ]];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

@end

#pragma mark - FWAProfileViewController

@interface FWAProfileViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

@property (nonatomic, strong, readonly) FWAAppState *appState;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) BOOL birthDatePickerExpanded;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;

@end

@implementation FWAProfileViewController

- (instancetype)initWithAppState:(FWAAppState *)appState {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _appState = appState;
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.dateStyle = NSDateFormatterMediumStyle;
        _dateFormatter.timeStyle = NSDateFormatterNoStyle;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Profile";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

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
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // Height/Weight use UIKeyboardTypeDecimalPad, which has no Return key at
    // all, so a tap outside is the ONLY way to dismiss short of the picker
    // row's own interaction. Same cancelsTouchesInView = NO reasoning as
    // FWAAddSourceViewController: the birth-date row selection, the Clear
    // button's accessoryView, the DEVELOPER switches and segmented controls
    // all still need their touches.
    UITapGestureRecognizer *dismissKeyboardTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    dismissKeyboardTap.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:dismissKeyboardTap];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return FWAProfileSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == FWAProfileSectionMeasurements) {
        return self.birthDatePickerExpanded ? 4 : 3;
    }
    return FWADeveloperRowFixedCount + self.appState.providerNames.count;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == FWAProfileSectionMeasurements ? @"Measurements" : @"Developer";
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == FWAProfileSectionDeveloper) {
        return @"Endpoint is compiled in from .env — `make ios` is what refreshes it, not an Xcode build. Fault injection below is for the demo, not a product feature: each toggle simulates that provider failing on the next fetch.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == FWAProfileSectionMeasurements) {
        return [self measurementCellForTableView:tableView atRow:indexPath.row];
    }
    if (indexPath.row < FWADeveloperRowFixedCount) {
        return [self connectionCellForTableView:tableView atRow:indexPath.row];
    }
    return [self faultCellForTableView:tableView
                               atIndex:indexPath.row - FWADeveloperRowFixedCount];
}

/// Read-only endpoint rows. Deliberately shows host and transport and NOT the
/// bearer token: this screen is reachable in any DEBUG build, and a token on
/// screen is a token in a screenshot.
- (UITableViewCell *)connectionCellForTableView:(UITableView *)tableView atRow:(NSInteger)row {
    static NSString *const kID = @"FWAConnectionCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                      reuseIdentifier:kID];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
    cell.detailTextLabel.minimumScaleFactor = 0.7;

    if (row == FWADeveloperRowHost) {
        cell.textLabel.text = @"gRPC host";
        cell.detailTextLabel.text = [FWAServerConfig grpcHost];
    } else {
        cell.textLabel.text = @"Transport";
        cell.detailTextLabel.text = [FWAServerConfig useTLS] ? @"TLS" : @"plaintext";
    }
    return cell;
}

- (UITableViewCell *)measurementCellForTableView:(UITableView *)tableView atRow:(NSInteger)row {
    switch (row) {
        case FWAMeasurementsRowHeight: {
            FWAMeasurementFieldCell *cell = [self dequeueFieldCell:tableView];
            cell.textLabel.text = @"Height (cm)";
            cell.textField.text = [NSString stringWithFormat:@"%.0f", self.appState.heightCm];
            cell.textField.tag = FWAMeasurementsRowHeight;
            cell.textField.delegate = self;
            [cell.textField removeTarget:self action:NULL forControlEvents:UIControlEventEditingChanged];
            [cell.textField addTarget:self action:@selector(didEditMeasurementField:) forControlEvents:UIControlEventEditingChanged];
            return cell;
        }
        case FWAMeasurementsRowWeight: {
            FWAMeasurementFieldCell *cell = [self dequeueFieldCell:tableView];
            cell.textLabel.text = @"Weight (kg)";
            cell.textField.text = [NSString stringWithFormat:@"%.1f", self.appState.weightKg];
            cell.textField.tag = FWAMeasurementsRowWeight;
            cell.textField.delegate = self;
            [cell.textField removeTarget:self action:NULL forControlEvents:UIControlEventEditingChanged];
            [cell.textField addTarget:self action:@selector(didEditMeasurementField:) forControlEvents:UIControlEventEditingChanged];
            return cell;
        }
        case FWAMeasurementsRowBirthDate: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kBirthDateCellID];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kBirthDateCellID];
            }
            cell.textLabel.text = @"Birth date";
            NSDate *birthDate = self.appState.birthDate;
            cell.detailTextLabel.text = birthDate != nil ? [self.dateFormatter stringFromDate:birthDate] : @"Not set";
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;

            if (birthDate != nil) {
                UIButton *clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
                [clearButton setTitle:@"Clear" forState:UIControlStateNormal];
                [clearButton sizeToFit];
                [clearButton addTarget:self action:@selector(didTapClearBirthDate) forControlEvents:UIControlEventTouchUpInside];
                cell.accessoryView = clearButton;
            } else {
                cell.accessoryView = nil;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            return cell;
        }
        case FWAMeasurementsRowBirthDatePicker:
        default: {
            FWADatePickerCell *cell = (FWADatePickerCell *)[tableView dequeueReusableCellWithIdentifier:kDatePickerCellID];
            if (!cell) {
                cell = [[FWADatePickerCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kDatePickerCellID];
            }
            cell.datePicker.date = self.appState.birthDate ?: [self fallbackBirthDateForEmptyPicker];
            [cell.datePicker removeTarget:self action:NULL forControlEvents:UIControlEventValueChanged];
            [cell.datePicker addTarget:self action:@selector(didChangeBirthDatePicker:) forControlEvents:UIControlEventValueChanged];
            return cell;
        }
    }
}

- (FWAMeasurementFieldCell *)dequeueFieldCell:(UITableView *)tableView {
    FWAMeasurementFieldCell *cell = (FWAMeasurementFieldCell *)[tableView dequeueReusableCellWithIdentifier:kFieldCellID];
    if (!cell) {
        cell = [[FWAMeasurementFieldCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kFieldCellID];
    }
    return cell;
}

- (UITableViewCell *)faultCellForTableView:(UITableView *)tableView atIndex:(NSInteger)index {
    FWAFaultCell *cell = (FWAFaultCell *)[tableView dequeueReusableCellWithIdentifier:kFaultCellID];
    if (!cell) {
        cell = [[FWAFaultCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kFaultCellID];
    }

    NSString *providerName = self.appState.providerNames[index];
    cell.nameLabel.text = providerName;
    cell.faultSwitch.on = [self.appState faultEnabledAtIndex:index];
    cell.faultSwitch.tag = index;
    [cell.faultSwitch removeTarget:self action:NULL forControlEvents:UIControlEventValueChanged];
    [cell.faultSwitch addTarget:self action:@selector(didToggleFaultSwitch:) forControlEvents:UIControlEventValueChanged];

    NSString *mode = [self.appState faultModeAtIndex:index];
    cell.modeControl.selectedSegmentIndex = [self segmentIndexForMode:mode];
    cell.modeControl.tag = index;
    cell.modeControl.enabled = cell.faultSwitch.isOn;
    [cell.modeControl removeTarget:self action:NULL forControlEvents:UIControlEventValueChanged];
    [cell.modeControl addTarget:self action:@selector(didChangeFaultMode:) forControlEvents:UIControlEventValueChanged];

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == FWAProfileSectionMeasurements && indexPath.row == FWAMeasurementsRowBirthDate) {
        [self toggleBirthDatePickerExpanded];
    }
}

- (void)toggleBirthDatePickerExpanded {
    self.birthDatePickerExpanded = !self.birthDatePickerExpanded;
    NSIndexPath *pickerPath = [NSIndexPath indexPathForRow:FWAMeasurementsRowBirthDatePicker
                                                    inSection:FWAProfileSectionMeasurements];
    if (self.birthDatePickerExpanded) {
        [self.tableView insertRowsAtIndexPaths:@[pickerPath] withRowAnimation:UITableViewRowAnimationFade];
    } else {
        [self.tableView deleteRowsAtIndexPaths:@[pickerPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

#pragma mark - Actions

- (void)didEditMeasurementField:(UITextField *)textField {
    double value = [textField.text doubleValue];
    if (textField.tag == FWAMeasurementsRowHeight) {
        self.appState.heightCm = value;
    } else if (textField.tag == FWAMeasurementsRowWeight) {
        self.appState.weightKg = value;
    }
}

- (void)didTapClearBirthDate {
    self.appState.birthDate = nil;
    if (self.birthDatePickerExpanded) {
        self.birthDatePickerExpanded = NO;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:FWAProfileSectionMeasurements]
                        withRowAnimation:UITableViewRowAnimationFade];
    } else {
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:FWAMeasurementsRowBirthDate
                                                                      inSection:FWAProfileSectionMeasurements]]
                                withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)didChangeBirthDatePicker:(UIDatePicker *)picker {
    self.appState.birthDate = picker.date;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:FWAMeasurementsRowBirthDate
                                                                  inSection:FWAProfileSectionMeasurements]]
                            withRowAnimation:UITableViewRowAnimationNone];
}

- (void)didToggleFaultSwitch:(UISwitch *)sender {
    [self.appState setFaultEnabled:sender.isOn atIndex:sender.tag];
    // sender.tag is a PROVIDER index; the section now has fixed rows above
    // the fault rows, so it must be offset to reach the right row.
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:sender.tag + FWADeveloperRowFixedCount
                                                                  inSection:FWAProfileSectionDeveloper]]
                            withRowAnimation:UITableViewRowAnimationNone];
}

- (void)didChangeFaultMode:(UISegmentedControl *)sender {
    [self.appState setFaultMode:[self modeForSegmentIndex:sender.selectedSegmentIndex] atIndex:sender.tag];
}

// Only reached when the picker row is expanded from a "Not set" birth date
// (the user tapped the row to set one from scratch) — this ONLY positions
// the wheel somewhere plausible so picking a date on stage is one gesture
// instead of thirty years of scrolling. It does not write anything: the
// field still reads "Not set" until the user actually turns the wheel (see
// -didChangeBirthDatePicker:, the only place appState.birthDate is
// assigned from the picker) or taps Clear, which must still return it to
// "Not set" exactly as before.
- (NSDate *)fallbackBirthDateForEmptyPicker {
    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.year = 1983;
    components.month = 5;
    components.day = 29;
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    return [calendar dateFromComponents:components] ?: [NSDate date];
}

- (NSInteger)segmentIndexForMode:(NSString *)mode {
    if ([mode isEqualToString:FWAFaultModeTimeout]) return 1;
    if ([mode isEqualToString:FWAFaultModeMalformed]) return 2;
    return 0;
}

- (NSString *)modeForSegmentIndex:(NSInteger)index {
    switch (index) {
        case 1: return FWAFaultModeTimeout;
        case 2: return FWAFaultModeMalformed;
        default: return FWAFaultModeError;
    }
}

#if DEBUG
- (void)debug_expandBirthDatePicker {
    if (!self.birthDatePickerExpanded) {
        [self toggleBirthDatePickerExpanded];
    }
}
#endif

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (string.length == 0) {
        return YES; // always allow deletes
    }
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789."];
    for (NSUInteger i = 0; i < string.length; i++) {
        if (![allowed characterIsMember:[string characterAtIndex:i]]) {
            return NO;
        }
    }
    return YES;
}

@end
