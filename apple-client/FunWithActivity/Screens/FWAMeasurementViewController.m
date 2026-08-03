//
//  FWAMeasurementViewController.m
//  FunWithActivity
//

#import "FWAMeasurementViewController.h"
#import "FWAGRPCClient.h"
#import "FWAHealthKitService.h"
#import "FWAResultsViewController.h"
#import "Recommendations.pbobjc.h"

typedef NS_ENUM(NSInteger, FWAButtonStyle) {
    FWAButtonStylePrimary,
    FWAButtonStyleSecondary,
};

@interface FWAMeasurementViewController () <UITextFieldDelegate>

@property (nonatomic, strong, readonly) FWAGRPCClient *grpcClient;
@property (nonatomic, strong, readonly, nullable) FWAHealthKitService *healthKitService;

@property (nonatomic, strong) UITextField *heightField;
@property (nonatomic, strong) UITextField *weightField;
@property (nonatomic, strong) UISwitch *birthDateSwitch;
@property (nonatomic, strong) UIDatePicker *birthDatePicker;
@property (nonatomic, strong) UIButton *healthButton;
@property (nonatomic, strong) UIButton *submitButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *errorLabel;

@end

@implementation FWAMeasurementViewController

- (instancetype)initWithGRPCClient:(FWAGRPCClient *)grpcClient
                    healthKitService:(nullable FWAHealthKitService *)healthKitService {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _grpcClient = grpcClient;
        _healthKitService = healthKitService;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Measurements";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self buildUI];
#if DEBUG
    [self setUpAutoSubmitDemoHookIfRequested];
#endif
}

#if DEBUG
// DEBUG-only launch-argument hook for headless verification, matching the
// house convention of test-only launch overrides (see e.g. CyberFight's
// `-CYF_GRPC_HOST`). Pass `-FWA_AUTOSUBMIT_DEMO 1` to drive a real submit
// through the full gRPC round trip without a human tapping — useful for
// smoke-testing a build against a locally running app-server. Never
// compiled into Release.
//
// By default this exercises the GDPR-skip path (birth date withheld,
// service2-stub skipped, 3 recommendations). Add
// `-FWA_AUTOSUBMIT_DEMO_BIRTHDATE 1` alongside it to also supply a birth
// date, exercising the full-response path instead (both providers, 6
// recommendations interleaved by score) — this is the primary demo beat
// and needs the same headless verification.
- (void)setUpAutoSubmitDemoHookIfRequested {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"FWA_AUTOSUBMIT_DEMO"]) {
        return;
    }
    self.heightField.text = @"175";
    self.weightField.text = @"70";
    BOOL includeBirthDate = [[NSUserDefaults standardUserDefaults] boolForKey:@"FWA_AUTOSUBMIT_DEMO_BIRTHDATE"];
    self.birthDateSwitch.on = includeBirthDate;
    [self didToggleBirthDateSwitch];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self didTapSubmit];
    });
}
#endif

#pragma mark - UI construction

- (void)buildUI {
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scrollView];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 20;
    stack.alignment = UIStackViewAlignmentFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scrollView.topAnchor constant:24],
        [stack.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor constant:-40],
    ]];

    UILabel *intro = [self labelWithText:@"Enter your measurements for personalized recommendations. Birth date is optional."
                                     bold:NO];
    intro.numberOfLines = 0;
    [stack addArrangedSubview:intro];

    if (self.healthKitService != nil) {
        self.healthButton = [self buttonWithTitle:@"Prefill from Health" style:FWAButtonStyleSecondary];
        [self.healthButton addTarget:self action:@selector(didTapHealthButton) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:self.healthButton];
    }

    [stack addArrangedSubview:[self labelWithText:@"Height (cm)" bold:YES]];
    self.heightField = [self numericFieldWithPlaceholder:@"e.g. 175"];
    [stack addArrangedSubview:self.heightField];

    [stack addArrangedSubview:[self labelWithText:@"Weight (kg)" bold:YES]];
    self.weightField = [self numericFieldWithPlaceholder:@"e.g. 70"];
    [stack addArrangedSubview:self.weightField];

    UIStackView *birthRow = [[UIStackView alloc] init];
    birthRow.axis = UILayoutConstraintAxisHorizontal;
    birthRow.spacing = 8;
    UILabel *birthLabel = [self labelWithText:@"Birth date (optional)" bold:YES];
    self.birthDateSwitch = [[UISwitch alloc] init];
    self.birthDateSwitch.on = NO;
    [self.birthDateSwitch addTarget:self action:@selector(didToggleBirthDateSwitch) forControlEvents:UIControlEventValueChanged];
    [birthRow addArrangedSubview:birthLabel];
    UIView *spacer = [[UIView alloc] init];
    [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [birthRow addArrangedSubview:spacer];
    [birthRow addArrangedSubview:self.birthDateSwitch];
    [stack addArrangedSubview:birthRow];

    UILabel *birthHint = [self labelWithText:@"One provider needs this; the rest work without it. Leave off to decline sharing it."
                                         bold:NO];
    birthHint.numberOfLines = 0;
    birthHint.font = [UIFont systemFontOfSize:13];
    birthHint.textColor = [UIColor secondaryLabelColor];
    [stack addArrangedSubview:birthHint];

    self.birthDatePicker = [[UIDatePicker alloc] init];
    self.birthDatePicker.datePickerMode = UIDatePickerModeDate;
    if (@available(iOS 13.4, *)) {
        self.birthDatePicker.preferredDatePickerStyle = UIDatePickerStyleWheels;
    }
    self.birthDatePicker.maximumDate = [NSDate date];
    self.birthDatePicker.date = [self defaultBirthDate];
    self.birthDatePicker.enabled = self.birthDateSwitch.isOn;
    self.birthDatePicker.alpha = self.birthDateSwitch.isOn ? 1.0 : 0.4;
    // `hidden`, not just `enabled`/`alpha`, on a UIStackView arranged
    // subview: the stack view collapses a hidden arranged subview and
    // reclaims its space, whereas enabled+alpha alone leaves it taking
    // its full height as an inert, ghosted control. Seeded from the
    // switch's initial (off) state here so the toggle-off ghost never
    // renders even for a single frame; didToggleBirthDateSwitch keeps it
    // in sync (animated) afterwards.
    self.birthDatePicker.hidden = !self.birthDateSwitch.isOn;
    [stack addArrangedSubview:self.birthDatePicker];

    self.errorLabel = [self labelWithText:@"" bold:NO];
    self.errorLabel.textColor = [UIColor systemRedColor];
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;
    [stack addArrangedSubview:self.errorLabel];

    self.submitButton = [self buttonWithTitle:@"Get Recommendations" style:FWAButtonStylePrimary];
    [self.submitButton addTarget:self action:@selector(didTapSubmit) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.submitButton];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    [stack addArrangedSubview:self.spinner];
}

- (NSDate *)defaultBirthDate {
    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.year = 1990;
    components.month = 1;
    components.day = 1;
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    return [calendar dateFromComponents:components] ?: [NSDate date];
}

- (UIButton *)buttonWithTitle:(NSString *)title style:(FWAButtonStyle)style {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    button.layer.cornerRadius = 10;
    // NOTE: -contentEdgeInsets is deprecated in favor of UIButtonConfiguration,
    // but mixing configuration-based sizing with the plain setTitleColor:/
    // backgroundColor calls below is its own source of surprises. Deprecated-
    // but-simple wins for this demo-scale screen.
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 16, 12, 16);
    if (style == FWAButtonStylePrimary) {
        button.backgroundColor = [UIColor systemBlueColor];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    } else {
        button.backgroundColor = [UIColor secondarySystemBackgroundColor];
        [button setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    }
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return button;
}

- (UILabel *)labelWithText:(NSString *)text bold:(BOOL)bold {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = bold ? [UIFont boldSystemFontOfSize:16] : [UIFont systemFontOfSize:15];
    return label;
}

- (UITextField *)numericFieldWithPlaceholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.keyboardType = UIKeyboardTypeDecimalPad;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.delegate = self;
    [field.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return field;
}

#pragma mark - Actions

- (void)didToggleBirthDateSwitch {
    BOOL isOn = self.birthDateSwitch.isOn;
    self.birthDatePicker.enabled = isOn;

    // Animate the expand/collapse rather than jumping: toggling `hidden`
    // on a UIStackView arranged subview inside an animation block, paired
    // with -layoutIfNeeded, is the supported way to make the stack's
    // resulting reflow (the picker's row growing/shrinking, everything
    // below it sliding up/down) read as intentional instead of a jump cut.
    // The hint label above stays visible in both states unconditionally —
    // it is what explains *why* the field is optional, in both states.
    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:0.25
                     animations:^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.birthDatePicker.alpha = isOn ? 1.0 : 0.4;
        strongSelf.birthDatePicker.hidden = !isOn;
        [strongSelf.view layoutIfNeeded];
    }];
}

- (void)didTapHealthButton {
    __weak typeof(self) weakSelf = self;
    [self.healthKitService requestAuthorizationWithCompletion:^(BOOL granted, NSError * _Nullable error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        // Whether or not `granted` is YES, HealthKit doesn't tell us
        // per-type grant status — just try the read. Any value it can't
        // supply comes back as "unavailable" and that field is left for
        // manual entry, per FWAHealthKitService's contract.
        [strongSelf.healthKitService fetchMeasurementsWithCompletion:^(FWAHealthKitMeasurements * _Nonnull measurements) {
            [strongSelf applyHealthKitMeasurements:measurements];
        }];
    }];
}

- (void)applyHealthKitMeasurements:(FWAHealthKitMeasurements *)measurements {
    if (measurements.heightCm > 0) {
        self.heightField.text = [NSString stringWithFormat:@"%.0f", measurements.heightCm];
    }
    if (measurements.weightKg > 0) {
        self.weightField.text = [NSString stringWithFormat:@"%.1f", measurements.weightKg];
    }
    if (measurements.birthDate != nil) {
        self.birthDateSwitch.on = YES;
        self.birthDatePicker.date = measurements.birthDate;
        [self didToggleBirthDateSwitch];
    }
    if (measurements.heightCm <= 0 && measurements.weightKg <= 0 && measurements.birthDate == nil) {
        self.errorLabel.hidden = NO;
        self.errorLabel.textColor = [UIColor secondaryLabelColor];
        self.errorLabel.text = @"No Health data found or access wasn't granted — please enter your measurements manually.";
    }
}

- (void)didTapSubmit {
    [self.view endEditing:YES];
    self.errorLabel.hidden = YES;

    double heightCm = [self.heightField.text doubleValue];
    double weightKg = [self.weightField.text doubleValue];

    if (heightCm <= 0 || weightKg <= 0) {
        self.errorLabel.hidden = NO;
        self.errorLabel.textColor = [UIColor systemRedColor];
        self.errorLabel.text = @"Height and weight are required and must be greater than zero.";
        return;
    }

    int64_t birthDateUnix = 0;
    if (self.birthDateSwitch.isOn) {
        birthDateUnix = (int64_t)[self.birthDatePicker.date timeIntervalSince1970];
    }

    self.submitButton.enabled = NO;
    [self.spinner startAnimating];

    __weak typeof(self) weakSelf = self;
    [self.grpcClient getRecommendationsWithHeightCm:heightCm
                                             weightKg:weightKg
                                        birthDateUnix:birthDateUnix
                                               faults:nil
                                           completion:^(GetRecommendationsResponse * _Nullable response, NSError * _Nullable error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.spinner stopAnimating];
        strongSelf.submitButton.enabled = YES;

        if (error || !response) {
            strongSelf.errorLabel.hidden = NO;
            strongSelf.errorLabel.textColor = [UIColor systemRedColor];
            strongSelf.errorLabel.text = [NSString stringWithFormat:@"Request failed: %@",
                                           error.localizedDescription ?: @"unknown error"];
            return;
        }

        FWAResultsViewController *resultsVC = [[FWAResultsViewController alloc] initWithResponse:response];
        [strongSelf.navigationController pushViewController:resultsVC animated:YES];
    }];
}

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
