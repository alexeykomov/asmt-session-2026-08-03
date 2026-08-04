package com.funwithactivity.app.features.charts;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * The invariants here are the ones a screenshot cannot catch. A bar scaled by
 * the wrong divisor and a pie rotated by 90° both render as perfectly
 * ordinary charts.
 */
public class ChartGeometryTest {

    private static final double EPS = 1e-9;

    @Test
    public void axisMaxRoundsUpToAReadableTick() {
        assertTrue(ChartGeometry.axisMax(Arrays.asList(9412.0)) >= 9412);
        assertEquals(10000, ChartGeometry.axisMax(Arrays.asList(9412.0)), EPS);
        assertEquals(50, ChartGeometry.axisMax(Arrays.asList(42.0)), EPS);
        assertEquals(0.5, ChartGeometry.axisMax(Arrays.asList(0.4)), EPS);
    }

    /**
     * An all-zero series is a real case — a rest day, or a metric with
     * nothing to report. Returning 0 would make every bar height a division
     * by zero.
     */
    @Test
    public void axisMaxIsNeverZero() {
        assertTrue(ChartGeometry.axisMax(Collections.emptyList()) > 0);
        assertTrue(ChartGeometry.axisMax(Arrays.asList(0.0, 0.0, 0.0)) > 0);
        assertTrue(ChartGeometry.axisMax(Arrays.asList(-5.0)) > 0);
    }

    @Test
    public void barHeightIsLinearInValue() {
        assertEquals(100, ChartGeometry.barHeight(50, 100, 200), EPS);
        assertEquals(50, ChartGeometry.barHeight(25, 100, 200), EPS);
        assertEquals(200, ChartGeometry.barHeight(100, 100, 200), EPS);
        assertEquals(2 * ChartGeometry.barHeight(30, 100, 200),
            ChartGeometry.barHeight(60, 100, 200), EPS);
    }

    @Test
    public void barHeightClampsRatherThanOverflowing() {
        assertEquals(200, ChartGeometry.barHeight(150, 100, 200), EPS);
    }

    @Test
    public void barHeightIsZeroForNonPositiveInput() {
        assertEquals(0, ChartGeometry.barHeight(0, 100, 200), EPS);
        assertEquals(0, ChartGeometry.barHeight(-10, 100, 200), EPS);
        assertEquals(0, ChartGeometry.barHeight(10, 0, 200), EPS);
    }

    /**
     * A pie that leaves a hairline gap, or overlaps itself by a fraction of a
     * degree, is visibly wrong and cannot be fixed by rounding differently.
     */
    @Test
    public void pieAnglesAlwaysTotal360() {
        List<List<Double>> cases = Arrays.asList(
            Arrays.asList(25.0, 25.0, 25.0, 25.0),
            Arrays.asList(22.4, 51.3, 18.1, 8.2),
            Arrays.asList(1.0, 1.0, 1.0),
            Arrays.asList(99.0, 1.0),
            Arrays.asList(7.0));
        for (List<Double> values : cases) {
            double total = 0;
            for (Double a : ChartGeometry.pieAngles(values)) total += a;
            assertEquals("values " + values, 360, total, EPS);
        }
    }

    @Test
    public void pieAnglesAreProportional() {
        List<Double> angles = ChartGeometry.pieAngles(Arrays.asList(25.0, 75.0));
        assertEquals(90, angles.get(0), EPS);
        assertEquals(270, angles.get(1), EPS);
    }

    @Test
    public void pieAnglesReturnNothingToDrawForEmptyInput() {
        assertTrue(ChartGeometry.pieAngles(Collections.emptyList()).isEmpty());
        assertTrue(ChartGeometry.pieAngles(Arrays.asList(0.0, 0.0)).isEmpty());
    }

    @Test
    public void pieAnglesIgnoreNegativeValues() {
        List<Double> angles = ChartGeometry.pieAngles(Arrays.asList(50.0, -10.0, 50.0));
        double total = 0;
        for (Double a : angles) {
            assertTrue("negative sweep " + a, a >= 0);
            total += a;
        }
        assertEquals(360, total, EPS);
    }

    /**
     * Zero degrees must be twelve o'clock. Canvas#drawArc measures from three
     * o'clock, and getting this wrong rotates every pie by 90° while still
     * producing an entirely plausible chart.
     */
    @Test
    public void pointOnCircleMeasuresClockwiseFromTwelve() {
        float[] top = ChartGeometry.pointOnCircle(100, 100, 50, 0);
        assertEquals(100, top[0], 1e-4);
        assertEquals(50, top[1], 1e-4);

        float[] right = ChartGeometry.pointOnCircle(100, 100, 50, 90);
        assertEquals(150, right[0], 1e-4);
        assertEquals(100, right[1], 1e-4);
    }

    @Test
    public void groupedBarSlotsArePackedAndDoNotOverlap() {
        double slotWidth = 90;
        double padding = 10;
        ChartGeometry.BarSlot a = ChartGeometry.groupedBarSlot(0, 0, 3, slotWidth, padding);
        ChartGeometry.BarSlot b = ChartGeometry.groupedBarSlot(0, 1, 3, slotWidth, padding);
        ChartGeometry.BarSlot c = ChartGeometry.groupedBarSlot(0, 2, 3, slotWidth, padding);

        assertEquals(padding, a.x, EPS);
        assertEquals(a.x + a.width, b.x, EPS);
        assertEquals(b.x + b.width, c.x, EPS);
        assertTrue(c.x + c.width <= slotWidth - padding + EPS);
    }

    @Test
    public void groupedBarSlotOffsetsEachCategoryByAWholeSlot() {
        ChartGeometry.BarSlot first = ChartGeometry.groupedBarSlot(0, 0, 2, 80, 8);
        ChartGeometry.BarSlot second = ChartGeometry.groupedBarSlot(1, 0, 2, 80, 8);
        assertEquals(80, second.x - first.x, EPS);
    }

    @Test
    public void groupedBarSlotHandlesASingleSeries() {
        ChartGeometry.BarSlot only = ChartGeometry.groupedBarSlot(0, 0, 1, 60, 6);
        assertTrue(only.width > 0);
    }
}
