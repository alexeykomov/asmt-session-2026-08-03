package com.funwithactivity.app.features.charts;

import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;

import com.funwithactivity.app.FunWithActivityApplication;
import com.funwithactivity.app.R;
import com.funwithactivity.app.core.network.GrpcClient;
import com.funwithactivity.app.core.state.AppState;
import com.funwithactivity.app.features.app.TabVisibilityAware;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import funwithactivity.recommendations.v1.Recommendations.Chart;
import funwithactivity.recommendations.v1.Recommendations.ChartType;
import funwithactivity.recommendations.v1.Recommendations.GetHealthChartsRequest;
import funwithactivity.recommendations.v1.Recommendations.HealthChartsResponse;
import funwithactivity.recommendations.v1.Recommendations.Measurements;
import funwithactivity.recommendations.v1.Recommendations.Series;

/**
 * The Trends tab: a steps bar chart, a sleep-stage pie, and a grouped bar of
 * active minutes by intensity, drawn with Canvas via {@link ChartView}.
 *
 * <p>Uses the same visit policy the Recommendations tab does — fetch on first
 * appearance, refetch on return only when the profile changed, always fetch on
 * pull-to-refresh — and repaints from the last response when the fetch is
 * skipped. That repaint is not incidental: omitting it on Recommendations
 * shipped as a real defect, where declining to fetch and losing the data
 * looked identical to the user.
 *
 * <p>Implements {@link TabVisibilityAware} for the same reason
 * RecommendationsFragment does: MainActivity switches tabs with show()/hide()
 * to preserve scroll position, which does not drive onResume().
 *
 * <p>Deliberately does NOT clear AppState's dirty flag on success. That flag
 * means "the profile changed since the last recommendations fetch", and the
 * Recommendations tab owns clearing it; consuming it here would let a visit to
 * Trends silently skip the refetch Recommendations was about to perform.
 */
public class ChartsFragment extends Fragment implements TabVisibilityAware {

    /** Height of one chart. These views draw into their bounds and have no
     *  intrinsic size, so without an explicit height they collapse to zero. */
    private static final int CHART_HEIGHT_DP = 180;

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private GrpcClient grpcClient;
    private AppState appState;
    private SwipeRefreshLayout swipeRefreshLayout;
    private LinearLayout container;

    /** Last response, kept so returning to the tab can repaint without refetching. */
    @Nullable private List<Chart> charts;
    private boolean hasFetchedOnce;

    @Override
    public void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        FunWithActivityApplication app =
            (FunWithActivityApplication) requireActivity().getApplication();
        grpcClient = app.getGrpcClient();
        appState = app.getAppState();
    }

    @Nullable
    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup parent,
                             @Nullable Bundle savedInstanceState) {
        return inflater.inflate(R.layout.fragment_charts, parent, false);
    }

    @Override
    public void onViewCreated(@NonNull View view, @Nullable Bundle savedInstanceState) {
        super.onViewCreated(view, savedInstanceState);
        swipeRefreshLayout = view.findViewById(R.id.charts_swipe_refresh);
        container = view.findViewById(R.id.charts_container);
        swipeRefreshLayout.setOnRefreshListener(this::loadCharts);
        maybeLoad();
    }

    @Override
    public void onTabShown() {
        maybeLoad();
    }

    private void maybeLoad() {
        if (getView() == null) return; // view not created yet

        // Charts are seeded from the measurements, so the same guard the
        // Recommendations tab applies holds here: without height and weight
        // the server has nothing to seed from, and an error message would be
        // describing an unfinished profile as a system fault.
        if (appState.getHeightCm() <= 0 || appState.getWeightKg() <= 0) {
            renderMessage(getString(R.string.charts_needs_measurements));
            return;
        }

        if (!hasFetchedOnce || appState.isDirty()) {
            loadCharts();
        } else {
            // Skipping the fetch must not mean showing an empty screen — the
            // whole reason `charts` is retained.
            renderCharts();
        }
    }

    private void loadCharts() {
        swipeRefreshLayout.setRefreshing(true);

        GetHealthChartsRequest request = GetHealthChartsRequest.newBuilder()
            .setMeasurements(Measurements.newBuilder()
                .setHeightCm(appState.getHeightCm())
                .setWeightKg(appState.getWeightKg())
                .setBirthDateUnix(appState.getBirthDateUnix())
                .build())
            .build();

        executor.execute(() -> {
            try {
                HealthChartsResponse response = grpcClient.getHealthCharts(request);
                mainHandler.post(() -> onResponse(response));
            } catch (Exception e) {
                mainHandler.post(this::onFailure);
            }
        });
    }

    private void onResponse(HealthChartsResponse response) {
        if (getView() == null) return;
        swipeRefreshLayout.setRefreshing(false);
        hasFetchedOnce = true;
        // Deliberately does not call appState.markClean() — see the class
        // Javadoc. The Recommendations tab owns that flag.
        charts = new ArrayList<>(response.getChartsList());
        renderCharts();
    }

    private void onFailure() {
        if (getView() == null) return;
        swipeRefreshLayout.setRefreshing(false);
        hasFetchedOnce = true;
        // A transport failure must not look like an empty chart set: the two
        // mean entirely different things to whoever is looking at the screen.
        renderMessage(getString(R.string.charts_error));
    }

    private void renderCharts() {
        container.removeAllViews();

        if (charts == null || charts.isEmpty()) {
            renderMessage(getString(R.string.charts_empty));
            return;
        }

        for (Chart chart : charts) {
            container.addView(titleView(chart.getTitle()));

            ChartView chartView = chartViewFor(chart.getType());
            if (chartView == null) {
                // Forward compatibility: a chart type this build predates keeps
                // its title and explains itself rather than blanking the screen.
                container.addView(captionView(getString(R.string.charts_unsupported_type)));
                continue;
            }
            chartView.setChart(chart);
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(CHART_HEIGHT_DP));
            params.bottomMargin = dp(4);
            chartView.setLayoutParams(params);
            chartView.setBackgroundColor(requireContext().getColor(R.color.colorSurface));
            container.addView(chartView);

            if (chart.getSeriesCount() > 1) {
                container.addView(legendFor(chart));
            }
        }
    }

    @Nullable
    private ChartView chartViewFor(ChartType type) {
        switch (type) {
            case CHART_TYPE_BAR:
            case CHART_TYPE_GROUPED_BAR:
                return new ChartView.BarChartView(requireContext());
            case CHART_TYPE_PIE:
                return new ChartView.PieChartView(requireContext());
            default:
                return null;
        }
    }

    private View legendFor(Chart chart) {
        LinearLayout row = new LinearLayout(requireContext());
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(4), 0, dp(12));

        for (Series series : chart.getSeriesList()) {
            View swatch = new View(requireContext());
            swatch.setBackgroundColor(
                ChartView.colorForSeriesKey(requireContext(), series.getKey()));
            LinearLayout.LayoutParams swatchParams =
                new LinearLayout.LayoutParams(dp(10), dp(10));
            swatchParams.rightMargin = dp(5);
            swatch.setLayoutParams(swatchParams);
            row.addView(swatch);

            TextView label = new TextView(requireContext());
            label.setText(series.getLabel());
            label.setTextSize(12);
            label.setTextColor(requireContext().getColor(R.color.colorTextMuted));
            LinearLayout.LayoutParams labelParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            labelParams.rightMargin = dp(14);
            label.setLayoutParams(labelParams);
            row.addView(label);
        }
        return row;
    }

    private TextView titleView(String text) {
        TextView view = new TextView(requireContext());
        view.setText(text);
        view.setTextSize(15);
        view.setTypeface(view.getTypeface(), android.graphics.Typeface.BOLD);
        view.setPadding(0, dp(8), 0, dp(6));
        return view;
    }

    private TextView captionView(String text) {
        TextView view = new TextView(requireContext());
        view.setText(text);
        view.setTextSize(12);
        view.setTextColor(requireContext().getColor(R.color.colorTextMuted));
        view.setPadding(0, dp(8), 0, 0);
        return view;
    }

    private void renderMessage(String message) {
        container.removeAllViews();
        TextView view = new TextView(requireContext());
        view.setText(message);
        view.setTextColor(requireContext().getColor(R.color.colorTextMuted));
        view.setGravity(Gravity.CENTER);
        view.setPadding(dp(24), dp(24), dp(24), dp(24));
        container.addView(view);
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density);
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        executor.shutdownNow();
    }
}
