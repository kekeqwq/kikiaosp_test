// SPDX-License-Identifier: Apache-2.0
package com.kiki.updater;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Insets;
import android.os.Bundle;
import android.os.Handler;
import android.util.TypedValue;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** Edge-to-edge content with a safe, always-visible action area. */
public final class UpdateActivity extends Activity {
    private TextView state;
    private LinearLayout root;
    private final Handler timer = new Handler();
    private final Runnable refresh = new Runnable() {
        public void run() {
            state.setText(UpdateService.status(UpdateActivity.this));
            timer.postDelayed(this, 1000);
        }
    };

    public void onCreate(Bundle savedState) {
        super.onCreate(savedState);
        getWindow().setDecorFitsSystemWindows(false);
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        TypedValue background = new TypedValue();
        getTheme().resolveAttribute(android.R.attr.colorBackground, background, true);
        root.setBackgroundColor(background.data);
        setContentView(root);
        root.setOnApplyWindowInsetsListener((view, windowInsets) -> {
            Insets safe = windowInsets.getInsets(
                    WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            root.setPadding(dp(20) + safe.left, dp(16) + safe.top,
                    dp(20) + safe.right, dp(16) + safe.bottom);
            applySystemBarContrast();
            return windowInsets;
        });
        root.requestApplyInsets();
        applySystemBarContrast();

        // Keep long status/error messages readable at large font sizes without
        // moving any action button underneath the system navigation area.
        ScrollView content = new ScrollView(this);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        content.addView(body);
        root.addView(content, new LinearLayout.LayoutParams(-1, 0, 1));
        TextView title = new TextView(this);
        title.setTextAppearance(android.R.style.TextAppearance_DeviceDefault_Large);
        title.setText("Kiki System Update");
        title.setTextSize(28);
        body.addView(title);
        TextView intro = new TextView(this);
        intro.setText("Full system updates, keeping your apps and data.\n"
                + "Checks official GitHub Releases automatically; no source version to select.\n"
                + "Back up important data before updating.");
        intro.setPadding(0, dp(8), 0, dp(12));
        body.addView(intro);
        state = new TextView(this);
        state.setTextAppearance(android.R.style.TextAppearance_DeviceDefault_Medium);
        state.setTextSize(17);
        body.addView(state);
        button("Check for updates", "check");
        button("Download and install", "install");
        button("Restart to finish", "reboot");
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private void applySystemBarContrast() {
        WindowInsetsController controller = getWindow().getInsetsController();
        if (controller == null) return;
        TypedValue light = new TypedValue();
        getTheme().resolveAttribute(android.R.attr.isLightTheme, light, true);
        int mask = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
        controller.setSystemBarsAppearance(light.data != 0 ? mask : 0, mask);
    }

    private void button(String label, String command) {
        Button button = new Button(this);
        button.setText(label);
        root.addView(button);
        button.setOnClickListener(view -> {
            if (command.equals("reboot")) {
                new AlertDialog.Builder(this).setTitle("Restart to finish updating?")
                        .setMessage("Android will shut down safely. KikiEmu will then start the updated system slot. Keep your PC powered on.")
                        .setPositiveButton("Restart", (dialog, which) -> send(command))
                        .setNegativeButton("Cancel", null).show();
            } else if (command.equals("install")) {
                new AlertDialog.Builder(this).setTitle("Install the verified update?")
                        .setMessage("The update installs to the inactive slot without erasing your data. You can choose when to restart after installation.")
                        .setPositiveButton("Install", (dialog, which) -> send(command))
                        .setNegativeButton("Cancel", null).show();
            } else send(command);
        });
    }

    private void send(String command) {
        startForegroundService(new Intent(this, UpdateService.class)
                .putExtra("command", command));
    }

    protected void onResume() {
        super.onResume();
        root.requestApplyInsets();
        applySystemBarContrast();
        timer.post(refresh);
    }

    protected void onPause() {
        timer.removeCallbacks(refresh);
        super.onPause();
    }
}
