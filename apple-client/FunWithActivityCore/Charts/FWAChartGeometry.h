//
//  FWAChartGeometry.h
//  FunWithActivityCore
//
//  Pure chart arithmetic, deliberately separated from anything that draws.
//
//  A wrong chart still looks like a chart. A bar scaled by the wrong divisor,
//  or a pie whose slices quietly overlap, renders without an error and reads
//  as entirely plausible — unlike a blank screen, nothing about it announces
//  the failure. The only defence is to compute the geometry somewhere it can
//  be asserted exactly, which is why these functions take numbers and return
//  numbers and know nothing about CoreGraphics contexts or views.
//
//  Mirrors funwithactivity.charts.geometry (web) and ChartGeometry (Android)
//  function for function, so the three platforms cannot disagree about where
//  a bar ends. The parity row in docs/mobile/parity-matrix.md is what keeps
//  that honest.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Upper bound of the value axis.
///
/// Rounded up to a "nice" number so the axis reads 10,000 rather than 9,412,
/// and never zero: an all-zero series is a real case (a rest day) and must
/// still produce a usable divisor rather than a division by zero that renders
/// every bar as NaN.
///
/// @return Strictly positive.
double FWAChartAxisMax(NSArray<NSNumber *> *values);

/// Height in points of a bar for `value` in a plot area `plotHeight` tall.
///
/// Linear in value — a bar for twice the value is exactly twice as tall.
/// That is the property the tests pin, because breaking it misleads while
/// looking completely normal. Clamped to [0, plotHeight]; returns 0 rather
/// than NaN when axisMax is not positive.
double FWAChartBarHeight(double value, double axisMax, double plotHeight);

/// Sweep angles in degrees for a pie, one per value, in input order.
///
/// Always totals exactly 360: the last slice takes the remainder rather than
/// its own rounded share, because a pie that leaves a hairline gap — or
/// overlaps itself by a fraction of a degree — is visibly wrong and cannot be
/// fixed by rounding differently.
///
/// Empty or all-zero input returns an empty array rather than a full circle
/// of nothing; the caller renders its "no data" state instead. Negative
/// values are ignored rather than sweeping backwards.
NSArray<NSNumber *> *FWAChartPieAngles(NSArray<NSNumber *> *values);

/// A point on a circle, for pie slice edges.
///
/// Angles are measured clockwise from twelve o'clock, which is where every
/// reader expects a pie to start. CoreGraphics measures anticlockwise from
/// three o'clock, so the conversion happens here, once, rather than in each
/// caller — getting it wrong rotates every pie by 90° while still producing a
/// perfectly plausible-looking chart.
CGPoint FWAChartPointOnCircle(CGPoint center, double radius, double degrees);

/// Left offset and width for one bar in a grouped bar chart.
///
/// Bars within a group sit flush against each other and the group is centred
/// in its category slot, so the gap a reader sees between groups is real
/// whitespace rather than a coincidence of rounding.
typedef struct {
    double x;
    double width;
} FWAChartBarSlot;

FWAChartBarSlot FWAChartGroupedBarSlot(NSInteger categoryIndex,
                                       NSInteger seriesIndex,
                                       NSInteger seriesCount,
                                       double slotWidth,
                                       double groupPadding);

NS_ASSUME_NONNULL_END
