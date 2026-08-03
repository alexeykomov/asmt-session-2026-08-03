package com.funwithactivity.app.core.state;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import funwithactivity.recommendations.v1.Recommendations.ProviderStatus;

/**
 * Shared client state: the measurements and developer fault settings the
 * Profile tab edits, plus a dirty flag and the most recent fetch result.
 *
 * Mirrors web-client's {@code funwithactivity.app.AppState}
 * (web-client/src/features/app/app-state.js): same three concerns
 * (measurements, faults, a dirty flag), same touch-only-on-real-change
 * discipline. The dirty flag exists so the Recommendations tab can refetch
 * on becoming visible ONLY when something actually changed — refetching
 * unconditionally burns a vendor call on every tab switch (the vendors are
 * flaky and rate-limited); never refetching makes the app look like it
 * ignored the user. See the Recommendations fragment for the consumer side
 * of this contract.
 *
 * One process-lifetime instance, held by {@link
 * com.funwithactivity.app.FunWithActivityApplication}. Not persisted to
 * disk and not thread-confined to the UI thread — all mutators are
 * synchronized because the gRPC fetch happens on a background executor
 * while Profile edits happen on the UI thread.
 */
public final class AppState {

    // Demo-friendly defaults so the app is populated with results on first
    // launch without requiring a Profile visit first: both providers engage
    // (service2 requires a birth date; service1 does not). Clearing the
    // birth date from Profile is the data-minimisation demo beat — it drops
    // service2 out of the response and shows the skipped banner.
    private static final double DEFAULT_HEIGHT_CM = 175.0;
    private static final double DEFAULT_WEIGHT_KG = 70.0;
    /** 1990-01-01T00:00:00Z, matches the demo constant used elsewhere in this client. */
    private static final long DEFAULT_BIRTH_DATE_UNIX = 631152000L;

    private double heightCm = DEFAULT_HEIGHT_CM;
    private double weightKg = DEFAULT_WEIGHT_KG;
    /** 0 means "not supplied" — mirrors the proto's own sentinel. */
    private long birthDateUnix = DEFAULT_BIRTH_DATE_UNIX;

    /** Provider name -> fault mode ("error" | "timeout" | "malformed"). */
    private final Map<String, String> faults = new LinkedHashMap<>();

    private boolean dirty = false;

    /**
     * Set true the instant the first fetch completes (success or failure).
     * The Recommendations tab fetches once on first appearance regardless
     * of {@link #dirty}; after that, only a dirty tab triggers a refetch.
     */
    private boolean everFetched = false;

    /** Statuses from the most recently completed fetch; feeds the Sources tab. */
    private List<ProviderStatus> lastStatuses = Collections.emptyList();

    public synchronized double getHeightCm() {
        return heightCm;
    }

    public synchronized double getWeightKg() {
        return weightKg;
    }

    public synchronized long getBirthDateUnix() {
        return birthDateUnix;
    }

    /**
     * Writes measurements, marking state dirty only if a value actually
     * changed — an unchanged write (e.g. re-focusing and blurring a field
     * without editing it) must not schedule a refetch.
     */
    public synchronized void setMeasurements(double heightCm, double weightKg, long birthDateUnix) {
        if (this.heightCm == heightCm && this.weightKg == weightKg && this.birthDateUnix == birthDateUnix) {
            return;
        }
        this.heightCm = heightCm;
        this.weightKg = weightKg;
        this.birthDateUnix = birthDateUnix;
        touch();
    }

    /** Defensive copy — callers must not mutate the live fault map. */
    public synchronized Map<String, String> getFaults() {
        return new LinkedHashMap<>(faults);
    }

    public synchronized void setFault(String provider, String mode) {
        if (mode.equals(faults.get(provider))) {
            return;
        }
        faults.put(provider, mode);
        touch();
    }

    public synchronized void clearFault(String provider) {
        if (!faults.containsKey(provider)) {
            return;
        }
        faults.remove(provider);
        touch();
    }

    public synchronized boolean isDirty() {
        return dirty;
    }

    /** Called by the Recommendations tab once it has fetched against current state. */
    public synchronized void markClean() {
        dirty = false;
    }

    public synchronized boolean hasFetchedOnce() {
        return everFetched;
    }

    public synchronized void setFetchedOnce() {
        everFetched = true;
    }

    public synchronized List<ProviderStatus> getLastStatuses() {
        return lastStatuses;
    }

    public synchronized void setLastStatuses(List<ProviderStatus> statuses) {
        this.lastStatuses = statuses;
    }

    private void touch() {
        dirty = true;
    }
}
