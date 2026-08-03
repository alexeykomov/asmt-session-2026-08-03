package com.funwithactivity.app.features.sources;

import android.app.AlertDialog;
import android.os.Bundle;
import android.text.TextUtils;
import android.util.Patterns;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.Spinner;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.funwithactivity.app.FunWithActivityApplication;
import com.funwithactivity.app.R;
import com.funwithactivity.app.core.state.AppState;
import com.funwithactivity.app.features.app.TabVisibilityAware;
import com.google.android.material.floatingactionbutton.FloatingActionButton;
import com.google.android.material.textfield.TextInputEditText;
import com.google.android.material.textfield.TextInputLayout;

import java.util.List;

import funwithactivity.recommendations.v1.Recommendations.ProviderStatus;

/**
 * Sources tab (1.2.0 design spec §5.3): lists the configured providers with
 * their status/latency from the most recent {@code GetRecommendationsResponse},
 * plus a {@code +} action that opens a stub add-source form.
 *
 * <p>Phase 1 (this client): the list comes from {@link AppState#getLastStatuses()}
 * — the provider registry as observed via the last fetch, not a persisted
 * table (Phase 2 makes sources managed rows; not implemented here). The
 * add-source form validates its fields and explains that a real source
 * needs a server-side adapter; nothing is persisted, and the auth token
 * field is discarded rather than stored, matching the wire contract's Phase
 * 1 boundary — no proto/gRPC change ships with this screen.
 */
public class SourcesFragment extends Fragment implements TabVisibilityAware {

    private TextView emptyView;
    private RecyclerView recyclerView;
    private SourceAdapter adapter;
    private AppState appState;

    @Override
    public void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        FunWithActivityApplication app = (FunWithActivityApplication) requireActivity().getApplication();
        appState = app.getAppState();
    }

    @Nullable
    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup container,
                              @Nullable Bundle savedInstanceState) {
        return inflater.inflate(R.layout.fragment_sources, container, false);
    }

    @Override
    public void onViewCreated(@NonNull View view, @Nullable Bundle savedInstanceState) {
        super.onViewCreated(view, savedInstanceState);
        emptyView = view.findViewById(R.id.sources_empty);
        recyclerView = view.findViewById(R.id.sources_recycler_view);
        FloatingActionButton fab = view.findViewById(R.id.sources_fab);

        adapter = new SourceAdapter(this::openSourceDetail);
        recyclerView.setLayoutManager(new LinearLayoutManager(requireContext()));
        recyclerView.setAdapter(adapter);

        fab.setOnClickListener(v -> showAddSourceDialog());

        refresh();
    }

    private void openSourceDetail(ProviderStatus status) {
        startActivity(SourceDetailActivity.createIntent(requireContext(), status));
    }

    @Override
    public void onTabShown() {
        // The most recent response may have changed while this tab was
        // hidden (a fetch happening on the Recommendations tab, or a manual
        // refresh there) — re-render from AppState every time this tab
        // becomes visible so the list can't go stale.
        refresh();
    }

    private void refresh() {
        if (getView() == null) return;
        List<ProviderStatus> statuses = appState.getLastStatuses();
        if (statuses.isEmpty()) {
            emptyView.setVisibility(View.VISIBLE);
            recyclerView.setVisibility(View.GONE);
        } else {
            emptyView.setVisibility(View.GONE);
            recyclerView.setVisibility(View.VISIBLE);
            adapter.setItems(statuses);
        }
    }

    private void showAddSourceDialog() {
        View view = LayoutInflater.from(requireContext()).inflate(R.layout.dialog_add_source, null);
        TextInputLayout nameLayout = view.findViewById(R.id.add_source_name_layout);
        TextInputEditText nameInput = view.findViewById(R.id.add_source_name);
        TextInputLayout urlLayout = view.findViewById(R.id.add_source_url_layout);
        TextInputEditText urlInput = view.findViewById(R.id.add_source_url);
        Spinner typeSpinner = view.findViewById(R.id.add_source_type);

        ArrayAdapter<CharSequence> typeAdapter = ArrayAdapter.createFromResource(
            requireContext(), R.array.source_types, android.R.layout.simple_spinner_item);
        typeAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        typeSpinner.setAdapter(typeAdapter);

        AlertDialog dialog = new AlertDialog.Builder(requireContext())
            .setTitle(R.string.add_source_title)
            .setView(view)
            .setPositiveButton(R.string.add_source_action, null)
            .setNegativeButton(android.R.string.cancel, null)
            .create();

        // Overridden after show() so an invalid submission can re-show the
        // dialog with field errors instead of dismissing it — the default
        // AlertDialog button behaviour always dismisses on click.
        dialog.setOnShowListener(d -> {
            Button positive = dialog.getButton(AlertDialog.BUTTON_POSITIVE);
            positive.setOnClickListener(v -> {
                String name = textOf(nameInput);
                String url = textOf(urlInput);

                boolean valid = true;
                if (TextUtils.isEmpty(name)) {
                    nameLayout.setError(getString(R.string.add_source_error_name));
                    valid = false;
                } else {
                    nameLayout.setError(null);
                }
                if (TextUtils.isEmpty(url) || !Patterns.WEB_URL.matcher(url).matches()) {
                    urlLayout.setError(getString(R.string.add_source_error_url));
                    valid = false;
                } else {
                    urlLayout.setError(null);
                }
                if (!valid) {
                    return;
                }

                dialog.dismiss();
                // Auth token is intentionally never read out of the form
                // beyond this point — collected because a real provider
                // would need one, discarded because a source that can never
                // be called has no business persisting a credential.
                showAddSourceExplanation(name);
            });
        });

        dialog.show();
    }

    private void showAddSourceExplanation(String name) {
        new AlertDialog.Builder(requireContext())
            .setTitle(R.string.add_source_explain_title)
            .setMessage(getString(R.string.add_source_explain_message, name))
            .setPositiveButton(android.R.string.ok, null)
            .show();
    }

    private static String textOf(TextInputEditText input) {
        return input.getText() != null ? input.getText().toString().trim() : "";
    }
}
