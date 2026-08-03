package com.funwithactivity.app.features.recommendations;

import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;

import com.funwithactivity.app.R;
import com.google.android.material.divider.MaterialDivider;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import funwithactivity.recommendations.v1.Recommendations.ProviderStatus;
import funwithactivity.recommendations.v1.Recommendations.Recommendation;

/**
 * Recommendations → row detail. Started when a recommendation row in
 * {@link RecommendationsFragment} is tapped. Same shape as
 * {@link com.funwithactivity.app.features.sources.SourceDetailActivity} —
 * toolbar plus captioned cards — so the two detail screens read as one app.
 *
 * <p>Three sections. RECOMMENDATION shows the details text in full (the list
 * row truncates it). PROVENANCE shows one row per contributing provider with
 * the status and latency that provider reported on the fetch that produced
 * this recommendation — the point of the screen, since the list row can only
 * show the joined source string ("service1, service2", which says a merge
 * happened but not what each side contributed). RANKING shows the final score
 * and the rank.
 *
 * <p>Deliberately the final score only. Raw and normalised scores stay
 * server-side — recommendations.proto reserves those field numbers precisely
 * so the ranker's internals never become wire contract — and the note under
 * the section says so rather than leaving a reader to wonder.
 *
 * <p>Nothing here is fetched, and no wire field was added for it. Everything
 * arrives from the response the user is already looking at. Re-fetching would
 * call the vendors again and could return a different set, leaving the user
 * reading an explanation of a recommendation that is no longer the one they
 * tapped.
 *
 * <p>Like {@code SourceDetailActivity}, the model crosses the Intent boundary
 * as primitive extras rather than as a serialised proto: protobuf-lite
 * messages are not {@link java.io.Serializable} and adding a parcelable
 * wrapper for one screen is not worth the surface.
 */
public class RecommendationDetailActivity extends AppCompatActivity {

    private static final String EXTRA_TITLE = "title";
    private static final String EXTRA_DETAILS = "details";
    private static final String EXTRA_SOURCE = "source";
    private static final String EXTRA_SCORE = "score";
    private static final String EXTRA_RANK = "rank";
    private static final String EXTRA_TOTAL = "total";
    private static final String EXTRA_STATUS_NAMES = "status_names";
    private static final String EXTRA_STATUS_OK = "status_ok";
    private static final String EXTRA_STATUS_SKIPPED = "status_skipped";
    private static final String EXTRA_STATUS_LATENCY = "status_latency";

    /**
     * The server joins every contributing provider into {@code source} with
     * ", " (ExactTitleDeduper sets Source to the joined display string and
     * keeps the winner's own provider in PrimarySource). Splitting it back
     * apart is the only way to show per-provider status, and it is safe
     * because provider names are registry keys, not free text, so they
     * cannot contain a comma.
     */
    private static final String SOURCE_SEPARATOR = ", ";

    /**
     * @param statuses every status from the same response, so each provider
     *     named in the recommendation's source can be resolved to the state
     *     it reported on that same fetch.
     * @param rank 1-based position in the response's ranked order.
     */
    public static Intent createIntent(Context context, Recommendation recommendation,
                                      List<ProviderStatus> statuses, int rank, int total) {
        Intent intent = new Intent(context, RecommendationDetailActivity.class);
        intent.putExtra(EXTRA_TITLE, recommendation.getTitle());
        intent.putExtra(EXTRA_DETAILS, recommendation.getDetails());
        intent.putExtra(EXTRA_SOURCE, recommendation.getSource());
        intent.putExtra(EXTRA_SCORE, recommendation.getScore());
        intent.putExtra(EXTRA_RANK, rank);
        intent.putExtra(EXTRA_TOTAL, total);

        String[] names = new String[statuses.size()];
        boolean[] oks = new boolean[statuses.size()];
        boolean[] skipped = new boolean[statuses.size()];
        long[] latencies = new long[statuses.size()];
        for (int i = 0; i < statuses.size(); i++) {
            ProviderStatus status = statuses.get(i);
            names[i] = status.getName();
            oks[i] = status.getOk();
            skipped[i] = status.getSkipped();
            latencies[i] = status.getLatencyMs();
        }
        intent.putExtra(EXTRA_STATUS_NAMES, names);
        intent.putExtra(EXTRA_STATUS_OK, oks);
        intent.putExtra(EXTRA_STATUS_SKIPPED, skipped);
        intent.putExtra(EXTRA_STATUS_LATENCY, latencies);
        return intent;
    }

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_recommendation_detail);

        Intent intent = getIntent();
        String title = safe(intent.getStringExtra(EXTRA_TITLE));

        Toolbar toolbar = findViewById(R.id.rec_detail_toolbar);
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setTitle(title);
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
        }
        toolbar.setNavigationOnClickListener(v -> finish());

        bindRecommendation(safe(intent.getStringExtra(EXTRA_DETAILS)));
        bindProvenance(safe(intent.getStringExtra(EXTRA_SOURCE)), statusesFromIntent(intent));
        bindRanking(intent.getDoubleExtra(EXTRA_SCORE, 0),
            intent.getIntExtra(EXTRA_RANK, 0), intent.getIntExtra(EXTRA_TOTAL, 0));
    }

    /**
     * Service 1 has no details field at all, so an empty string here is the
     * vendor's data rather than a rendering failure. Say that instead of
     * showing a bare dash a presenter would have to explain.
     */
    private void bindRecommendation(String details) {
        TextView view = findViewById(R.id.rec_detail_details_value);
        if (details.isEmpty()) {
            view.setText(R.string.rec_detail_no_details);
            view.setTextColor(getColor(R.color.colorTextMuted));
        } else {
            view.setText(details);
        }
    }

    private void bindProvenance(String source, Map<String, ProviderStatus> byName) {
        LinearLayout container = findViewById(R.id.rec_detail_provenance_container);
        TextView note = findViewById(R.id.rec_detail_provenance_note);
        List<String> names = splitSources(source);

        if (names.isEmpty()) {
            addRow(container, getString(R.string.rec_detail_provenance_unknown),
                getString(R.string.source_latency_dash), R.color.colorTextMuted, false);
            note.setText(R.string.rec_detail_provenance_single);
            return;
        }

        for (int i = 0; i < names.size(); i++) {
            String name = names.get(i);
            ProviderStatus status = byName.get(name);
            if (status == null) {
                // Contributed a recommendation but reported no status in the
                // same response. Say so rather than inventing an "ok" the
                // data does not support.
                addRow(container, name, getString(R.string.rec_detail_provider_no_data),
                    R.color.colorTextMuted, i > 0);
                continue;
            }
            // The skipped-vs-degraded decision is made exactly once, by
            // ProviderStatusPresentation — never re-derived here.
            ProviderStatusPresentation presentation = ProviderStatusPresentation.forStatus(status);
            addRow(container, name, statusText(presentation), statusColorRes(presentation), i > 0);
        }

        // Two providers independently returning the same title is the merge
        // this product exists to perform, so it is stated rather than left
        // for the reader to infer from a comma in the source column.
        note.setText(names.size() > 1
            ? getString(R.string.rec_detail_provenance_merged_format, names.size())
            : getString(R.string.rec_detail_provenance_single));
    }

    private void bindRanking(double score, int rank, int total) {
        // Same "%.2f" the list row uses, so the two screens cannot show a
        // different number for the same recommendation.
        setText(R.id.rec_detail_score_value, getString(R.string.rec_detail_score_format, score));
        setText(R.id.rec_detail_rank_value, rank > 0
            ? getString(R.string.rec_detail_rank_format, rank, total)
            : getString(R.string.source_latency_dash));
    }

    private void addRow(LinearLayout container, String name, String value,
                        int valueColorRes, boolean withDivider) {
        if (withDivider) {
            MaterialDivider divider = new MaterialDivider(this);
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            int margin = getResources().getDimensionPixelSize(R.dimen.rec_detail_row_spacing);
            params.topMargin = margin;
            params.bottomMargin = margin;
            divider.setLayoutParams(params);
            divider.setDividerColor(getColor(R.color.colorDivider));
            container.addView(divider);
        }
        View row = LayoutInflater.from(this)
            .inflate(R.layout.item_provenance_row, container, false);
        ((TextView) row.findViewById(R.id.provenance_row_name)).setText(name);
        TextView status = row.findViewById(R.id.provenance_row_status);
        status.setText(value);
        status.setTextColor(getColor(valueColorRes));
        container.addView(row);
    }

    private String statusText(ProviderStatusPresentation presentation) {
        String word;
        switch (presentation.getSeverity()) {
            case INFO:
                word = getString(R.string.source_status_skipped);
                break;
            case DEGRADED:
                word = getString(R.string.source_status_degraded);
                break;
            case OK:
            default:
                word = getString(R.string.source_status_ok);
                break;
        }
        // '—' rather than '0 ms': the stub fallback returns in microseconds
        // and truncates to zero, matching the Sources list and Source detail.
        String latency = presentation.getLatencyMs() == 0
            ? getString(R.string.source_latency_dash)
            : getString(R.string.source_latency_ms_format, presentation.getLatencyMs());
        return getString(R.string.rec_detail_provider_status_format, word, latency);
    }

    private int statusColorRes(ProviderStatusPresentation presentation) {
        switch (presentation.getSeverity()) {
            case INFO:
                return R.color.colorStatusSkippedText;
            case DEGRADED:
                return R.color.colorStatusDegradedText;
            case OK:
            default:
                return R.color.colorStatusOk;
        }
    }

    /** Drops empties so a trailing or doubled separator cannot make a blank row. */
    private static List<String> splitSources(String source) {
        List<String> names = new ArrayList<>();
        for (String raw : source.split(SOURCE_SEPARATOR)) {
            String name = raw.trim();
            if (!name.isEmpty()) {
                names.add(name);
            }
        }
        return names;
    }

    private static Map<String, ProviderStatus> statusesFromIntent(Intent intent) {
        Map<String, ProviderStatus> byName = new LinkedHashMap<>();
        String[] names = intent.getStringArrayExtra(EXTRA_STATUS_NAMES);
        boolean[] oks = intent.getBooleanArrayExtra(EXTRA_STATUS_OK);
        boolean[] skipped = intent.getBooleanArrayExtra(EXTRA_STATUS_SKIPPED);
        long[] latencies = intent.getLongArrayExtra(EXTRA_STATUS_LATENCY);
        if (names == null || oks == null || skipped == null || latencies == null) {
            return byName;
        }
        int count = Math.min(names.length,
            Math.min(oks.length, Math.min(skipped.length, latencies.length)));
        for (int i = 0; i < count; i++) {
            byName.put(names[i], ProviderStatus.newBuilder()
                .setName(names[i])
                .setOk(oks[i])
                .setSkipped(skipped[i])
                .setLatencyMs(latencies[i])
                .build());
        }
        return byName;
    }

    private void setText(int viewId, String value) {
        ((TextView) findViewById(viewId)).setText(value);
    }

    private static String safe(@Nullable String value) {
        return value == null ? "" : value;
    }
}
