package com.funwithactivity.app.features.measurement;

import android.app.DatePickerDialog;
import android.content.Intent;
import android.os.Bundle;
import android.text.TextUtils;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import com.funwithactivity.app.BuildConfig;
import com.funwithactivity.app.R;
import com.funwithactivity.app.core.health.HealthConnectHelper;
import com.funwithactivity.app.features.recommendations.ResultsActivity;
import com.google.android.material.textfield.TextInputEditText;

import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Locale;
import java.util.concurrent.TimeUnit;

/**
 * Measurement entry screen: height (required), weight (required) and
 * birth date (optional — a user may decline it, and the server still
 * returns results from providers that don't require it; see
 * recommendations.proto's Measurements.birth_date_unix comment).
 */
public class MeasurementActivity extends AppCompatActivity {

    // DEBUG-only launch hook for headless verification, matching the house
    // convention of test-only launch overrides used on the iOS client (see
    // FWAMeasurementViewController's -FWA_AUTOSUBMIT_DEMO). Android has no
    // equivalent of NSUserDefaults launch arguments, so this reads Intent
    // extras instead — set with `am start -n <pkg>/.MeasurementActivity
    // --ez EXTRA_AUTOSUBMIT_DEMO true [--ez EXTRA_AUTOSUBMIT_DEMO_BIRTHDATE true]`.
    // Never reachable in a release build (guarded by BuildConfig.DEBUG).
    public static final String EXTRA_AUTOSUBMIT_DEMO = "com.funwithactivity.app.AUTOSUBMIT_DEMO";
    public static final String EXTRA_AUTOSUBMIT_DEMO_BIRTHDATE = "com.funwithactivity.app.AUTOSUBMIT_DEMO_BIRTHDATE";
    /** 1990-01-01T00:00:00Z — arbitrary, matches the value used in prior gRPC edge verification. */
    private static final long DEMO_BIRTH_DATE_UNIX = 631152000L;

    private TextInputEditText heightInput;
    private TextInputEditText weightInput;
    private TextView birthDateInput;
    private TextView healthConnectStatus;

    /** 0 means "not supplied" — mirrors the proto's own sentinel. */
    private long birthDateUnixSeconds = 0L;

    private HealthConnectHelper healthConnectHelper;
    private final SimpleDateFormat displayFormat =
        new SimpleDateFormat("d MMM yyyy", Locale.US);

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_measurement);

        if (getSupportActionBar() != null) {
            getSupportActionBar().setTitle(R.string.measurement_title);
        }

        heightInput = findViewById(R.id.input_height_cm);
        weightInput = findViewById(R.id.input_weight_kg);
        birthDateInput = findViewById(R.id.input_birth_date);
        healthConnectStatus = findViewById(R.id.health_connect_status);
        Button submitButton = findViewById(R.id.submit_button);
        Button healthConnectButton = findViewById(R.id.health_connect_button);
        Button clearBirthDateButton = findViewById(R.id.clear_birth_date_button);

        birthDateInput.setOnClickListener(v -> showDatePicker());
        clearBirthDateButton.setOnClickListener(v -> setBirthDate(0L));
        submitButton.setOnClickListener(v -> onSubmit());

        healthConnectHelper = new HealthConnectHelper(this);
        healthConnectButton.setOnClickListener(v -> prefillFromHealthConnect());

        if (BuildConfig.DEBUG) {
            maybeAutoSubmitForDemoVerification(submitButton);
        }
    }

    /** See {@link #EXTRA_AUTOSUBMIT_DEMO} for how this is invoked. */
    private void maybeAutoSubmitForDemoVerification(Button submitButton) {
        if (!getIntent().getBooleanExtra(EXTRA_AUTOSUBMIT_DEMO, false)) {
            return;
        }
        heightInput.setText("175");
        weightInput.setText("70");
        if (getIntent().getBooleanExtra(EXTRA_AUTOSUBMIT_DEMO_BIRTHDATE, false)) {
            setBirthDate(DEMO_BIRTH_DATE_UNIX);
        } else {
            setBirthDate(0L); // exercise the GDPR-skip path by default
        }
        submitButton.postDelayed(this::onSubmit, 500);
    }

    private void showDatePicker() {
        Calendar calendar = Calendar.getInstance();
        if (birthDateUnixSeconds > 0) {
            calendar.setTimeInMillis(TimeUnit.SECONDS.toMillis(birthDateUnixSeconds));
        } else {
            calendar.add(Calendar.YEAR, -30);
        }
        new DatePickerDialog(this, (view, year, month, dayOfMonth) -> {
            Calendar picked = Calendar.getInstance();
            picked.clear();
            picked.set(year, month, dayOfMonth);
            setBirthDate(TimeUnit.MILLISECONDS.toSeconds(picked.getTimeInMillis()));
        }, calendar.get(Calendar.YEAR), calendar.get(Calendar.MONTH), calendar.get(Calendar.DAY_OF_MONTH))
            .show();
    }

    private void setBirthDate(long unixSeconds) {
        birthDateUnixSeconds = unixSeconds;
        if (unixSeconds > 0) {
            birthDateInput.setText(displayFormat.format(new java.util.Date(TimeUnit.SECONDS.toMillis(unixSeconds))));
        } else {
            birthDateInput.setText(R.string.birth_date_hint);
        }
    }

    private void prefillFromHealthConnect() {
        healthConnectHelper.prefill(new HealthConnectHelper.Callback() {
            @Override
            public void onResult(Double heightCm, Double weightKg, String statusMessage) {
                runOnUiThread(() -> {
                    if (heightCm != null) {
                        heightInput.setText(String.format(Locale.US, "%.1f", heightCm));
                    }
                    if (weightKg != null) {
                        weightInput.setText(String.format(Locale.US, "%.1f", weightKg));
                    }
                    if (statusMessage != null) {
                        healthConnectStatus.setText(statusMessage);
                        healthConnectStatus.setVisibility(View.VISIBLE);
                    }
                });
            }
        });
    }

    private void onSubmit() {
        String heightText = heightInput.getText() != null ? heightInput.getText().toString().trim() : "";
        String weightText = weightInput.getText() != null ? weightInput.getText().toString().trim() : "";

        double heightCm = parsePositiveDouble(heightText);
        double weightKg = parsePositiveDouble(weightText);

        if (heightCm <= 0) {
            Toast.makeText(this, R.string.error_height_required, Toast.LENGTH_SHORT).show();
            return;
        }
        if (weightKg <= 0) {
            Toast.makeText(this, R.string.error_weight_required, Toast.LENGTH_SHORT).show();
            return;
        }

        Intent intent = new Intent(this, ResultsActivity.class);
        intent.putExtra(ResultsActivity.EXTRA_HEIGHT_CM, heightCm);
        intent.putExtra(ResultsActivity.EXTRA_WEIGHT_KG, weightKg);
        intent.putExtra(ResultsActivity.EXTRA_BIRTH_DATE_UNIX, birthDateUnixSeconds);
        startActivity(intent);
    }

    private double parsePositiveDouble(String text) {
        if (TextUtils.isEmpty(text)) return 0;
        try {
            return Double.parseDouble(text);
        } catch (NumberFormatException e) {
            return 0;
        }
    }
}
