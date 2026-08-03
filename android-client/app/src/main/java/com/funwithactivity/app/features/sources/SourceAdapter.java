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

import funwithactivity.recommendations.v1.Recommendations.ProviderStatus;

/**
 * Renders the Sources tab list: one row per provider from the most recent
 * {@code GetRecommendationsResponse.statuses}.
 *
 * The ok/skipped/degraded classification is resolved exclusively by {@link
 * ProviderStatusPresentation#forStatus} — the same class ResultsActivity /
 * RecommendationsFragment use for the banner. This adapter only maps that
 * already-resolved severity to a label and colour; it never re-examines
 * {@code ok}/{@code skipped}/{@code error} itself. A second copy of that
 * branch is exactly what has caused four defects on this project (see
 * ProviderStatusPresentation's Javadoc) — do not "simplify" this class by
 * inlining the check.
 */
public class SourceAdapter extends RecyclerView.Adapter<SourceAdapter.ViewHolder> {

    private final List<ProviderStatus> items = new ArrayList<>();

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

        switch (presentation.getSeverity()) {
            case INFO:
                holder.statusLabel.setText(R.string.source_status_skipped);
                holder.statusLabel.setBackgroundColor(context.getColor(R.color.colorStatusSkippedBg));
                holder.statusLabel.setTextColor(context.getColor(R.color.colorStatusSkippedText));
                break;
            case DEGRADED:
                holder.statusLabel.setText(R.string.source_status_degraded);
                holder.statusLabel.setBackgroundColor(context.getColor(R.color.colorStatusErrorBg));
                holder.statusLabel.setTextColor(context.getColor(R.color.colorStatusErrorText));
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

        String error = presentation.getError();
        if (presentation.getSeverity() == ProviderStatusPresentation.Severity.DEGRADED
            && error != null && !error.isEmpty()) {
            holder.error.setVisibility(View.VISIBLE);
            holder.error.setText(error);
        } else {
            holder.error.setVisibility(View.GONE);
        }
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
