//
//  FWAChartGeometryTests.m
//  FunWithActivityCoreTests
//
//  The invariants here are the ones a screenshot cannot catch. A bar scaled
//  by the wrong divisor and a pie rotated by 90° both render as perfectly
//  ordinary charts.
//

#import <XCTest/XCTest.h>
#import "FWAChartGeometry.h"

@interface FWAChartGeometryTests : XCTestCase
@end

@implementation FWAChartGeometryTests

#pragma mark - axisMax

- (void)testAxisMaxRoundsUpToAReadableTick {
    XCTAssertGreaterThanOrEqual(FWAChartAxisMax(@[@9412]), 9412);
    XCTAssertEqual(FWAChartAxisMax(@[@9412]), 10000);
    XCTAssertEqual(FWAChartAxisMax(@[@42]), 50);
    XCTAssertEqualWithAccuracy(FWAChartAxisMax(@[@0.4]), 0.5, 1e-9);
}

// An all-zero series is a real case — a rest day, or a metric with nothing to
// report. Returning 0 would make every bar height a division by zero.
- (void)testAxisMaxIsNeverZero {
    XCTAssertGreaterThan(FWAChartAxisMax(@[]), 0);
    XCTAssertGreaterThan(FWAChartAxisMax(@[@0, @0, @0]), 0);
    XCTAssertGreaterThan(FWAChartAxisMax(@[@(-5)]), 0);
}

#pragma mark - barHeight

- (void)testBarHeightIsLinearInValue {
    XCTAssertEqual(FWAChartBarHeight(50, 100, 200), 100);
    XCTAssertEqual(FWAChartBarHeight(25, 100, 200), 50);
    XCTAssertEqual(FWAChartBarHeight(100, 100, 200), 200);
    XCTAssertEqualWithAccuracy(FWAChartBarHeight(60, 100, 200),
                               2 * FWAChartBarHeight(30, 100, 200), 1e-9);
}

- (void)testBarHeightClampsRatherThanOverflowing {
    XCTAssertEqual(FWAChartBarHeight(150, 100, 200), 200);
}

- (void)testBarHeightIsZeroForNonPositiveInput {
    XCTAssertEqual(FWAChartBarHeight(0, 100, 200), 0);
    XCTAssertEqual(FWAChartBarHeight(-10, 100, 200), 0);
    XCTAssertEqual(FWAChartBarHeight(10, 0, 200), 0);
}

#pragma mark - pieAngles

// A pie that leaves a hairline gap, or overlaps itself by a fraction of a
// degree, is visibly wrong and cannot be fixed by rounding differently.
- (void)testPieAnglesAlwaysTotal360 {
    NSArray<NSArray<NSNumber *> *> *cases = @[
        @[@25, @25, @25, @25],
        @[@22.4, @51.3, @18.1, @8.2],
        @[@1, @1, @1],
        @[@99, @1],
        @[@7],
    ];
    for (NSArray<NSNumber *> *values in cases) {
        double total = 0;
        for (NSNumber *a in FWAChartPieAngles(values)) total += a.doubleValue;
        XCTAssertEqualWithAccuracy(total, 360, 1e-9, @"values %@", values);
    }
}

- (void)testPieAnglesAreProportional {
    NSArray<NSNumber *> *angles = FWAChartPieAngles(@[@25, @75]);
    XCTAssertEqualWithAccuracy(angles[0].doubleValue, 90, 1e-9);
    XCTAssertEqualWithAccuracy(angles[1].doubleValue, 270, 1e-9);
}

- (void)testPieAnglesReturnNothingToDrawForEmptyInput {
    XCTAssertEqual(FWAChartPieAngles(@[]).count, 0u);
    XCTAssertEqual(FWAChartPieAngles(@[@0, @0]).count, 0u);
}

- (void)testPieAnglesIgnoreNegativeValues {
    NSArray<NSNumber *> *angles = FWAChartPieAngles(@[@50, @(-10), @50]);
    double total = 0;
    for (NSNumber *a in angles) {
        XCTAssertGreaterThanOrEqual(a.doubleValue, 0);
        total += a.doubleValue;
    }
    XCTAssertEqualWithAccuracy(total, 360, 1e-9);
}

#pragma mark - pointOnCircle

// Zero degrees must be twelve o'clock. CoreGraphics measures from three
// o'clock, and getting this wrong rotates every pie by 90° while still
// producing an entirely plausible chart.
- (void)testPointOnCircleMeasuresClockwiseFromTwelve {
    CGPoint center = CGPointMake(100, 100);

    CGPoint top = FWAChartPointOnCircle(center, 50, 0);
    XCTAssertEqualWithAccuracy(top.x, 100, 1e-9);
    XCTAssertEqualWithAccuracy(top.y, 50, 1e-9);

    CGPoint right = FWAChartPointOnCircle(center, 50, 90);
    XCTAssertEqualWithAccuracy(right.x, 150, 1e-9);
    XCTAssertEqualWithAccuracy(right.y, 100, 1e-9);
}

#pragma mark - groupedBarSlot

- (void)testGroupedBarSlotsArePackedAndDoNotOverlap {
    double slotWidth = 90;
    double padding = 10;
    FWAChartBarSlot a = FWAChartGroupedBarSlot(0, 0, 3, slotWidth, padding);
    FWAChartBarSlot b = FWAChartGroupedBarSlot(0, 1, 3, slotWidth, padding);
    FWAChartBarSlot c = FWAChartGroupedBarSlot(0, 2, 3, slotWidth, padding);

    XCTAssertEqualWithAccuracy(a.x, padding, 1e-9);
    XCTAssertEqualWithAccuracy(b.x, a.x + a.width, 1e-9);
    XCTAssertEqualWithAccuracy(c.x, b.x + b.width, 1e-9);
    XCTAssertLessThanOrEqual(c.x + c.width, slotWidth - padding + 1e-9);
}

- (void)testGroupedBarSlotOffsetsEachCategoryByAWholeSlot {
    FWAChartBarSlot first = FWAChartGroupedBarSlot(0, 0, 2, 80, 8);
    FWAChartBarSlot second = FWAChartGroupedBarSlot(1, 0, 2, 80, 8);
    XCTAssertEqualWithAccuracy(second.x - first.x, 80, 1e-9);
}

- (void)testGroupedBarSlotHandlesASingleSeries {
    FWAChartBarSlot only = FWAChartGroupedBarSlot(0, 0, 1, 60, 6);
    XCTAssertGreaterThan(only.width, 0);
}

@end
