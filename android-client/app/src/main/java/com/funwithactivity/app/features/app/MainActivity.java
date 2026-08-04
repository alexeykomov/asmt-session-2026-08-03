package com.funwithactivity.app.features.app;

import android.os.Bundle;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;
import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentManager;
import androidx.fragment.app.FragmentTransaction;

import com.funwithactivity.app.R;
import com.funwithactivity.app.features.charts.ChartsFragment;
import com.funwithactivity.app.features.profile.ProfileFragment;
import com.funwithactivity.app.features.recommendations.RecommendationsFragment;
import com.funwithactivity.app.features.sources.SourcesFragment;
import com.google.android.material.bottomnavigation.BottomNavigationView;

/**
 * LAUNCHER activity: hosts the three-tab shell (Recommendations / Sources /
 * Profile) behind a {@link BottomNavigationView}, per the 1.2.0 tabbed-UI
 * design spec §5.1 ("Android: BottomNavigationView").
 *
 * All three tab fragments are created once and kept alive for the life of
 * this activity, switched with show()/hide() rather than replace() so that
 * e.g. the Recommendations RecyclerView's scroll position survives a trip
 * to another tab. Because hide()/show() does not drive fragment
 * onPause()/onResume(), tabs that need an explicit "I just became visible"
 * signal implement {@link TabVisibilityAware}; this activity calls it right
 * after a show().
 */
public class MainActivity extends AppCompatActivity {

    private static final String TAG_RECOMMENDATIONS = "tab-recommendations";
    private static final String TAG_SOURCES = "tab-sources";
    private static final String TAG_CHARTS = "tab-charts";
    private static final String TAG_PROFILE = "tab-profile";

    private Fragment recommendationsFragment;
    private Fragment sourcesFragment;
    private Fragment chartsFragment;
    private Fragment profileFragment;
    private Fragment activeFragment;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        Toolbar toolbar = findViewById(R.id.toolbar);
        setSupportActionBar(toolbar);

        FragmentManager fm = getSupportFragmentManager();

        if (savedInstanceState == null) {
            recommendationsFragment = new RecommendationsFragment();
            sourcesFragment = new SourcesFragment();
            chartsFragment = new ChartsFragment();
            profileFragment = new ProfileFragment();

            FragmentTransaction tx = fm.beginTransaction();
            tx.add(R.id.fragment_container, profileFragment, TAG_PROFILE).hide(profileFragment);
            tx.add(R.id.fragment_container, chartsFragment, TAG_CHARTS).hide(chartsFragment);
            tx.add(R.id.fragment_container, sourcesFragment, TAG_SOURCES).hide(sourcesFragment);
            tx.add(R.id.fragment_container, recommendationsFragment, TAG_RECOMMENDATIONS);
            tx.commitNow();

            activeFragment = recommendationsFragment;
            // Not notified here: onResume() runs immediately after onCreate()
            // on every code path (fresh launch, config change, process
            // restore) and is the single place that signals "the active tab
            // is visible". Calling notifyShown() here too would double-fire
            // it on cold start, racing two concurrent fetches.
        } else {
            // Fragment manager already restored the three fragments (and
            // their hidden/shown state) across the config change; just
            // re-acquire the references.
            recommendationsFragment = fm.findFragmentByTag(TAG_RECOMMENDATIONS);
            sourcesFragment = fm.findFragmentByTag(TAG_SOURCES);
            chartsFragment = fm.findFragmentByTag(TAG_CHARTS);
            profileFragment = fm.findFragmentByTag(TAG_PROFILE);
            activeFragment = resolveActiveFragment();
        }

        BottomNavigationView bottomNav = findViewById(R.id.bottom_navigation);
        bottomNav.setOnItemSelectedListener(this::onTabSelected);
    }

    private Fragment resolveActiveFragment() {
        if (sourcesFragment != null && !sourcesFragment.isHidden()) return sourcesFragment;
        if (chartsFragment != null && !chartsFragment.isHidden()) return chartsFragment;
        if (profileFragment != null && !profileFragment.isHidden()) return profileFragment;
        return recommendationsFragment;
    }

    private boolean onTabSelected(@NonNull android.view.MenuItem item) {
        Fragment target;
        int id = item.getItemId();
        if (id == R.id.nav_recommendations) {
            target = recommendationsFragment;
        } else if (id == R.id.nav_sources) {
            target = sourcesFragment;
        } else if (id == R.id.nav_charts) {
            target = chartsFragment;
        } else if (id == R.id.nav_profile) {
            target = profileFragment;
        } else {
            return false;
        }
        showTab(target);
        return true;
    }

    private void showTab(Fragment target) {
        if (target == activeFragment) {
            return;
        }
        FragmentTransaction tx = getSupportFragmentManager().beginTransaction();
        if (activeFragment != null) {
            tx.hide(activeFragment);
        }
        tx.show(target);
        tx.commit();
        activeFragment = target;
        notifyShown(target);
    }

    private void notifyShown(Fragment fragment) {
        if (fragment instanceof TabVisibilityAware) {
            ((TabVisibilityAware) fragment).onTabShown();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        // The activity itself coming back to the foreground (e.g. after the
        // app was backgrounded, or Health Connect returned control to us)
        // counts as "becoming visible" for whichever tab is currently
        // active, same as a tab switch would.
        if (activeFragment != null) {
            notifyShown(activeFragment);
        }
    }
}
