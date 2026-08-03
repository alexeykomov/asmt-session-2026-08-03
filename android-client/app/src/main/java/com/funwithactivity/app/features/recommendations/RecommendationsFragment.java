package com.funwithactivity.app.features.recommendations;

import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.LayoutInflater;
import android.view.Menu;
import android.view.MenuInflater;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.funwithactivity.app.FunWithActivityApplication;
import com.funwithactivity.app.R;
import com.funwithactivity.app.core.network.GrpcClient;
import com.funwithactivity.app.core.state.AppState;
import com.funwithactivity.app.features.app.TabVisibilityAware;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import funwithactivity.recommendations.v1.Recommendations.GetRecommendationsRequest;
import funwithactivity.recommendations.v1.Recommendations.GetRecommendationsResponse;
import funwithactivity.recommendations.v1.Recommendations.Measurements;
import funwithactivity.recommendations.v1.Recommendations.ProviderStatus;
import funwithactivity.recommendations.v1.Recommendations.Recommendation;

/**
 * Recommendations tab: the v1.1.0 results screen's RecyclerView and banner
 * area, now populated by a background fetch instead of a form submit (1.2.0
 * design spec §5.2).
 *
 * <p>Refresh policy — the highest-value behaviour in this screen:
 * <ul>
 *   <li>Fetch once on first appearance, unconditionally.</li>
 *   <li>Refetch when the tab becomes visible again ONLY if {@link
 *       AppState#isDirty()} — i.e. Profile changed measurements or fault
 *       settings since the last fetch — then clear the flag.</li>
 *   <li>A manual refresh action in the app bar always fetches, dirty or
 *       not.</li>
 * </ul>
 * Both directions matter: refetching unconditionally on every tab switch
 * burns a call against flaky, rate-limited vendors; never refetching makes
 * the app look like it ignored a Profile edit.
 *
 * <p>The ok/skipped/error branching that decides banner severity lives in
 * {@link ProviderStatusPresentation} — not re-derived here.
 */
public class RecommendationsFragment extends Fragment implements TabVisibilityAware {

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private View progressBar;
    private TextView errorView;
    private TextView emptyView;
    private ViewGroup statusBannerContainer;
    private RecyclerView recyclerView;
    private RecommendationAdapter adapter;

    private AppState appState;
    private GrpcClient grpcClient;

    @Override
    public void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setHasOptionsMenu(true);
        FunWithActivityApplication app = (FunWithActivityApplication) requireActivity().getApplication();
        appState = app.getAppState();
        grpcClient = app.getGrpcClient();
    }

    @Nullable
    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup container,
                              @Nullable Bundle savedInstanceState) {
        return inflater.inflate(R.layout.fragment_recommendations, container, false);
    }

    @Override
    public void onViewCreated(@NonNull View view, @Nullable Bundle savedInstanceState) {
        super.onViewCreated(view, savedInstanceState);

        progressBar = view.findViewById(R.id.recs_progress);
        errorView = view.findViewById(R.id.recs_error);
        emptyView = view.findViewById(R.id.recs_empty);
        statusBannerContainer = view.findViewById(R.id.recs_status_banner_container);
        recyclerView = view.findViewById(R.id.recs_recycler_view);

        adapter = new RecommendationAdapter();
        recyclerView.setLayoutManager(new LinearLayoutManager(requireContext()));
        recyclerView.setAdapter(adapter);
    }

    @Override
    public void onCreateOptionsMenu(@NonNull Menu menu, @NonNull MenuInflater inflater) {
        inflater.inflate(R.menu.menu_recommendations, menu);
        super.onCreateOptionsMenu(menu, inflater);
    }

    @Override
    public boolean onOptionsItemSelected(@NonNull MenuItem item) {
        if (item.getItemId() == R.id.action_refresh) {
            loadRecommendations();
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    /** Called by MainActivity right after this tab is shown (see TabVisibilityAware). */
    @Override
    public void onTabShown() {
        if (getView() == null) return; // view not created yet; onViewCreated path isn't ready
        if (!appState.hasFetchedOnce() || appState.isDirty()) {
            loadRecommendations();
        }
    }

    private void loadRecommendations() {
        if (getView() == null) return;
        progressBar.setVisibility(View.VISIBLE);
        errorView.setVisibility(View.GONE);
        emptyView.setVisibility(View.GONE);

        Measurements measurements = Measurements.newBuilder()
            .setHeightCm(appState.getHeightCm())
            .setWeightKg(appState.getWeightKg())
            .setBirthDateUnix(appState.getBirthDateUnix())
            .build();

        GetRecommendationsRequest.Builder requestBuilder = GetRecommendationsRequest.newBuilder()
            .setMeasurements(measurements);
        for (Map.Entry<String, String> fault : appState.getFaults().entrySet()) {
            requestBuilder.putFaults(fault.getKey(), fault.getValue());
        }
        GetRecommendationsRequest request = requestBuilder.build();

        executor.execute(() -> {
            try {
                GetRecommendationsResponse response = grpcClient.getRecommendations(request);
                appState.setLastStatuses(response.getStatusesList());
                appState.setFetchedOnce();
                appState.markClean();
                mainHandler.post(() -> onResponse(response));
            } catch (Exception e) {
                appState.setFetchedOnce();
                mainHandler.post(() -> onFailure(e));
            }
        });
    }

    private void onResponse(GetRecommendationsResponse response) {
        if (getView() == null || !isAdded()) return;

        progressBar.setVisibility(View.GONE);
        renderStatusBanners(response.getStatusesList());

        List<Recommendation> recommendations = response.getRecommendationsList();
        // adapter.setItems() runs either way — an empty list must actually
        // clear previously-rendered cards, not just be skipped, or a
        // refetch that legitimately returns nothing (e.g. every provider
        // now skipped/degraded) leaves the previous fetch's cards on
        // screen underneath the empty-state text.
        adapter.setItems(recommendations);
        if (recommendations.isEmpty()) {
            emptyView.setVisibility(View.VISIBLE);
            recyclerView.setVisibility(View.GONE);
        } else {
            emptyView.setVisibility(View.GONE);
            recyclerView.setVisibility(View.VISIBLE);
        }
    }

    private void onFailure(Exception e) {
        if (getView() == null || !isAdded()) return;

        progressBar.setVisibility(View.GONE);
        errorView.setVisibility(View.VISIBLE);
        errorView.setText(getString(R.string.request_failed, e.getMessage()));
    }

    private void renderStatusBanners(List<ProviderStatus> statuses) {
        statusBannerContainer.setVisibility(View.VISIBLE);
        statusBannerContainer.removeAllViews();

        LayoutInflater inflater = LayoutInflater.from(requireContext());
        for (ProviderStatus status : statuses) {
            ProviderStatusPresentation presentation = ProviderStatusPresentation.forStatus(status);
            switch (presentation.getSeverity()) {
                case INFO:
                    addBanner(inflater, getString(R.string.status_skipped_format,
                        presentation.getProviderName(), presentation.getError()),
                        R.color.colorStatusSkippedBg, R.color.colorStatusSkippedText);
                    break;
                case DEGRADED:
                    addBanner(inflater, getString(R.string.status_error_format,
                        presentation.getProviderName(), presentation.getError()),
                        R.color.colorStatusErrorBg, R.color.colorStatusErrorText);
                    break;
                case OK:
                default:
                    addBanner(inflater, getString(R.string.status_ok_format,
                        presentation.getProviderName(), presentation.getCount(), presentation.getLatencyMs()),
                        android.R.color.transparent, R.color.colorStatusOk);
                    break;
            }
        }
    }

    private void addBanner(LayoutInflater inflater, String text, int backgroundColorRes, int textColorRes) {
        View banner = inflater.inflate(R.layout.item_status_banner, statusBannerContainer, false);
        TextView textView = banner.findViewById(R.id.status_banner_text);
        textView.setText(text);
        textView.setBackgroundColor(getResources().getColor(backgroundColorRes));
        textView.setTextColor(getResources().getColor(textColorRes));
        statusBannerContainer.addView(banner);
    }

    @Override
    public void onDestroy() {
        executor.shutdownNow();
        super.onDestroy();
    }
}
