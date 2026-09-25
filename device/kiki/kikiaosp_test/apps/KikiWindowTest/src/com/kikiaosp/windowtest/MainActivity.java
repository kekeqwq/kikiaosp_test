package com.kikiaosp.windowtest;

import android.animation.ValueAnimator;
import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

public final class MainActivity extends Activity {
    private static final int BACKGROUND = Color.rgb(8, 13, 20);
    private static final int GREEN = Color.rgb(68, 255, 64);
    private static final int ORANGE = Color.rgb(255, 145, 32);
    private static final int TEXT = Color.rgb(225, 237, 248);

    private FrameLayout root;
    private View movingSquare;
    private ValueAnimator animator;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        root = new FrameLayout(this);
        root.setBackgroundColor(BACKGROUND);

        LinearLayout center = new LinearLayout(this);
        center.setOrientation(LinearLayout.VERTICAL);
        center.setGravity(Gravity.CENTER);

        TextView result = new TextView(this);
        result.setText("TEST OK");
        result.setTextColor(GREEN);
        result.setTextSize(42);
        result.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        result.setGravity(Gravity.CENTER);
        center.addView(result, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        TextView subtitle = new TextView(this);
        subtitle.setText("KikiAOSP · Android Activity / WindowManager");
        subtitle.setTextColor(TEXT);
        subtitle.setTextSize(15);
        subtitle.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams subtitleParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        subtitleParams.topMargin = dp(12);
        center.addView(subtitle, subtitleParams);

        root.addView(center, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        addCloseHeader();
        addMovingSquare();
        setContentView(root);
        root.addOnLayoutChangeListener((view, left, top, right, bottom,
                                       oldLeft, oldTop, oldRight, oldBottom) -> startAnimation());
    }

    private void addCloseHeader() {
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(18), dp(8), dp(18), dp(8));

        TextView title = new TextView(this);
        title.setText("KikiAOSP test window");
        title.setTextColor(TEXT);
        title.setTextSize(16);
        header.addView(title, new LinearLayout.LayoutParams(0,
                LinearLayout.LayoutParams.WRAP_CONTENT, 1));

        Button close = new Button(this);
        close.setText("×  Close");
        close.setAllCaps(false);
        close.setTextColor(Color.WHITE);
        close.setOnClickListener(view -> finish());
        header.addView(close, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        root.addView(header, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP));
    }

    private void addMovingSquare() {
        movingSquare = new View(this);
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(GREEN);
        shape.setCornerRadius(dp(3));
        movingSquare.setBackground(shape);

        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(dp(36), dp(36),
                Gravity.BOTTOM | Gravity.START);
        params.setMargins(dp(24), 0, 0, dp(28));
        root.addView(movingSquare, params);
    }

    private void startAnimation() {
        if (animator != null || movingSquare == null || root.getWidth() == 0) return;
        animator = ValueAnimator.ofFloat(0f, 1f);
        animator.setDuration(1800);
        animator.setRepeatCount(ValueAnimator.INFINITE);
        animator.setRepeatMode(ValueAnimator.REVERSE);
        animator.addUpdateListener(value -> {
            float progress = (float) value.getAnimatedValue();
            float travel = Math.max(0, root.getWidth() - movingSquare.getWidth() - dp(48));
            movingSquare.setTranslationX(progress * travel);
            movingSquare.setBackgroundColor(progress < 0.5f ? GREEN : ORANGE);
        });
        animator.start();
    }

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    @Override
    protected void onDestroy() {
        if (animator != null) animator.cancel();
        super.onDestroy();
    }
}
