package com.funwithactivity.app.features.app;

/**
 * Implemented by a tab fragment that needs an explicit "I just became the
 * visible tab" signal, distinct from the fragment's Android view lifecycle.
 *
 * {@link MainActivity} keeps all three tab fragments alive for the life of
 * the host activity and switches between them with
 * FragmentTransaction.show()/hide() rather than replace() — that preserves
 * RecyclerView scroll position and in-progress state across tab switches.
 * The cost is that hide()/show() does NOT drive onPause()/onResume(): a
 * hidden fragment's view lifecycle keeps ticking. {@link #onTabShown()} is
 * the substitute hook MainActivity calls right after a show(), which is
 * what the Recommendations tab's refetch-on-return-if-dirty policy (see
 * AppState) is built on.
 */
public interface TabVisibilityAware {
    void onTabShown();
}
