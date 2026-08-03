package com.funwithactivity.app.features.recommendations;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import com.funwithactivity.app.R;

import java.util.ArrayList;
import java.util.List;

import funwithactivity.recommendations.v1.Recommendations.Recommendation;

/** Renders the flat list of recommendations returned by the server. */
public class RecommendationAdapter extends RecyclerView.Adapter<RecommendationAdapter.ViewHolder> {

    /**
     * Set by RecommendationsFragment so a tapped row can open
     * RecommendationDetailActivity. Mirrors SourceAdapter's listener rather
     * than having the adapter start an Activity itself — the adapter renders,
     * the fragment navigates.
     */
    public interface OnItemClickListener {
        void onItemClick(Recommendation recommendation, int position);
    }

    private final List<Recommendation> items = new ArrayList<>();
    private OnItemClickListener listener;

    public void setOnItemClickListener(OnItemClickListener listener) {
        this.listener = listener;
    }

    public void setItems(List<Recommendation> newItems) {
        items.clear();
        items.addAll(newItems);
        notifyDataSetChanged();
    }

    @NonNull
    @Override
    public ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(parent.getContext())
            .inflate(R.layout.item_recommendation, parent, false);
        return new ViewHolder(view);
    }

    @Override
    public void onBindViewHolder(@NonNull ViewHolder holder, int position) {
        Recommendation item = items.get(position);
        holder.title.setText(item.getTitle());
        holder.details.setText(item.getDetails());
        holder.source.setText(item.getSource());
        holder.score.setText(holder.itemView.getContext()
            .getString(R.string.score_format, item.getScore()));

        // position is captured rather than read back inside the callback:
        // getBindingAdapterPosition() can return NO_POSITION mid-update, and
        // the rank shown on the detail screen must match the row tapped.
        final int position1 = position;
        holder.itemView.setOnClickListener(v -> {
            if (listener != null) listener.onItemClick(item, position1);
        });
    }

    @Override
    public int getItemCount() {
        return items.size();
    }

    static class ViewHolder extends RecyclerView.ViewHolder {
        final TextView title;
        final TextView details;
        final TextView source;
        final TextView score;

        ViewHolder(@NonNull View itemView) {
            super(itemView);
            title = itemView.findViewById(R.id.recommendation_title);
            details = itemView.findViewById(R.id.recommendation_details);
            source = itemView.findViewById(R.id.recommendation_source);
            score = itemView.findViewById(R.id.recommendation_score);
        }
    }
}
