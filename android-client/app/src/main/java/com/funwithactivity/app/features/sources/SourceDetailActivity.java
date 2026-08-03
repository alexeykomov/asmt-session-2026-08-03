package com.funwithactivity.app.features.sources;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;

import com.funwithactivity.app.R;
import com.funwithactivity.app.features.recommendations.ProviderStatusPresentation;

import funwithactivity.recommendations.v1.Recommendations.ProviderStatus;

/**
 * Source detail screen (1.2.0 Material-convention pass): opened by tapping a
 * row on the Sources tab. Same grouped-card style as {@link
 * com.funwithactivity.app.features.profile.ProfileFragment} — CONFIGURATION
 * (name, type, base URL) and STATUS (status, latency, last error) — the
 * Android equivalent of an iOS inset-grouped table.
 *
 * <p>Both currently-possible sources (service1, service2) are built-in and
 * therefore always read-only here: plain, non-editable rows plus a footer
 * explaining that built-in sources are configured at deployment time. There
 * is intentionally no control on this screen that silently ignores a tap.
 * A future user-added source (the Sources tab "+" form is a stub in this
 * phase — see SourcesFragment) could plausibly be editable; that is why
 * every row is rendered from a plain value here rather than baked into the
 * layout as static text — swapping a row's TextView for an EditText behind
 * an {@code editable} flag is the anticipated extension point. Building
 * that editor is explicitly out of scope for this pass.
 *
 * <p>Severity (ok/skipped/degraded) is resolved exclusively by {@link
 * ProviderStatusPresentation#forStatus} — never re-derived here. The raw
 * {@link ProviderStatus} arrives via primitive Intent extras (protobuf-lite
 * messages aren't Parcelable/Serializable) and is rebuilt with a builder
 * purely so this screen can call the one shared classifier, same as
 * SourceAdapter and RecommendationsFragment do.
 */
public class SourceDetailActivity extends AppCompatActivity {

    private static final String EXTRA_NAME = "name";
    private static final String EXTRA_OK = "ok";
    private static final String EXTRA_SKIPPED = "skipped";
    private static final String EXTRA_ERROR = "error";
    private static final String EXTRA_COUNT = "count";
    private static final String EXTRA_LATENCY_MS = "latency_ms";

    public static Intent createIntent(Context context, ProviderStatus status) {
        Intent intent = new Intent(context, SourceDetailActivity.class);
        intent.putExtra(EXTRA_NAME, status.getName());
        intent.putExtra(EXTRA_OK, status.getOk());
        intent.putExtra(EXTRA_SKIPPED, status.getSkipped());
        intent.putExtra(EXTRA_ERROR, status.getError());
        intent.putExtra(EXTRA_COUNT, status.getCount());
        intent.putExtra(EXTRA_LATENCY_MS, status.getLatencyMs());
        return intent;
    }

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_source_detail);

        ProviderStatus status = ProviderStatus.newBuilder()
            .setName(getIntent().getStringExtra(EXTRA_NAME))
            .setOk(getIntent().getBooleanExtra(EXTRA_OK, false))
            .setSkipped(getIntent().getBooleanExtra(EXTRA_SKIPPED, false))
            .setError(safe(getIntent().getStringExtra(EXTRA_ERROR)))
            .setCount(getIntent().getIntExtra(EXTRA_COUNT, 0))
            .setLatencyMs(getIntent().getLongExtra(EXTRA_LATENCY_MS, 0))
            .build();
        ProviderStatusPresentation presentation = ProviderStatusPresentation.forStatus(status);

        Toolbar toolbar = findViewById(R.id.source_detail_toolbar);
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setTitle(presentation.getProviderName());
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
        }
        toolbar.setNavigationOnClickListener(v -> finish());

        bindConfiguration(presentation);
        bindStatus(presentation);
    }

    /**
     * CONFIGURATION section. This client only ever has the two built-in
     * providers (service1/service2 — see ProfileFragment's Javadoc on why
     * their names aren't hardcoded elsewhere), so "type" and "base URL"
     * aren't on the wire (ProviderStatus carries only name/ok/skipped/
     * error/count/latency_ms — see recommendations.proto) and must not be
     * fabricated from the raw error text, which is exactly the vendor-URL
     * leak this pass is removing from the list. Both fields show the same
     * "configured at deployment time" explanation as the footer.
     */
    private void bindConfiguration(ProviderStatusPresentation presentation) {
        setText(R.id.source_detail_name_value, presentation.getProviderName());
        setText(R.id.source_detail_type_value, getString(R.string.source_detail_type_builtin));
        setText(R.id.source_detail_base_url_value, getString(R.string.source_detail_base_url_value));
        // Long-press to copy: useful for whoever needs to hand the exact
        // value to someone else mid-incident, e.g. pasting it into a ticket.
        makeCopyable(R.id.source_detail_base_url_value, R.string.source_detail_label_base_url);
    }

    private void bindStatus(ProviderStatusPresentation presentation) {
        int statusTextRes;
        int statusBgRes;
        int statusTextColorRes;
        switch (presentation.getSeverity()) {
            case INFO:
                statusTextRes = R.string.source_status_skipped;
                statusBgRes = R.color.colorStatusSkippedBg;
                statusTextColorRes = R.color.colorStatusSkippedText;
                break;
            case DEGRADED:
                statusTextRes = R.string.source_status_degraded;
                statusBgRes = R.color.colorStatusDegradedBg;
                statusTextColorRes = R.color.colorStatusDegradedText;
                break;
            case OK:
            default:
                statusTextRes = R.string.source_status_ok;
                statusBgRes = R.color.colorStatusOkBg;
                statusTextColorRes = R.color.colorStatusOk;
                break;
        }

        android.widget.TextView statusValue = findViewById(R.id.source_detail_status_value);
        statusValue.setText(statusTextRes);
        statusValue.setBackgroundColor(getColor(statusBgRes));
        statusValue.setTextColor(getColor(statusTextColorRes));

        String latencyText = presentation.getLatencyMs() == 0
            ? getString(R.string.source_latency_dash)
            : getString(R.string.source_latency_ms_format, presentation.getLatencyMs());
        setText(R.id.source_detail_latency_value, latencyText);

        // Full raw text on purpose — unlike the list, the detail screen is
        // exactly where the whole provider error (vendor URL included)
        // belongs, per the design note this screen exists to satisfy.
        String error = presentation.getError();
        boolean hasError = error != null && !error.isEmpty();
        setText(R.id.source_detail_error_value,
            hasError ? error : getString(R.string.source_detail_value_none));
        if (hasError) {
            // Full raw error (vendor URL included) — exactly what an
            // operator would want to paste into a ticket or a search.
            makeCopyable(R.id.source_detail_error_value, R.string.source_detail_label_last_error);
        }
    }

    private void setText(int viewId, String value) {
        ((TextView) findViewById(viewId)).setText(value);
    }

    /** Long-press copies the row's current text to the clipboard with a confirmation toast. */
    private void makeCopyable(int viewId, int labelRes) {
        TextView view = findViewById(viewId);
        view.setOnLongClickListener(v -> {
            ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (clipboard == null) return false;
            clipboard.setPrimaryClip(ClipData.newPlainText(getString(labelRes), view.getText()));
            Toast.makeText(this, getString(R.string.source_detail_copied_format, getString(labelRes)),
                Toast.LENGTH_SHORT).show();
            return true;
        });
    }

    private static String safe(@Nullable String value) {
        return value == null ? "" : value;
    }
}
