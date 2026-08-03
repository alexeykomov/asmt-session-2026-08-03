package com.funwithactivity.app.core.health;

import android.content.Context;

import androidx.health.connect.client.HealthConnectClient;

import com.funwithactivity.app.R;

/**
 * M5 (Health Connect prefill) — PARTIALLY IMPLEMENTED, by design.
 *
 * What works: SDK-availability detection below is plain, Java-callable
 * androidx code and is wired for real.
 *
 * What is cut: actually reading HeightRecord/WeightRecord data.
 * androidx.health.connect:connect-client's read APIs are Kotlin `suspend`
 * functions over `KClass<T>`-parameterised requests — there is no Guava
 * ListenableFuture or plain-Java-friendly surface for this in the current
 * artifact (unlike e.g. WorkManager). Consuming it correctly from pure Java
 * means hand-rolling a Continuation bridge and reflectively building
 * `KClass` instances, which cannot be verified without a device that has
 * Health Connect installed *and* seeded height/weight samples — neither of
 * which could be confirmed in this environment. Rather than ship an
 * unverified suspend/continuation bridge, this always falls back to manual
 * entry, per the instruction to cut this cleanly instead of half-finishing
 * it. The house "no Kotlin source" rule is also a factor: a real fix is a
 * tiny dedicated Kotlin bridge module — a call for whoever owns this to make.
 *
 * Also note: Health Connect has no birth-date record type at all (it only
 * models measurements, not user-profile fields), so date of birth can never
 * be prefilled from Health Connect regardless of this limitation — it always
 * needs manual entry, which is why the form marks it optional independent of
 * this helper.
 */
public class HealthConnectHelper {

    /** Callback invoked with any prefill values found (nullable) and a status/explanatory message. */
    public interface Callback {
        void onResult(Double heightCm, Double weightKg, String statusMessage);
    }

    private final Context context;

    public HealthConnectHelper(Context context) {
        this.context = context.getApplicationContext();
    }

    public void prefill(Callback callback) {
        int status;
        try {
            // connect-client's own minSdk is 26 (forced down via
            // tools:overrideLibrary so the app can keep minSdk 24) — guard
            // against class-loading failures on pre-26 devices.
            status = HealthConnectClient.getSdkStatus(context);
        } catch (Throwable t) {
            callback.onResult(null, null, context.getString(R.string.health_connect_unavailable));
            return;
        }
        if (status != HealthConnectClient.SDK_AVAILABLE) {
            callback.onResult(null, null, context.getString(R.string.health_connect_unavailable));
            return;
        }

        // SDK is available, but the read path is not wired — see class Javadoc.
        callback.onResult(null, null, context.getString(R.string.health_connect_no_data));
    }
}
