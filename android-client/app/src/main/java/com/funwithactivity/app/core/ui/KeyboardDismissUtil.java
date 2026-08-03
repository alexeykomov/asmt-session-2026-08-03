package com.funwithactivity.app.core.ui;

import android.content.Context;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;

/**
 * Tap-outside-an-EditText-to-dismiss-the-keyboard helper.
 *
 * <p>Unlike iOS's {@code UIScrollView.keyboardDismissMode}, Android has no
 * built-in "tap outside to dismiss" behavior: an {@code EditText} keeps
 * focus (and the IME stays up) until something else explicitly takes focus.
 * Left alone, a user who taps away from a focused field is stuck with a
 * focused, highlighted field and no obvious way out short of the back
 * button.
 *
 * <p>{@link #dismissOnOutsideTouch} walks a view subtree and installs an
 * {@link View.OnTouchListener} on every view that is not itself an {@code
 * EditText}. The listener always returns {@code false} — it never consumes
 * the touch — so every button, switch, spinner and row underneath keeps
 * working exactly as before; see
 * {@code View#setOnTouchListener}: when the listener returns {@code false},
 * the view's own {@code onTouchEvent} still runs afterward, which is what
 * lets a button underneath still register its click. This is the reason a
 * single touch listener on the root view is not enough by itself: a child
 * that consumes the touch (a button, a switch) never lets the ancestor's
 * listener fire, and a plain, non-interactive view (a label, a divider, a
 * card's own padding) does consume the touch, but its listener does fire —
 * so tapping anywhere except an actual field dismisses the keyboard.
 */
public final class KeyboardDismissUtil {

    private KeyboardDismissUtil() {}

    /**
     * @param subtreeRoot the view (and its descendants) to wire up
     * @param window      the window the currently-focused view lives in —
     *                    the hosting {@code Activity}'s window for a
     *                    fragment, or the {@code Dialog}'s own window for a
     *                    dialog form (an {@code Activity} and a {@code
     *                    Dialog} are separate windows, so the focused view
     *                    has to be looked up in the right one)
     */
    public static void dismissOnOutsideTouch(View subtreeRoot, Window window) {
        if (!(subtreeRoot instanceof EditText)) {
            subtreeRoot.setOnTouchListener((v, event) -> {
                hideKeyboardIfEditTextFocused(window);
                return false;
            });
        }
        if (subtreeRoot instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) subtreeRoot;
            for (int i = 0; i < group.getChildCount(); i++) {
                dismissOnOutsideTouch(group.getChildAt(i), window);
            }
        }
    }

    private static void hideKeyboardIfEditTextFocused(Window window) {
        View focused = window.getDecorView().findFocus();
        if (!(focused instanceof EditText)) {
            return;
        }
        focused.clearFocus();
        InputMethodManager imm =
            (InputMethodManager) focused.getContext().getSystemService(Context.INPUT_METHOD_SERVICE);
        if (imm != null) {
            imm.hideSoftInputFromWindow(focused.getWindowToken(), 0);
        }
    }
}
