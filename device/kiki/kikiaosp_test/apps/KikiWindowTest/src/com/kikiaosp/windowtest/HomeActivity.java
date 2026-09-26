package com.kikiaosp.windowtest;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.os.Bundle;
import android.view.Gravity;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.Collections;
import java.util.List;

public final class HomeActivity extends Activity {
    private static final int BACKGROUND = Color.rgb(8, 13, 20);
    private static final int ACCENT = Color.rgb(68, 255, 64);
    private static final int TEXT = Color.rgb(225, 237, 248);
    private LinearLayout appList;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        getWindow().setStatusBarColor(BACKGROUND);
        getWindow().setNavigationBarColor(BACKGROUND);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(24), dp(16), dp(24), dp(12));
        root.setBackgroundColor(BACKGROUND);

        TextView title = new TextView(this);
        title.setText("KikiAOSP");
        title.setTextColor(ACCENT);
        title.setTextSize(30);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setGravity(Gravity.CENTER_VERTICAL);
        root.addView(title, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(44)));

        TextView subtitle = new TextView(this);
        subtitle.setText("Installed apps");
        subtitle.setTextColor(TEXT);
        subtitle.setTextSize(16);
        subtitle.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams subtitleParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(36));
        subtitleParams.topMargin = dp(8);
        root.addView(subtitle, subtitleParams);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        appList = new LinearLayout(this);
        appList.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(appList, new ScrollView.LayoutParams(
                ScrollView.LayoutParams.MATCH_PARENT, ScrollView.LayoutParams.WRAP_CONTENT));
        root.addView(scroll, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));

        setContentView(root);
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshApps();
    }

    private void refreshApps() {
        if (appList == null) return;
        appList.removeAllViews();

        PackageManager packageManager = getPackageManager();
        Intent launcherIntent = new Intent(Intent.ACTION_MAIN);
        launcherIntent.addCategory(Intent.CATEGORY_LAUNCHER);
        List<ResolveInfo> activities = packageManager.queryIntentActivities(launcherIntent, 0);
        Collections.sort(activities, (left, right) ->
                String.CASE_INSENSITIVE_ORDER.compare(
                        left.loadLabel(packageManager).toString(),
                        right.loadLabel(packageManager).toString()));

        for (ResolveInfo resolveInfo : activities) {
            ActivityInfo activityInfo = resolveInfo.activityInfo;
            if (activityInfo == null) continue;

            Button app = new Button(this);
            app.setText(resolveInfo.loadLabel(packageManager));
            app.setAllCaps(false);
            app.setGravity(Gravity.START | Gravity.CENTER_VERTICAL);
            Drawable icon = resolveInfo.loadIcon(packageManager);
            app.setCompoundDrawablesWithIntrinsicBounds(icon, null, null, null);
            app.setCompoundDrawablePadding(dp(12));
            app.setOnClickListener(view -> {
                Intent launch = new Intent(Intent.ACTION_MAIN);
                launch.addCategory(Intent.CATEGORY_LAUNCHER);
                launch.setClassName(activityInfo.packageName, activityInfo.name);
                startActivity(launch);
            });
            appList.addView(app, new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, dp(58)));
        }

        if (activities.isEmpty()) {
            TextView empty = new TextView(this);
            empty.setText("No launcher apps found");
            empty.setTextColor(TEXT);
            empty.setTextSize(16);
            appList.addView(empty);
        }
    }

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
