//
//  FWAChartView.h
//  FunWithActivity
//
//  CoreGraphics chart renderers. No charting library — the customer's brief
//  rules out third-party UI components, and the deck commits to platform
//  primitives.
//
//  Each view takes a decoded Chart and draws it. None of them fetches,
//  caches, or knows anything about navigation; all the arithmetic lives in
//  FWAChartGeometry, which is unit-tested without a view at all. That split
//  exists because a wrong chart still looks like a chart — a bar scaled by
//  the wrong divisor renders without an error and reads as plausible.
//
//  Colour comes from named assets in Assets.xcassets, keyed by the series
//  `key` the server sends — never by its display label, so rewording a label
//  cannot recolour a chart. Nothing about colour crosses the wire, which is
//  also what gets these views dark mode for free.
//

#import <UIKit/UIKit.h>

@class Chart;

NS_ASSUME_NONNULL_BEGIN

/// Maps a series key to its colour asset. Falls back to ChartUnknown for a
/// key this build does not recognise: a future server adding a series must
/// render as a visible neutral rather than crashing or drawing invisibly.
UIColor *FWAChartColorForSeriesKey(NSString *key);

/// Common base: holds the chart and repaints when it is replaced.
@interface FWAChartView : UIView
@property (nonatomic, strong, nullable) Chart *chart;
@end

/// Bar and grouped bar. One renderer for both: a single-series bar chart is
/// a grouped chart with one bar per group, so splitting them would duplicate
/// the axis, scaling and label logic for no behavioural difference.
@interface FWABarChartView : FWAChartView
@end

/// Pie. One value per series, by wire contract.
@interface FWAPieChartView : FWAChartView
@end

NS_ASSUME_NONNULL_END
