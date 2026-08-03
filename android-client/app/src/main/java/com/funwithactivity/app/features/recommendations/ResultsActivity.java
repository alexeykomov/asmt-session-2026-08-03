package com.funwithactivity.app.features.recommendations;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.funwithactivity.app.FunWithActivityApplication;
import com.funwithactivity.app.R;
import com.funwithactivity.app.core.network.GrpcClient;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import funwithactivity.recommendations.v1.Recommendations.GetRecommendationsRequest;
import funwithactivity.recommendations.v1.Recommendations.GetRecommendationsResponse;
import funwithactivity.recommendations.v1.Recommendations.Measurements;
import funwithactivity.recommendations.v1.Recommendations.ProviderStatus;

/**
 * Results screen: fires the GetRecommendations RPC on a background thread
 * and marshals the response back to the UI thread. Renders the flat
 * recommendation list plus a status/banner area for each provider's outcome.
 *
 * The ok/skipped/error branching that decides banner severity lives in
 * {@link ProviderStatusPresentation} (branch order matters — see its
 * Javadoc and {@link ProviderStatusPresentationTest} — do not reorder it
 * here or there).
 */
public class ResultsActivity extends AppCompatActivity {

    public static final String EXTRA_HEIGHT_CM = "height_cm";
    public static final String EXTRA_WEIGHT_KG = "weight_kg";
    public static final String EXTRA_BIRTH_DATE_UNIX = "birth_date_unix";

    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    private View progressBar;
    private TextView errorView;
    private TextView emptyView;
    private View statusBannerContainer;
    private RecyclerView recyclerView;
    private RecommendationAdapter adapter;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_results);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setTitle(R.string.results_title);
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
        }

        progressBar = findViewById(R.id.results_progress);
        errorView = findViewById(R.id.results_error);
        emptyView = findViewById(R.id.results_empty);
        statusBannerContainer = findViewById(R.id.status_banner_container);
        recyclerView = findViewById(R.id.results_recycler_view);

        adapter = new RecommendationAdapter();
        recyclerView.setLayoutManager(new LinearLayoutManager(this));
        recyclerView.setAdapter(adapter);

        double heightCm = getIntent().getDoubleExtra(EXTRA_HEIGHT_CM, 0);
        double weightKg = getIntent().getDoubleExtra(EXTRA_WEIGHT_KG, 0);
        long birthDateUnix = getIntent().getLongExtra(EXTRA_BIRTH_DATE_UNIX, 0);

        loadRecommendations(heightCm, weightKg, birthDateUnix);
    }

    private void loadRecommendations(double heightCm, double weightKg, long birthDateUnix) {
        progressBar.setVisibility(View.VISIBLE);

        GrpcClient grpcClient = ((FunWithActivityApplication) getApplication()).getGrpcClient();

        Measurements measurements = Measurements.newBuilder()
            .setHeightCm(heightCm)
            .setWeightKg(weightKg)
            .setBirthDateUnix(birthDateUnix) // 0 means "not supplied"
            .build();

        GetRecommendationsRequest request = GetRecommendationsRequest.newBuilder()
            .setMeasurements(measurements)
            // Demo-only fault injection map — unused by this client; the
            // server treats an absent key as "no fault" per provider.
            .build();

        executor.execute(() -> {
            try {
                GetRecommendationsResponse response = grpcClient.getRecommendations(request);
                runOnUiThread(() -> onResponse(response));
            } catch (Exception e) {
                runOnUiThread(() -> onFailure(e));
            }
        });
    }

    private void onResponse(GetRecommendationsResponse response) {
        if (isFinishing() || isDestroyed()) return;

        progressBar.setVisibility(View.GONE);
        renderStatusBanners(response.getStatusesList());

        List<funwithactivity.recommendations.v1.Recommendations.Recommendation> recommendations =
            response.getRecommendationsList();
        if (recommendations.isEmpty()) {
            emptyView.setVisibility(View.VISIBLE);
        } else {
            emptyView.setVisibility(View.GONE);
            adapter.setItems(recommendations);
        }
    }

    private void onFailure(Exception e) {
        if (isFinishing() || isDestroyed()) return;

        progressBar.setVisibility(View.GONE);
        errorView.setVisibility(View.VISIBLE);
        errorView.setText(getString(R.string.request_failed, e.getMessage()));
    }

    private void renderStatusBanners(List<ProviderStatus> statuses) {
        statusBannerContainer.setVisibility(View.VISIBLE);
        ((android.view.ViewGroup) statusBannerContainer).removeAllViews();

        LayoutInflater inflater = LayoutInflater.from(this);
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
        View banner = inflater.inflate(R.layout.item_status_banner, (android.view.ViewGroup) statusBannerContainer, false);
        TextView textView = banner.findViewById(R.id.status_banner_text);
        textView.setText(text);
        textView.setBackgroundColor(getResources().getColor(backgroundColorRes));
        textView.setTextColor(getResources().getColor(textColorRes));
        ((android.view.ViewGroup) statusBannerContainer).addView(banner);
    }

    @Override
    public boolean onSupportNavigateUp() {
        finish();
        return true;
    }

    @Override
    protected void onDestroy() {
        executor.shutdownNow();
        super.onDestroy();
    }
}
