//
//  FWAAddSourceViewController.m
//  FunWithActivity
//

#import "FWAAddSourceViewController.h"

typedef NS_ENUM(NSInteger, FWASourceType) {
    FWASourceTypeREST = 0,
    FWASourceTypeGRPC,
};

@interface FWAAddSourceViewController ()

@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *baseURLField;
@property (nonatomic, strong) UITextField *authTokenField;
@property (nonatomic, strong) UISegmentedControl *typeControl;
@property (nonatomic, strong) UILabel *errorLabel;

@end

@implementation FWAAddSourceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Add Source";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self buildUI];
}

- (void)buildUI {
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scrollView];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
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

    UILabel *intro = [self labelWithText:@"A new source needs an adapter — Go code implementing the Provider interface — before it can be called. This form validates and explains that; it does not add a working source." bold:NO];
    intro.numberOfLines = 0;
    intro.textColor = [UIColor secondaryLabelColor];
    [stack addArrangedSubview:intro];

    [stack addArrangedSubview:[self labelWithText:@"Name" bold:YES]];
    self.nameField = [self fieldWithPlaceholder:@"e.g. service3"];
    [stack addArrangedSubview:self.nameField];

    [stack addArrangedSubview:[self labelWithText:@"Base URL" bold:YES]];
    self.baseURLField = [self fieldWithPlaceholder:@"https://example.com/services/service3"];
    self.baseURLField.keyboardType = UIKeyboardTypeURL;
    self.baseURLField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [stack addArrangedSubview:self.baseURLField];

    [stack addArrangedSubview:[self labelWithText:@"Auth token" bold:YES]];
    self.authTokenField = [self fieldWithPlaceholder:@"optional"];
    self.authTokenField.secureTextEntry = YES;
    self.authTokenField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [stack addArrangedSubview:self.authTokenField];
    UILabel *tokenHint = [self labelWithText:@"Never stored — a credential for a source that can't be called yet is pure liability." bold:NO];
    tokenHint.numberOfLines = 0;
    tokenHint.font = [UIFont systemFontOfSize:13];
    tokenHint.textColor = [UIColor secondaryLabelColor];
    [stack addArrangedSubview:tokenHint];

    [stack addArrangedSubview:[self labelWithText:@"Type" bold:YES]];
    self.typeControl = [[UISegmentedControl alloc] initWithItems:@[@"REST", @"gRPC"]];
    self.typeControl.selectedSegmentIndex = FWASourceTypeREST;
    [stack addArrangedSubview:self.typeControl];

    self.errorLabel = [self labelWithText:@"" bold:NO];
    self.errorLabel.textColor = [UIColor systemRedColor];
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;
    [stack addArrangedSubview:self.errorLabel];

    UIButton *submitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [submitButton setTitle:@"Add Source" forState:UIControlStateNormal];
    submitButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    submitButton.layer.cornerRadius = 10;
    submitButton.contentEdgeInsets = UIEdgeInsetsMake(12, 16, 12, 16);
    submitButton.backgroundColor = [UIColor systemBlueColor];
    [submitButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [submitButton.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [submitButton addTarget:self action:@selector(didTapSubmit) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:submitButton];
}

- (UILabel *)labelWithText:(NSString *)text bold:(BOOL)bold {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = bold ? [UIFont boldSystemFontOfSize:16] : [UIFont systemFontOfSize:15];
    return label;
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.borderStyle = UITextBorderStyleRoundedRect;
    [field.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return field;
}

- (void)didTapSubmit {
    [self.view endEditing:YES];
    self.errorLabel.hidden = YES;

    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *baseURL = [self.baseURLField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (name.length == 0) {
        [self showValidationError:@"Name is required."];
        return;
    }
    if (baseURL.length == 0) {
        [self showValidationError:@"Base URL is required."];
        return;
    }
    NSURL *url = [NSURL URLWithString:baseURL];
    if (url == nil || url.scheme == nil || url.host == nil) {
        [self showValidationError:@"Base URL must be a valid absolute URL, e.g. https://example.com/services/name."];
        return;
    }

    // The auth token field is read only long enough to be discarded here —
    // it is never assigned to an ivar, a model object, or anything that
    // outlives this method, matching "do not store the auth token."
    NSString *type = self.typeControl.selectedSegmentIndex == FWASourceTypeGRPC ? @"gRPC" : @"REST";

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

- (void)showValidationError:(NSString *)message {
    self.errorLabel.text = message;
    self.errorLabel.hidden = NO;
}

#if DEBUG
- (void)debug_fillValidFormAndSubmit {
    self.nameField.text = @"service3";
    self.baseURLField.text = @"https://example.com/services/service3";
    self.authTokenField.text = @"demo-token-not-stored";
    self.typeControl.selectedSegmentIndex = FWASourceTypeGRPC;
    [self didTapSubmit];
}
#endif

@end
