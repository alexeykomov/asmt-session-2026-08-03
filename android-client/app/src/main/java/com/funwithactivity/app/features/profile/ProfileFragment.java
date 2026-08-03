package com.funwithactivity.app.features.profile;

import android.os.Bundle;
import android.text.Editable;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.Spinner;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.widget.SwitchCompat;
import androidx.fragment.app.Fragment;

import com.funwithactivity.app.FunWithActivityApplication;
import com.funwithactivity.app.R;
import com.funwithactivity.app.core.health.HealthConnectHelper;
import com.funwithactivity.app.core.state.AppState;
import com.funwithactivity.app.features.app.TabVisibilityAware;
import com.google.android.material.datepicker.MaterialDatePicker;
import com.google.android.material.textfield.TextInputEditText;

import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;
import java.util.concurrent.TimeUnit;

import funwithactivity.recommendations.v1.Recommendations.ProviderStatus;

/**
 * Profile tab (1.2.0 design spec §5.4): a settings-style grouped list with
 * MEASUREMENTS (height, weight, a clearable birth date) and DEVELOPER
 * (a fault switch + mode selector per provider) sections.
 *
 * <p>Every edit here writes straight through to the shared {@link
 * AppState}, which is what sets the dirty flag the Recommendations tab
 * checks on becoming visible — see AppState's Javadoc and
 * RecommendationsFragment. This fragment never decides whether to refetch
 * itself; it only ever changes state and lets the Recommendations tab react.
 *
 * <p>DEVELOPER row labels/keys track the provider names from the most
 * recent fetch ({@link AppState#getLastStatuses()}) rather than a hardcoded
 * "service1"/"service2", because the fault map key sent on the wire MUST
 * match the provider's actual name exactly (e.g. local stub-provider
 * verification reports "service1-stub"/"service2-stub", not "service1"/
 * "service2") — a mismatched key would silently no-op the fault. Before any
 * fetch has completed, the wire-contract's own default provider names are
 * used as a placeholder.
 */
public class ProfileFragment extends Fragment implements TabVisibilityAware {

    private static final String DEFAULT_PROVIDER_1 = "service1";
    private static final String DEFAULT_PROVIDER_2 = "service2";

    /**
     * Where the birth-date picker opens when nothing is set yet — purely a
     * starting position so choosing a date on stage is one gesture instead
     * of scrolling back thirty-odd years. The field itself stays unset until
     * the user actually picks something (see {@link #showDatePicker}).
     */
    private static final int DEFAULT_PICKER_YEAR = 1983;
    private static final int DEFAULT_PICKER_MONTH = Calendar.MAY;
    private static final int DEFAULT_PICKER_DAY = 29;

    private TextInputEditText heightInput;
    private TextInputEditText weightInput;
    private TextView birthDateText;
    private TextView healthConnectStatus;

    private TextView service1Label;
    private SwitchCompat service1Switch;
    private Spinner service1ModeSpinner;

    private TextView service2Label;
    private SwitchCompat service2Switch;
    private Spinner service2ModeSpinner;

    private AppState appState;
    private HealthConnectHelper healthConnectHelper;

    private String service1ProviderName = DEFAULT_PROVIDER_1;
    private String service2ProviderName = DEFAULT_PROVIDER_2;

    /** Guards listeners while views are being programmatically synced from AppState. */
    private boolean applyingState = false;

    private final SimpleDateFormat displayFormat = new SimpleDateFormat("d MMM yyyy", Locale.US);

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
        return inflater.inflate(R.layout.fragment_profile, container, false);
    }

    @Override
    public void onViewCreated(@NonNull View view, @Nullable Bundle savedInstanceState) {
        super.onViewCreated(view, savedInstanceState);

        heightInput = view.findViewById(R.id.profile_height);
        weightInput = view.findViewById(R.id.profile_weight);
        birthDateText = view.findViewById(R.id.profile_birth_date);
        healthConnectStatus = view.findViewById(R.id.profile_health_connect_status);

        service1Label = view.findViewById(R.id.profile_service1_label);
        service1Switch = view.findViewById(R.id.profile_service1_switch);
        service1ModeSpinner = view.findViewById(R.id.profile_service1_mode);

        service2Label = view.findViewById(R.id.profile_service2_label);
        service2Switch = view.findViewById(R.id.profile_service2_switch);
        service2ModeSpinner = view.findViewById(R.id.profile_service2_mode);

        healthConnectHelper = new HealthConnectHelper(requireContext());
        view.findViewById(R.id.profile_health_connect_button).setOnClickListener(v -> prefillFromHealthConnect());

        birthDateText.setOnClickListener(v -> showDatePicker());
        view.findViewById(R.id.profile_clear_birth_date).setOnClickListener(v -> setBirthDate(0L));

        heightInput.addTextChangedListener(measurementWatcher());
        weightInput.addTextChangedListener(measurementWatcher());

        service1Switch.setOnCheckedChangeListener((buttonView, isChecked) -> onFaultToggle(
            service1ProviderName, isChecked, service1ModeSpinner));
        service2Switch.setOnCheckedChangeListener((buttonView, isChecked) -> onFaultToggle(
            service2ProviderName, isChecked, service2ModeSpinner));

        service1ModeSpinner.setOnItemSelectedListener(modeSelectedListener(
            () -> service1ProviderName, service1Switch));
        service2ModeSpinner.setOnItemSelectedListener(modeSelectedListener(
            () -> service2ProviderName, service2Switch));

        applyStateToViews();
    }

    @Override
    public void onTabShown() {
        applyStateToViews();
    }

    /** Syncs every view from {@link AppState} without re-triggering the write-through listeners. */
    private void applyStateToViews() {
        if (getView() == null) return;
        applyingState = true;
        try {
            refreshProviderNames();

            heightInput.setText(formatNumber(appState.getHeightCm()));
            weightInput.setText(formatNumber(appState.getWeightKg()));
            renderBirthDate(appState.getBirthDateUnix());

            java.util.Map<String, String> faults = appState.getFaults();
            applyFaultState(service1ProviderName, faults.get(service1ProviderName), service1Switch, service1ModeSpinner);
            applyFaultState(service2ProviderName, faults.get(service2ProviderName), service2Switch, service2ModeSpinner);
        } finally {
            applyingState = false;
        }
    }

    private void refreshProviderNames() {
        List<ProviderStatus> statuses = appState.getLastStatuses();
        if (statuses.size() >= 2) {
            service1ProviderName = statuses.get(0).getName();
            service2ProviderName = statuses.get(1).getName();
        }
        service1Label.setText(service1ProviderName);
        service2Label.setText(service2ProviderName);
    }

    private void applyFaultState(String providerName, @Nullable String mode, SwitchCompat toggle, Spinner spinner) {
        boolean enabled = mode != null;
        toggle.setChecked(enabled);
        spinner.setEnabled(enabled);
        if (enabled) {
            setSpinnerSelection(spinner, mode);
        }
    }

    private void setSpinnerSelection(Spinner spinner, String value) {
        for (int i = 0; i < spinner.getAdapter().getCount(); i++) {
            if (value.equals(spinner.getAdapter().getItem(i))) {
                spinner.setSelection(i, false);
                return;
            }
        }
    }

    private TextWatcher measurementWatcher() {
        return new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {}

            @Override
            public void afterTextChanged(Editable s) {
                if (applyingState) return;
                commitMeasurements();
            }
        };
    }

    private void commitMeasurements() {
        double heightCm = parseDouble(heightInput.getText());
        double weightKg = parseDouble(weightInput.getText());
        appState.setMeasurements(heightCm, weightKg, appState.getBirthDateUnix());
    }

    private void onFaultToggle(String providerName, boolean isChecked, Spinner modeSpinner) {
        if (applyingState) return;
        modeSpinner.setEnabled(isChecked);
        if (isChecked) {
            String mode = (String) modeSpinner.getSelectedItem();
            appState.setFault(providerName, mode);
        } else {
            appState.clearFault(providerName);
        }
    }

    private interface ProviderNameSupplier {
        String get();
    }

    private AdapterView.OnItemSelectedListener modeSelectedListener(
            ProviderNameSupplier providerName, SwitchCompat toggle) {
        return new AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                if (applyingState || !toggle.isChecked()) return;
                String mode = (String) parent.getItemAtPosition(position);
                appState.setFault(providerName.get(), mode);
            }

            @Override
            public void onNothingSelected(AdapterView<?> parent) {}
        };
    }

    private void showDatePicker() {
        MaterialDatePicker<Long> picker = MaterialDatePicker.Builder.datePicker()
            .setTitleText(R.string.label_birth_date)
            .setSelection(pickerStartSelectionUtcMillis())
            .build();
        picker.addOnPositiveButtonClickListener(this::onDatePicked);
        picker.show(getParentFragmentManager(), "birth_date_picker");
    }

    /**
     * Where the picker opens, as UTC millis (MaterialDatePicker always
     * operates in UTC — see Google's docs on
     * {@code MaterialDatePicker#todayInUtcMilliseconds}). If a birth date is
     * already set, this points at that same calendar day (re-expressed in
     * UTC so the correct day highlights regardless of device timezone);
     * otherwise it points at 29 May 1983 (see {@link #DEFAULT_PICKER_YEAR}).
     * Either way this only positions the dialog — it never itself sets
     * {@link AppState}'s birth date.
     */
    private long pickerStartSelectionUtcMillis() {
        Calendar utc = Calendar.getInstance(TimeZone.getTimeZone("UTC"));
        utc.clear();
        long current = appState.getBirthDateUnix();
        if (current > 0) {
            Calendar local = Calendar.getInstance();
            local.setTimeInMillis(TimeUnit.SECONDS.toMillis(current));
            utc.set(local.get(Calendar.YEAR), local.get(Calendar.MONTH), local.get(Calendar.DAY_OF_MONTH));
        } else {
            utc.set(DEFAULT_PICKER_YEAR, DEFAULT_PICKER_MONTH, DEFAULT_PICKER_DAY);
        }
        return utc.getTimeInMillis();
    }

    /**
     * MaterialDatePicker hands back a UTC-midnight selection; re-expressed
     * against a default-timezone Calendar (same as the old
     * android.app.DatePickerDialog callback did) so the stored value keeps
     * meaning "local midnight of the chosen day", matching {@link
     * #renderBirthDate}'s formatting.
     */
    private void onDatePicked(Long utcSelectionMillis) {
        if (utcSelectionMillis == null) return;
        Calendar utc = Calendar.getInstance(TimeZone.getTimeZone("UTC"));
        utc.setTimeInMillis(utcSelectionMillis);
        Calendar local = Calendar.getInstance();
        local.clear();
        local.set(utc.get(Calendar.YEAR), utc.get(Calendar.MONTH), utc.get(Calendar.DAY_OF_MONTH));
        setBirthDate(TimeUnit.MILLISECONDS.toSeconds(local.getTimeInMillis()));
    }

    /** Sets birth date to 0 to clear it — the data-minimisation demo beat (1.2.0 spec §7). */
    private void setBirthDate(long unixSeconds) {
        appState.setMeasurements(appState.getHeightCm(), appState.getWeightKg(), unixSeconds);
        renderBirthDate(unixSeconds);
    }

    private void renderBirthDate(long unixSeconds) {
        if (unixSeconds > 0) {
            birthDateText.setText(displayFormat.format(new java.util.Date(TimeUnit.SECONDS.toMillis(unixSeconds))));
        } else {
            birthDateText.setText(R.string.birth_date_hint);
        }
    }

    private void prefillFromHealthConnect() {
        healthConnectHelper.prefill((heightCm, weightKg, statusMessage) -> {
            if (getView() == null) return;
            requireActivity().runOnUiThread(() -> {
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
        });
    }

    private static double parseDouble(@Nullable Editable text) {
        if (text == null || TextUtils.isEmpty(text.toString().trim())) return 0;
        try {
            return Double.parseDouble(text.toString().trim());
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    private static String formatNumber(double value) {
        if (value == Math.rint(value)) {
            return String.valueOf((long) value);
        }
        return String.valueOf(value);
    }
}
