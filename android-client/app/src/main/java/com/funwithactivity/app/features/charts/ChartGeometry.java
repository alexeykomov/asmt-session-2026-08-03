package com.funwithactivity.app.features.charts;

import java.util.ArrayList;
import java.util.List;

/**
 * Pure chart arithmetic, deliberately separated from anything that draws.
 *
 * <p>A wrong chart still looks like a chart. A bar scaled by the wrong
 * divisor, or a pie whose slices quietly overlap, renders without an error
 * and reads as entirely plausible — unlike a blank screen, nothing about it
 * announces the failure. The only defence is to compute the geometry
 * somewhere it can be asserted exactly, which is why every method here takes
 * numbers and returns numbers and knows nothing about Canvas or View.
 *
 * <p>Mirrors funwithactivity.charts.geometry (web) and FWAChartGeometry (iOS)
 * method for method, so the three platforms cannot disagree about where a bar
 * ends. The parity row in docs/mobile/parity-matrix.md keeps that honest.
 */
public final class ChartGeometry {

    private ChartGeometry() {}

    /**
     * Upper bound of the value axis.
     *
     * <p>Rounded up to a "nice" number so the axis reads 10,000 rather than
     * 9,412, and never zero: an all-zero series is a real case (a rest day)
     * and must still produce a usable divisor rather than a division by zero
     * that renders every bar as NaN.
     *
     * @return strictly positive
     */
    public static double axisMax(List<Double> values) {
        double max = 0;
        for (Double v : values) {
            if (v != null && v > max) max = v;
        }
        if (max <= 0) return 1;

        // Round up to 1, 2 or 5 times a power of ten — the standard tick
        // steps that produce readable axis labels at any magnitude.
        double magnitude = Math.pow(10, Math.floor(Math.log10(max)));
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

    /**
     * Height in pixels of a bar for {@code value} in a plot area
     * {@code plotHeight} tall.
     *
     * <p>Linear in value — a bar for twice the value is exactly twice as
     * tall. That is the property the tests pin, because breaking it misleads
     * while looking completely normal. Clamped to [0, plotHeight]; returns 0
     * rather than NaN when axisMax is not positive.
     */
    public static double barHeight(double value, double axisMax, double plotHeight) {
        if (!(axisMax > 0)) return 0;
        double h = (value / axisMax) * plotHeight;
        if (Double.isNaN(h) || Double.isInfinite(h) || h < 0) return 0;
        return Math.min(h, plotHeight);
    }

    /**
     * Sweep angles in degrees for a pie, one per value, in input order.
     *
     * <p>Always totals exactly 360: the last slice takes the remainder rather
     * than its own rounded share, because a pie that leaves a hairline gap —
     * or overlaps itself by a fraction of a degree — is visibly wrong and
     * cannot be fixed by rounding differently.
     *
     * <p>Empty or all-zero input returns an empty list rather than a full
     * circle of nothing; the caller renders its "no data" state instead.
     * Negative values are ignored rather than sweeping backwards.
     */
    public static List<Double> pieAngles(List<Double> values) {
        double total = 0;
        for (Double v : values) {
            if (v != null && v > 0) total += v;
        }
        List<Double> angles = new ArrayList<>();
        if (total <= 0) return angles;

        double assigned = 0;
        for (int i = 0; i < values.size(); i++) {
            Double raw = values.get(i);
            double v = (raw == null || raw < 0) ? 0 : raw;
            double sweep;
            if (i == values.size() - 1) {
                sweep = 360 - assigned;
            } else {
                sweep = (v / total) * 360;
                assigned += sweep;
            }
            angles.add(sweep);
        }
        return angles;
    }

    /**
     * A point on a circle, for pie slice edges, as {@code {x, y}}.
     *
     * <p>Angles are measured clockwise from twelve o'clock, which is where
     * every reader expects a pie to start. Canvas#drawArc measures from three
     * o'clock, so the conversion happens here, once, rather than in each
     * caller — getting it wrong rotates every pie by 90° while still
     * producing a perfectly plausible-looking chart.
     */
    public static float[] pointOnCircle(float cx, float cy, double radius, double degrees) {
        double radians = Math.toRadians(degrees - 90);
        return new float[] {
            (float) (cx + radius * Math.cos(radians)),
            (float) (cy + radius * Math.sin(radians)),
        };
    }

    /** Left offset and width of one bar in a grouped bar chart. */
    public static final class BarSlot {
        public final double x;
        public final double width;

        BarSlot(double x, double width) {
            this.x = x;
            this.width = width;
        }
    }

    /**
     * Bars within a group sit flush against each other and the group is
     * centred in its category slot, so the gap a reader sees between groups
     * is real whitespace rather than a coincidence of rounding.
     */
    public static BarSlot groupedBarSlot(int categoryIndex, int seriesIndex,
                                         int seriesCount, double slotWidth,
                                         double groupPadding) {
        double usable = Math.max(slotWidth - groupPadding * 2, 1);
        double width = usable / Math.max(seriesCount, 1);
        return new BarSlot(
            categoryIndex * slotWidth + groupPadding + seriesIndex * width,
            width);
    }
}
