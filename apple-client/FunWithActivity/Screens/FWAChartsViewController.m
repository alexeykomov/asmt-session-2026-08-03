//
//  FWAChartsViewController.m
//  FunWithActivity
//

#import "FWAChartsViewController.h"

#import "FWAAppState.h"
#import "FWAChartView.h"
#import "FWAGRPCClient.h"
#import "Recommendations.pbobjc.h"

/// Height of one chart card. Fixed rather than intrinsic: these views draw
/// into their bounds and have no natural size, so a stack view would collapse
/// them to zero without an explicit constraint.
static const CGFloat kChartHeight = 200;

@interface FWAChartsViewController ()
@property (nonatomic, strong, readonly) FWAGRPCClient *grpcClient;
@property (nonatomic, strong, readonly) FWAAppState *appState;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
/// Last response, kept so returning to the tab can repaint without refetching.
@property (nonatomic, strong, nullable) NSArray<Chart *> *charts;
@property (nonatomic, assign) BOOL hasFetchedOnce;
@end

@implementation FWAChartsViewController

- (instancetype)initWithGRPCClient:(FWAGRPCClient *)grpcClient
                           appState:(FWAAppState *)appState {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _grpcClient = grpcClient;
        _appState = appState;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Trends";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self
                             action:@selector(handleRefresh)
                   forControlEvents:UIControlEventValueChanged];
    self.scrollView.refreshControl = self.refreshControl;

    self.stack = [[UIStackView alloc] init];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 20;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.stack];

    UILayoutGuide *content = self.scrollView.contentLayoutGuide;
    UILayoutGuide *frame = self.scrollView.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:16],
        [self.stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
        [self.stack.leadingAnchor constraintEqualToAnchor:frame.leadingAnchor constant:16],
        [self.stack.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor constant:-16],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Charts are seeded from the measurements, so the same guard the
    // Recommendations tab applies holds here: without height and weight the
    // server has nothing to seed from, and a red failure banner would be
    // describing an unfinished profile as a system fault.
    if (self.appState.heightCm <= 0 || self.appState.weightKg <= 0) {
        [self renderMessage:@"Add your height and weight in Profile to see charts."];
        return;
    }

    if (!self.hasFetchedOnce || self.appState.isDirty) {
        [self fetchCharts];
    } else {
        // Skipping the fetch must not mean showing an empty screen — the
        // whole reason `charts` is retained.
        [self renderCharts];
    }
}

- (void)handleRefresh {
    [self fetchCharts];
}

- (void)fetchCharts {
    if (!self.refreshControl.isRefreshing) {
        [self.refreshControl beginRefreshing];
    }

    int64_t birthDateUnix = self.appState.birthDate
        ? (int64_t)[self.appState.birthDate timeIntervalSince1970] : 0;

    __weak typeof(self) weakSelf = self;
    [self.grpcClient getHealthChartsWithHeightCm:self.appState.heightCm
                                         weightKg:self.appState.weightKg
                                    birthDateUnix:birthDateUnix
                                       completion:^(HealthChartsResponse *_Nullable response,
                                                    NSError *_Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        [self.refreshControl endRefreshing];
        self.hasFetchedOnce = YES;
        // Deliberately does not clear appState's dirty flag — see this
        // class's header doc. The Recommendations tab owns that flag.

        if (error || response == nil) {
            // A transport failure must not look like an empty chart set:
            // the two mean entirely different things to whoever is looking.
            [self renderMessage:@"Unable to load charts — pull to refresh to try again."];
            return;
        }
        self.charts = [response.chartsArray copy];
        [self renderCharts];
    }];
}

- (void)renderCharts {
    [self clearStack];

    if (self.charts.count == 0) {
        [self renderMessage:@"No charts returned."];
        return;
    }

    for (Chart *chart in self.charts) {
        [self.stack addArrangedSubview:[self titleLabelWithText:chart.title]];

        FWAChartView *chartView = [self chartViewForType:chart.type];
        if (chartView == nil) {
            // Forward compatibility: a chart type this build predates keeps
            // its title and explains itself rather than blanking the screen.
            [self.stack addArrangedSubview:
                [self captionLabelWithText:@"This chart type is not supported by this app version."]];
            continue;
        }
        chartView.chart = chart;
        chartView.translatesAutoresizingMaskIntoConstraints = NO;
        [chartView.heightAnchor constraintEqualToConstant:kChartHeight].active = YES;
        [self.stack addArrangedSubview:chartView];

        if (chart.seriesArray_Count > 1) {
            [self.stack addArrangedSubview:[self legendForChart:chart]];
        }
    }
}

- (nullable FWAChartView *)chartViewForType:(ChartType)type {
    switch (type) {
        case ChartType_ChartTypeBar:
        case ChartType_ChartTypeGroupedBar:
            return [[FWABarChartView alloc] init];
        case ChartType_ChartTypePie:
            return [[FWAPieChartView alloc] init];
        default:
            return nil;
    }
}

- (UIView *)legendForChart:(Chart *)chart {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 14;
    row.alignment = UIStackViewAlignmentCenter;

    for (Series *series in chart.seriesArray) {
        UIStackView *item = [[UIStackView alloc] init];
        item.axis = UILayoutConstraintAxisHorizontal;
        item.spacing = 5;
        item.alignment = UIStackViewAlignmentCenter;

        UIView *swatch = [[UIView alloc] init];
        swatch.backgroundColor = FWAChartColorForSeriesKey(series.key);
        swatch.layer.cornerRadius = 2;
        swatch.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [swatch.widthAnchor constraintEqualToConstant:10],
            [swatch.heightAnchor constraintEqualToConstant:10],
        ]];

        UILabel *label = [[UILabel alloc] init];
        label.text = series.label;
        label.font = [UIFont systemFontOfSize:12];
        label.textColor = [UIColor secondaryLabelColor];

        [item addArrangedSubview:swatch];
        [item addArrangedSubview:label];
        [row addArrangedSubview:item];
    }

    // Trailing spacer so the items group left rather than stretching.
    [row addArrangedSubview:[[UIView alloc] init]];
    return row;
}

- (UILabel *)titleLabelWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    label.textColor = [UIColor labelColor];
    label.numberOfLines = 0;
    return label;
}

- (UILabel *)captionLabelWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont italicSystemFontOfSize:12];
    label.textColor = [UIColor secondaryLabelColor];
    label.numberOfLines = 0;
    return label;
}

- (void)renderMessage:(NSString *)message {
    [self clearStack];
    UILabel *label = [[UILabel alloc] init];
    label.text = message;
    label.font = [UIFont systemFontOfSize:14];
    label.textColor = [UIColor secondaryLabelColor];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    [self.stack addArrangedSubview:label];
}

- (void)clearStack {
    for (UIView *view in [self.stack.arrangedSubviews copy]) {
        [self.stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
}

@end
