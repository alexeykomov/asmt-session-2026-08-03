//
//  FWAChartGeometry.m
//  FunWithActivityCore
//

#import "FWAChartGeometry.h"

#import <math.h>

double FWAChartAxisMax(NSArray<NSNumber *> *values) {
    double max = 0;
    for (NSNumber *n in values) {
        double v = n.doubleValue;
        if (v > max) max = v;
    }
    if (max <= 0) return 1;

    // Round up to 1, 2 or 5 times a power of ten — the standard tick steps
    // that produce readable axis labels at any magnitude.
    double magnitude = pow(10, floor(log10(max)));
    double normalised = max / magnitude;
    double step;
    if (normalised <= 1) {
        step = 1;
    } else if (normalised <= 2) {
        step = 2;
    } else if (normalised <= 5) {
        step = 5;
    } else {
        step = 10;
    }
    return step * magnitude;
}

double FWAChartBarHeight(double value, double axisMax, double plotHeight) {
    if (!(axisMax > 0)) return 0;
    double h = (value / axisMax) * plotHeight;
    if (!isfinite(h) || h < 0) return 0;
    return fmin(h, plotHeight);
}

NSArray<NSNumber *> *FWAChartPieAngles(NSArray<NSNumber *> *values) {
    double total = 0;
    for (NSNumber *n in values) {
        double v = n.doubleValue;
        if (v > 0) total += v;
    }
    if (total <= 0) return @[];

    NSMutableArray<NSNumber *> *angles = [NSMutableArray arrayWithCapacity:values.count];
    double assigned = 0;
    for (NSUInteger i = 0; i < values.count; i++) {
        double v = values[i].doubleValue;
        if (v < 0) v = 0;
        double sweep;
        if (i == values.count - 1) {
            // The last slice takes the remainder so rounding cannot leave a
            // gap or an overlap.
            sweep = 360 - assigned;
        } else {
            sweep = (v / total) * 360;
            assigned += sweep;
        }
        [angles addObject:@(sweep)];
    }
    return angles;
}

CGPoint FWAChartPointOnCircle(CGPoint center, double radius, double degrees) {
    double radians = (degrees - 90) * M_PI / 180;
    return CGPointMake(center.x + radius * cos(radians),
                       center.y + radius * sin(radians));
}

FWAChartBarSlot FWAChartGroupedBarSlot(NSInteger categoryIndex,
                                       NSInteger seriesIndex,
                                       NSInteger seriesCount,
                                       double slotWidth,
                                       double groupPadding) {
    double usable = fmax(slotWidth - groupPadding * 2, 1);
    double width = usable / (double)MAX(seriesCount, 1);
    FWAChartBarSlot slot;
    slot.x = categoryIndex * slotWidth + groupPadding + seriesIndex * width;
    slot.width = width;
    return slot;
}
