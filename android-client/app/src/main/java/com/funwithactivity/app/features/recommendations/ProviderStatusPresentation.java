package com.funwithactivity.app.features.recommendations;

import java.util.ArrayList;
import java.util.List;

import funwithactivity.recommendations.v1.Recommendations.ProviderStatus;

/**
 * Turns a {@link ProviderStatus} into a UI-ready severity classification.
 * Pulled out of the screen that renders it (originally ResultsActivity; now
 * {@link com.funwithactivity.app.features.recommendations.RecommendationsFragment}
 * and {@link com.funwithactivity.app.features.sources.SourceAdapter}, which
 * both need an Android {@code Context}/resources to turn a severity into
 * banner/label text) so the one rule that matters is defined exactly once,
 * in a plain-Java class that a JVM unit test can exercise without
 * Robolectric or instrumentation:
 *
 * <p>ALWAYS branch on {@code skipped} BEFORE {@code error}/{@code ok}. A
 * skipped status also carries text in {@code error} (it reuses the field for
 * the human-readable reason), so checking {@code error} first renders
 * deliberate GDPR data-minimisation ("user declined to supply birth date")
 * as if it were a service outage. That exact inversion has already caused
 * three defects on this project — do not "simplify" this by checking
 * {@code !ok} first.
 */
public final class ProviderStatusPresentation {

    public enum Severity {
        /** ok == true. Not a failure — rendered informationally (or not at all), never as an error. */
        OK,
        /** ok == false, skipped == true. Not a failure — the user declined an input this provider needs. */
        INFO,
        /** ok == false, skipped == false. A genuine outage. */
        DEGRADED,
    }

    private final String providerName;
    private final Severity severity;
    private final String error;
    private final int count;
    private final long latencyMs;

    private ProviderStatusPresentation(String providerName, Severity severity, String error, int count, long latencyMs) {
        this.providerName = providerName;
        this.severity = severity;
        this.error = error;
        this.count = count;
        this.latencyMs = latencyMs;
    }

    public String getProviderName() {
        return providerName;
    }

    public Severity getSeverity() {
        return severity;
    }

    public String getError() {
        return error;
    }

    public int getCount() {
        return count;
    }

    public long getLatencyMs() {
        return latencyMs;
    }

    /**
     * Classifies one status. Branch order is the entire point of this class:
     * {@code skipped} MUST be checked before {@code ok}/{@code error} — see
     * class Javadoc for why.
     */
    public static ProviderStatusPresentation forStatus(ProviderStatus status) {
        if (status.getSkipped()) {
            return new ProviderStatusPresentation(
                status.getName(), Severity.INFO, status.getError(), status.getCount(), status.getLatencyMs());
        } else if (!status.getOk()) {
            return new ProviderStatusPresentation(
                status.getName(), Severity.DEGRADED, status.getError(), status.getCount(), status.getLatencyMs());
        } else {
            return new ProviderStatusPresentation(
                status.getName(), Severity.OK, status.getError(), status.getCount(), status.getLatencyMs());
        }
    }

    public static List<ProviderStatusPresentation> forStatuses(List<ProviderStatus> statuses) {
        List<ProviderStatusPresentation> result = new ArrayList<>();
        for (ProviderStatus status : statuses) {
            result.add(forStatus(status));
        }
        return result;
    }
}
