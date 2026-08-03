package com.funwithactivity.app.features.recommendations;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

import funwithactivity.recommendations.v1.Recommendations.ProviderStatus;

/**
 * {@link ProviderStatusPresentation} is required to branch on {@code
 * skipped} BEFORE {@code error}/{@code ok} (see its Javadoc) — a skipped
 * ProviderStatus also carries text in the {@code error} field, so checking
 * {@code error}/{@code !ok} first would render deliberate GDPR
 * data-minimisation ("birth date not supplied") as a provider outage. That
 * inversion has already caused three defects on this project, so this is
 * exercised explicitly rather than trusted to code review alone.
 *
 * Plain JUnit (JVM {@code test/} source set) — no instrumentation needed,
 * because the presentation logic was deliberately extracted out of the
 * screen that renders it into a class with no Android framework dependency.
 */
public class ProviderStatusPresentationTest {

    private static ProviderStatus statusNamed(String name, boolean ok, boolean skipped, String error) {
        return ProviderStatus.newBuilder()
            .setName(name)
            .setOk(ok)
            .setSkipped(skipped)
            .setError(error)
            .build();
    }

    /** ok == true must classify as OK. */
    @Test
    public void okStatusClassifiesAsOk() {
        ProviderStatus status = statusNamed("service1-stub", true, false, "");

        ProviderStatusPresentation presentation = ProviderStatusPresentation.forStatus(status);

        assertEquals(ProviderStatusPresentation.Severity.OK, presentation.getSeverity());
    }

    /**
     * The case that matters most: ok == false, skipped == true, and {@code
     * error} is ALSO populated (the skipped reason text lives there on the
     * wire). This MUST classify as INFO, never as DEGRADED — that is the
     * exact inversion that has caused three prior defects. If the
     * implementation's branch order were reversed to check {@code !ok}
     * before {@code skipped}, this assertion would fail because a
     * populated {@code error} combined with {@code ok == false} would route
     * it into the DEGRADED ("unavailable") branch instead.
     */
    @Test
    public void skippedStatusWithErrorTextClassifiesAsInfoNotDegraded() {
        ProviderStatus status = statusNamed(
            "service2-stub", false, true, "required measurements not supplied");

        ProviderStatusPresentation presentation = ProviderStatusPresentation.forStatus(status);

        assertEquals(ProviderStatusPresentation.Severity.INFO, presentation.getSeverity());
    }

    /** A genuine outage: ok == false, skipped == false. Must classify as DEGRADED. */
    @Test
    public void genuineFailureClassifiesAsDegraded() {
        ProviderStatus status = statusNamed("service1-stub", false, false, "upstream timeout");

        ProviderStatusPresentation presentation = ProviderStatusPresentation.forStatus(status);

        assertEquals(ProviderStatusPresentation.Severity.DEGRADED, presentation.getSeverity());
    }
}
