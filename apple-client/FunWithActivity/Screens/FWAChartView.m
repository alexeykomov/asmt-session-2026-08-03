//
//  FWAChartView.m
//  FunWithActivity
//

#import "FWAChartView.h"

#import "FWAChartGeometry.h"
#import "Recommendations.pbobjc.h"

/// Series key -> colour asset name. The keys are the wire's stable handles
/// (see recommendations.proto's Series.key); the values are colour sets in
/// Assets.xcassets. This table is the iOS half of a palette the web client
/// holds as CSS custom properties and Android as colors.xml entries — the
/// three must agree, and docs/mobile/parity-matrix.md carries the row that
/// says so.
static NSDictionary<NSString *, NSString *> *FWAChartColorAssetNames(void) {
    static NSDictionary *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @{
            @"steps": @"ChartSteps",
            @"deep": @"ChartSleepDeep",
            @"light": @"ChartSleepLight",
            @"rem": @"ChartSleepREM",
            @"awake": @"ChartSleepAwake",
            @"light_activity": @"ChartActivityLight",
            @"moderate": @"ChartActivityModerate",
            @"vigorous": @"ChartActivityVigorous",
        };
    });
    return names;
}

UIColor *FWAChartColorForSeriesKey(NSString *key) {
    NSString *assetName = FWAChartColorAssetNames()[key ?: @""];
    UIColor *color = assetName ? [UIColor colorNamed:assetName] : nil;
    if (color) return color;
    // Unknown key, or an asset that failed to load. Either way, draw
    // something visible rather than nothing.
    return [UIColor colorNamed:@"ChartUnknown"] ?: [UIColor systemGrayColor];
}

#pragma mark - Layout constants

// Drawn in points against the view's own bounds rather than a fixed
// coordinate space: unlike the web's SVG viewBox, there is no automatic
// scaling here, so the geometry is computed from whatever size layout gives.
static const CGFloat kPadTop = 12;
static const CGFloat kPadRight = 8;
static const CGFloat kPadBottom = 24;
static const CGFloat kPadLeft = 44;
static const NSInteger kGridlineCount = 4;

@implementation FWAChartView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        self.layer.cornerRadius = 10;
        self.clipsToBounds = YES;
    }
    return self;
}

- (void)setChart:(Chart *)chart {
    _chart = chart;
    [self setNeedsDisplay];
}

// Redrawn on a trait change so the asset catalogue's dark-mode variants
// actually take effect — colorNamed: resolves against the trait collection
// at draw time, and without this the view keeps its light-mode pixels.
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) {
        [self setNeedsDisplay];
    }
}

/// Draws centred text where a chart has nothing to show. An empty chart and
/// a failed request mean different things; this is only ever the former.
- (void)drawNoDataInRect:(CGRect)rect {
    NSDictionary *attrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:13],
        NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
    };
    NSString *text = @"No data";
    CGSize size = [text sizeWithAttributes:attrs];
    [text drawAtPoint:CGPointMake(CGRectGetMidX(rect) - size.width / 2,
                                  CGRectGetMidY(rect) - size.height / 2)
       withAttributes:attrs];
}

@end

#pragma mark - Bar

@implementation FWABarChartView

- (void)drawRect:(CGRect)rect {
    Chart *chart = self.chart;
    if (chart.seriesArray_Count == 0 || chart.categoriesArray_Count == 0) {
        [self drawNoDataInRect:rect];
        return;
    }

    CGFloat plotWidth = CGRectGetWidth(rect) - kPadLeft - kPadRight;
    CGFloat plotHeight = CGRectGetHeight(rect) - kPadTop - kPadBottom;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    NSMutableArray<NSNumber *> *all = [NSMutableArray array];
    for (Series *s in chart.seriesArray) {
        for (NSUInteger i = 0; i < s.valuesArray_Count; i++) {
            [all addObject:@([s.valuesArray valueAtIndex:i])];
        }
    }
    double axisMax = FWAChartAxisMax(all);

    CGContextRef ctx = UIGraphicsGetCurrentContext();

    // Gridlines and axis labels first, so bars paint over them.
    NSDictionary *labelAttrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:10],
        NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
    };
    CGContextSetStrokeColorWithColor(ctx, [UIColor separatorColor].CGColor);
    CGContextSetLineWidth(ctx, 1.0 / UIScreen.mainScreen.scale);
    for (NSInteger i = 0; i <= kGridlineCount; i++) {
        CGFloat y = kPadTop + plotHeight - (plotHeight * i / kGridlineCount);
        CGContextMoveToPoint(ctx, kPadLeft, y);
        CGContextAddLineToPoint(ctx, kPadLeft + plotWidth, y);
        CGContextStrokePath(ctx);

        double value = axisMax * i / kGridlineCount;
        NSString *text = value >= 1000
            ? [NSString stringWithFormat:@"%.0fk", value / 1000]
            : [NSString stringWithFormat:@"%.0f", value];
        CGSize size = [text sizeWithAttributes:labelAttrs];
        [text drawAtPoint:CGPointMake(kPadLeft - size.width - 6, y - size.height / 2)
           withAttributes:labelAttrs];
    }

    NSInteger categoryCount = (NSInteger)chart.categoriesArray_Count;
    NSInteger seriesCount = (NSInteger)chart.seriesArray_Count;
    double slotWidth = plotWidth / MAX(categoryCount, 1);
    double groupPadding = MIN(slotWidth * 0.18, 8);

    for (NSInteger c = 0; c < categoryCount; c++) {
        for (NSInteger s = 0; s < seriesCount; s++) {
            Series *series = chart.seriesArray[s];
            if ((NSUInteger)c >= series.valuesArray_Count) continue;

            double value = [series.valuesArray valueAtIndex:(NSUInteger)c];
            FWAChartBarSlot slot = FWAChartGroupedBarSlot(
                c, s, seriesCount, slotWidth, groupPadding);
            double height = FWAChartBarHeight(value, axisMax, plotHeight);

            CGRect bar = CGRectMake(kPadLeft + slot.x,
                                    kPadTop + plotHeight - height,
                                    MAX(slot.width - 1, 1),
                                    height);
            CGContextSetFillColorWithColor(
                ctx, FWAChartColorForSeriesKey(series.key).CGColor);
            CGContextFillRect(ctx, bar);
        }

        NSString *category = chart.categoriesArray[c];
        CGSize size = [category sizeWithAttributes:labelAttrs];
        [category drawAtPoint:CGPointMake(
                        kPadLeft + c * slotWidth + slotWidth / 2 - size.width / 2,
                        CGRectGetHeight(rect) - kPadBottom + 6)
               withAttributes:labelAttrs];
    }
}

@end

#pragma mark - Pie

@implementation FWAPieChartView

- (void)drawRect:(CGRect)rect {
    Chart *chart = self.chart;
    if (chart.seriesArray_Count == 0) {
        [self drawNoDataInRect:rect];
        return;
    }

    NSMutableArray<NSNumber *> *values = [NSMutableArray array];
    for (Series *s in chart.seriesArray) {
        [values addObject:@(s.valuesArray_Count > 0
                            ? [s.valuesArray valueAtIndex:0] : 0)];
    }

    NSArray<NSNumber *> *angles = FWAChartPieAngles(values);
    if (angles.count == 0) {
        [self drawNoDataInRect:rect];
        return;
    }

    CGPoint center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
    CGFloat radius = MIN(CGRectGetWidth(rect), CGRectGetHeight(rect)) / 2 - 12;
    if (radius <= 0) return;

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    double start = 0;

    for (NSUInteger i = 0; i < angles.count; i++) {
        double sweep = angles[i].doubleValue;
        UIColor *color = FWAChartColorForSeriesKey(chart.seriesArray[i].key);
        CGContextSetFillColorWithColor(ctx, color.CGColor);

        // A single slice covering the whole circle cannot be expressed as an
        // arc — its start and end coincide, so the path collapses to nothing.
        if (sweep >= 359.999) {
            CGContextAddArc(ctx, center.x, center.y, radius, 0, 2 * M_PI, 0);
            CGContextFillPath(ctx);
            break;
        }

        // CoreGraphics measures anticlockwise from three o'clock; the -90
        // rotation to twelve o'clock lives in FWAChartPointOnCircle, so the
        // same conversion is applied here rather than reinvented.
        CGFloat startRadians = (start - 90) * M_PI / 180;
        CGFloat endRadians = (start + sweep - 90) * M_PI / 180;

        CGContextMoveToPoint(ctx, center.x, center.y);
        CGContextAddArc(ctx, center.x, center.y, radius,
                        startRadians, endRadians, 0);
        CGContextClosePath(ctx);
        CGContextFillPath(ctx);

        // Hairline separator in the background colour, matching the web's
        // stroke on each slice.
        CGContextSetStrokeColorWithColor(
            ctx, [UIColor secondarySystemGroupedBackgroundColor].CGColor);
        CGContextSetLineWidth(ctx, 2);
        CGContextMoveToPoint(ctx, center.x, center.y);
        CGPoint edge = FWAChartPointOnCircle(center, radius, start);
        CGContextAddLineToPoint(ctx, edge.x, edge.y);
        CGContextStrokePath(ctx);

        start += sweep;
    }
}

@end
