package com.funwithactivity.app.features.sources;

import android.content.Context;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import com.funwithactivity.app.R;
import com.funwithactivity.app.features.recommendations.ProviderStatusPresentation;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import funwithactivity.recommendations.v1.Recommendations.ProviderStatus;

/**
 * Renders the Sources tab list: one row per provider from the most recent
 * {@code GetRecommendationsResponse.statuses}. Rows are tappable and open
 * {@link SourceDetailActivity} via the supplied {@link OnItemClickListener}.
 *
 * The ok/skipped/degraded classification is resolved exclusively by {@link
 * ProviderStatusPresentation#forStatus} — the same class ResultsActivity /
 * RecommendationsFragment use for the banner. This adapter only maps that
 * already-resolved severity to a label and colour; it never re-examines
 * {@code ok}/{@code skipped}/{@code error} itself. A second copy of that
 * branch is exactly what has caused four defects on this project (see
 * ProviderStatusPresentation's Javadoc) — do not "simplify" this class by
 * inlining the check.
 *
 * <p>The list row shows a SHORT reason only (e.g. "timed out", "skipped —
 * no birth date") — never the raw provider error, which embeds the full
 * vendor URL and must not be projected during a demo/presentation. {@link
 * #shortReason} is pure formatting on top of the already-resolved severity,
 * same rationale as the latency dash below; it does not re-decide anything.
 * The full raw error text still reaches the user, just on {@link
 * SourceDetailActivity}'s STATUS section, not here.
 */
public class SourceAdapter extends RecyclerView.Adapter<SourceAdapter.ViewHolder> {

    /** Notified when a row is tapped, with the row's raw (un-presented) status. */
    public interface OnItemClickListener {
        void onItemClick(ProviderStatus status);
    }

    private final List<ProviderStatus> items = new ArrayList<>();
    private final OnItemClickListener listener;

    public SourceAdapter(OnItemClickListener listener) {
        this.listener = listener;
    }

    public void setItems(List<ProviderStatus> newItems) {
        items.clear();
        items.addAll(newItems);
        notifyDataSetChanged();
    }

    @NonNull
    @Override
    public ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(parent.getContext())
            .inflate(R.layout.item_source, parent, false);
        return new ViewHolder(view);
    }

    @Override
    public void onBindViewHolder(@NonNull ViewHolder holder, int position) {
        ProviderStatus status = items.get(position);
        ProviderStatusPresentation presentation = ProviderStatusPresentation.forStatus(status);
        Context context = holder.itemView.getContext();

        holder.name.setText(presentation.getProviderName());
        holder.itemView.setOnClickListener(v -> {
            if (listener != null) listener.onItemClick(status);
        });

        switch (presentation.getSeverity()) {
            case INFO:
                holder.statusLabel.setText(R.string.source_status_skipped);
                holder.statusLabel.setBackgroundColor(context.getColor(R.color.colorStatusSkippedBg));
                holder.statusLabel.setTextColor(context.getColor(R.color.colorStatusSkippedText));
                break;
            case DEGRADED:
                holder.statusLabel.setText(R.string.source_status_degraded);
                holder.statusLabel.setBackgroundColor(context.getColor(R.color.colorStatusDegradedBg));
                holder.statusLabel.setTextColor(context.getColor(R.color.colorStatusDegradedText));
                break;
            case OK:
            default:
                holder.statusLabel.setText(R.string.source_status_ok);
                holder.statusLabel.setBackgroundColor(context.getColor(R.color.colorStatusOkBg));
                holder.statusLabel.setTextColor(context.getColor(R.color.colorStatusOk));
                break;
        }

        // Stub providers return in microseconds; a literal "0 ms" reads as
        // broken rather than fast, so zero renders as an em dash instead
        // (1.2.0 design spec §5.3). This is pure formatting, not a re-decision
        // of provider status, so it stays local to this adapter.
        String latencyValue = presentation.getLatencyMs() == 0
            ? context.getString(R.string.source_latency_dash)
            : context.getString(R.string.source_latency_ms_format, presentation.getLatencyMs());
        holder.latency.setText(context.getString(R.string.source_latency_format, latencyValue));

        String reason = shortReason(context, presentation);
        if (reason != null) {
            holder.error.setVisibility(View.VISIBLE);
            holder.error.setText(reason);
            // Colour the reason text to match its severity — INFO (skipped)
            // must read as informational/blue, never as the DEGRADED red,
            // or a deliberate data-minimisation outcome reads as an outage.
            // The "OnSurface" variants (not the badge-paired
            // colorStatusSkippedText/colorStatusDegradedText) are used here
            // deliberately: this text sits bare on the card, which stays a
            // light surface in dark mode too, so it must not pick up the
            // night-tuned lighter tone meant for the colored badge — see
            // colors.xml's comment on those two resources.
            int reasonColorRes = presentation.getSeverity() == ProviderStatusPresentation.Severity.INFO
                ? R.color.colorStatusSkippedTextOnSurface
                : R.color.colorStatusDegradedTextOnSurface;
            holder.error.setTextColor(context.getColor(reasonColorRes));
        } else {
            holder.error.setVisibility(View.GONE);
        }
    }

    /**
     * Short, presentation-only reason text for the list row. Never the raw
     * {@code error} string — that would print the vendor URL in a screen
     * that gets projected. Returns {@code null} for OK (no reason to show).
     */
    private static String shortReason(Context context, ProviderStatusPresentation presentation) {
        switch (presentation.getSeverity()) {
            case INFO:
                // The only skip reason this app produces is a missing birth
                // date (see aggregator.go's Requires() routing) — fixed text,
                // not derived from the raw error.
                return context.getString(R.string.source_reason_skipped_no_birth_date);
            case DEGRADED:
                return context.getString(looksLikeTimeout(presentation.getError())
                    ? R.string.source_reason_timed_out
                    : R.string.source_reason_unavailable);
            case OK:
            default:
                return null;
        }
    }

    private static boolean looksLikeTimeout(String rawError) {
        if (rawError == null || rawError.isEmpty()) return false;
        String lower = rawError.toLowerCase(Locale.US);
        return lower.contains("deadline exceeded") || lower.contains("timeout");
    }

    @Override
    public int getItemCount() {
        return items.size();
    }

    static class ViewHolder extends RecyclerView.ViewHolder {
        final TextView name;
        final TextView statusLabel;
        final TextView latency;
        final TextView error;

        ViewHolder(@NonNull View itemView) {
            super(itemView);
            name = itemView.findViewById(R.id.source_name);
            statusLabel = itemView.findViewById(R.id.source_status);
            latency = itemView.findViewById(R.id.source_latency);
            error = itemView.findViewById(R.id.source_error);
        }
    }
}
