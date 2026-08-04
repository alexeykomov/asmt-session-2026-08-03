package com.funwithactivity.app.features.charts;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.util.AttributeSet;
import android.view.View;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.funwithactivity.app.R;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import funwithactivity.recommendations.v1.Recommendations.Chart;
import funwithactivity.recommendations.v1.Recommendations.Series;

/**
 * Canvas chart renderers. No charting library — the customer's brief rules
 * out third-party UI components, and the deck commits to platform primitives.
 *
 * <p>Each view takes a decoded {@link Chart} and draws it. None of them
 * fetches, caches, or knows anything about navigation; all the arithmetic
 * lives in {@link ChartGeometry}, which is unit-tested without a view at all.
 * That split exists because a wrong chart still looks like a chart — a bar
 * scaled by the wrong divisor renders without an error and reads as
 * plausible.
 *
 * <p>Colour comes from named entries in colors.xml, keyed by the series key
 * the server sends rather than its display label, so rewording a label cannot
 * recolour a chart. Nothing about colour crosses the wire.
 */
public abstract class ChartView extends View {

    /**
     * Series key -> colour resource. The keys are the wire's stable handles
     * (see Series.key in recommendations.proto). This is the Android half of
     * a palette the web client holds as CSS custom properties and iOS as
     * colour sets; the three must agree, and docs/mobile/parity-matrix.md
     * carries the row that says so.
     */
    private static final Map<String, Integer> COLOR_BY_KEY = new HashMap<>();

    static {
        COLOR_BY_KEY.put("steps", R.color.colorChartSteps);
        COLOR_BY_KEY.put("deep", R.color.colorChartSleepDeep);
        COLOR_BY_KEY.put("light", R.color.colorChartSleepLight);
        COLOR_BY_KEY.put("rem", R.color.colorChartSleepRem);
        COLOR_BY_KEY.put("awake", R.color.colorChartSleepAwake);
        COLOR_BY_KEY.put("light_activity", R.color.colorChartActivityLight);
        COLOR_BY_KEY.put("moderate", R.color.colorChartActivityModerate);
        COLOR_BY_KEY.put("vigorous", R.color.colorChartActivityVigorous);
    }

    /**
     * Falls back to a visible neutral for a key this build does not know: a
     * future server adding a series must not render as invisible or crash.
     */
    public static int colorForSeriesKey(Context context, @Nullable String key) {
        Integer res = key == null ? null : COLOR_BY_KEY.get(key);
        return context.getColor(res == null ? R.color.colorChartUnknown : res);
    }

    protected static final int GRIDLINE_COUNT = 4;

    protected final Paint fillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    protected final Paint linePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    protected final Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    @Nullable private Chart chart;

    public ChartView(Context context) {
        this(context, null);
    }

    public ChartView(Context context, @Nullable AttributeSet attrs) {
        super(context, attrs);
        fillPaint.setStyle(Paint.Style.FILL);
        linePaint.setStyle(Paint.Style.STROKE);
        linePaint.setStrokeWidth(1f);
        linePaint.setColor(context.getColor(R.color.colorDivider));
        textPaint.setColor(context.getColor(R.color.colorTextMuted));
        textPaint.setTextSize(spToPx(11));
    }

    public void setChart(@Nullable Chart chart) {
        this.chart = chart;
        invalidate();
    }

    @Nullable
    protected Chart getChart() {
        return chart;
    }

    protected float dpToPx(float dp) {
        return dp * getResources().getDisplayMetrics().density;
    }

    protected float spToPx(float sp) {
        return sp * getResources().getDisplayMetrics().scaledDensity;
    }

    /**
     * Draws centred text where a chart has nothing to show. An empty chart
     * and a failed request mean different things; this is only ever the
     * former — the fragment owns the failure message.
     */
    protected void drawNoData(@NonNull Canvas canvas) {
        String text = "No data";
        float width = textPaint.measureText(text);
        canvas.drawText(text, (getWidth() - width) / 2f, getHeight() / 2f, textPaint);
    }

    /**
     * Bar and grouped bar share a renderer: a single-series bar chart is a
     * grouped chart with one bar per group, so splitting them would duplicate
     * the axis, scaling and label logic for no behavioural difference.
     */
    public static class BarChartView extends ChartView {

        public BarChartView(Context context) {
            super(context);
        }

        public BarChartView(Context context, @Nullable AttributeSet attrs) {
            super(context, attrs);
        }

        @Override
        protected void onDraw(@NonNull Canvas canvas) {
            super.onDraw(canvas);
            Chart chart = getChart();
            if (chart == null || chart.getSeriesCount() == 0
                    || chart.getCategoriesCount() == 0) {
                drawNoData(canvas);
                return;
            }

            float padLeft = dpToPx(38);
            float padRight = dpToPx(8);
            float padTop = dpToPx(10);
            float padBottom = dpToPx(20);

            float plotWidth = getWidth() - padLeft - padRight;
            float plotHeight = getHeight() - padTop - padBottom;
            if (plotWidth <= 0 || plotHeight <= 0) return;

            List<Double> all = new ArrayList<>();
            for (Series s : chart.getSeriesList()) {
                all.addAll(s.getValuesList());
            }
            double axisMax = ChartGeometry.axisMax(all);

            // Gridlines and axis labels first, so bars paint over them.
            for (int i = 0; i <= GRIDLINE_COUNT; i++) {
                float y = padTop + plotHeight - (plotHeight * i / GRIDLINE_COUNT);
                canvas.drawLine(padLeft, y, padLeft + plotWidth, y, linePaint);

                double value = axisMax * i / GRIDLINE_COUNT;
                String text = value >= 1000
                    ? String.format("%.0fk", value / 1000)
                    : String.format("%.0f", value);
                float width = textPaint.measureText(text);
                canvas.drawText(text, padLeft - width - dpToPx(4),
                    y + textPaint.getTextSize() / 3f, textPaint);
            }

            int categoryCount = chart.getCategoriesCount();
            int seriesCount = chart.getSeriesCount();
            double slotWidth = plotWidth / Math.max(categoryCount, 1);
            double groupPadding = Math.min(slotWidth * 0.18, dpToPx(6));

            for (int c = 0; c < categoryCount; c++) {
                for (int s = 0; s < seriesCount; s++) {
                    Series series = chart.getSeries(s);
                    if (c >= series.getValuesCount()) continue;

                    ChartGeometry.BarSlot slot = ChartGeometry.groupedBarSlot(
                        c, s, seriesCount, slotWidth, groupPadding);
                    double height = ChartGeometry.barHeight(
                        series.getValues(c), axisMax, plotHeight);

                    fillPaint.setColor(colorForSeriesKey(getContext(), series.getKey()));
                    canvas.drawRect(
                        (float) (padLeft + slot.x),
                        (float) (padTop + plotHeight - height),
                        (float) (padLeft + slot.x + Math.max(slot.width - 1, 1)),
                        padTop + plotHeight,
                        fillPaint);
                }

                String category = chart.getCategories(c);
                float width = textPaint.measureText(category);
                canvas.drawText(category,
                    (float) (padLeft + c * slotWidth + slotWidth / 2 - width / 2),
                    getHeight() - dpToPx(4), textPaint);
            }
        }
    }

    /** Pie. One value per series, by wire contract. */
    public static class PieChartView extends ChartView {

        private final Paint separatorPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

        public PieChartView(Context context) {
            this(context, null);
        }

        public PieChartView(Context context, @Nullable AttributeSet attrs) {
            super(context, attrs);
            separatorPaint.setStyle(Paint.Style.STROKE);
            separatorPaint.setStrokeWidth(dpToPx(2));
            separatorPaint.setColor(context.getColor(R.color.colorSurface));
        }

        @Override
        protected void onDraw(@NonNull Canvas canvas) {
            super.onDraw(canvas);
            Chart chart = getChart();
            if (chart == null || chart.getSeriesCount() == 0) {
                drawNoData(canvas);
                return;
            }

            List<Double> values = new ArrayList<>();
            for (Series s : chart.getSeriesList()) {
                values.add(s.getValuesCount() > 0 ? s.getValues(0) : 0.0);
            }
            List<Double> angles = ChartGeometry.pieAngles(values);
            if (angles.isEmpty()) {
                drawNoData(canvas);
                return;
            }

            float cx = getWidth() / 2f;
            float cy = getHeight() / 2f;
            float radius = Math.min(getWidth(), getHeight()) / 2f - dpToPx(10);
            if (radius <= 0) return;

            RectF oval = new RectF(cx - radius, cy - radius, cx + radius, cy + radius);
            float start = 0;

            for (int i = 0; i < angles.size(); i++) {
                float sweep = angles.get(i).floatValue();
                fillPaint.setColor(
                    colorForSeriesKey(getContext(), chart.getSeries(i).getKey()));

                // Canvas measures from three o'clock; -90 puts zero degrees
                // at twelve, matching ChartGeometry.pointOnCircle and both
                // other platforms.
                canvas.drawArc(oval, start - 90, sweep, true, fillPaint);

                float[] edge = ChartGeometry.pointOnCircle(cx, cy, radius, start);
                canvas.drawLine(cx, cy, edge[0], edge[1], separatorPaint);

                start += sweep;
            }
        }
    }
}
