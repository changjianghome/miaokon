package site.miaokon.android;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;

import java.util.UUID;

public final class MainActivity extends Activity implements UsbTcpServer.Listener, GesturePadView.Feedback {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private TouchpadSettings settings;
    private UsbTcpServer transport;
    private TextView statusView;
    private String pendingTestId;

    private final Runnable heartbeat = new Runnable() {
        @Override public void run() {
            if (transport != null) transport.send("pause", null, null, null, null, null, null);
            handler.postDelayed(this, 1_000);
        }
    };
    private final Runnable gestureTicker = new Runnable() {
        @Override public void run() {
            if (padView != null) padView.tick(android.os.SystemClock.uptimeMillis());
            handler.postDelayed(this, 30);
        }
    };
    private GesturePadView padView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        hideSystemUi();
        settings = new TouchpadSettings(this);
        transport = new UsbTcpServer(this);

        FrameLayout root = new FrameLayout(this);
        padView = new GesturePadView(this, transport, settings, this);
        root.addView(padView, new FrameLayout.LayoutParams(-1, -1));
        root.addView(createToolbar(), new FrameLayout.LayoutParams(-1, dp(48), Gravity.TOP));
        setContentView(root);

        transport.start();
        handler.post(heartbeat);
        handler.post(gestureTicker);
    }

    private View createToolbar() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(10), dp(4), dp(10), dp(4));
        row.setBackgroundColor(0xDD0D141C);

        statusView = new TextView(this);
        statusView.setText("USB 服务启动中…");
        statusView.setTextColor(Color.WHITE);
        statusView.setTextSize(13);
        row.addView(statusView, new LinearLayout.LayoutParams(0, -1, 1f));

        row.addView(toolbarButton("设置", v -> showSettings()));
        row.addView(toolbarButton("重连", v -> {
            if (transport != null) transport.restart();
        }));
        row.addView(toolbarButton("测试", v -> testConnection()));
        row.addView(toolbarButton("震动", v -> vibrate(2, true)));
        return row;
    }

    private Button toolbarButton(String title, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setText(title);
        button.setTextSize(12);
        button.setMinWidth(dp(54));
        button.setMinimumWidth(dp(54));
        button.setPadding(dp(6), 0, dp(6), 0);
        button.setOnClickListener(listener);
        return button;
    }

    private void showSettings() {
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(20), dp(12), dp(20), dp(12));
        content.setBackgroundColor(0xFF18232E);

        addLogSlider(content, "鼠标左右速度", settings.horizontalSpeed, 0.1, 1.0, 8.0,
                value -> { settings.horizontalSpeed = value; settings.save(); });
        addLogSlider(content, "鼠标上下速度", settings.verticalSpeed, 0.1, 1.0, 8.0,
                value -> { settings.verticalSpeed = value; settings.save(); });
        addLogSlider(content, "滚动速度", settings.scrollSpeed, 0.2, 1.0, 12.0,
                value -> { settings.scrollSpeed = value; settings.save(); });
        addLogSlider(content, "捏合缩放速度", settings.zoomSpeed, 0.3, 1.0, 3.0,
                value -> { settings.zoomSpeed = value; settings.save(); });
        addLogSlider(content, "触觉反馈强度", settings.hapticStrength, 0.5, 0.9, 1.5,
                value -> { settings.hapticStrength = value; settings.save(); });
        addLogSlider(content, "慢速移动下限", settings.slowMoveMultiplier, 0.2, 0.35, 0.8,
                value -> { settings.slowMoveMultiplier = value; settings.save(); });
        addCheckBox(content, "自然滚动方向", settings.naturalScroll,
                checked -> { settings.naturalScroll = checked; settings.save(); });
        addCheckBox(content, "触觉反馈", settings.hapticEnabled,
                checked -> { settings.hapticEnabled = checked; settings.save(); });
        addCheckBox(content, "双指点按模拟右键", settings.twoFingerRightClick,
                checked -> { settings.twoFingerRightClick = checked; settings.save(); });
        addCheckBox(content, "单指长按拖动", settings.singleFingerDrag,
                checked -> { settings.singleFingerDrag = checked; settings.save(); });
        addCheckBox(content, "慢速移动自动降低倍率", settings.adaptiveMoveSpeed,
                checked -> { settings.adaptiveMoveSpeed = checked; settings.save(); });

        ScrollView scroll = new ScrollView(this);
        scroll.addView(content);
        new AlertDialog.Builder(this)
                .setTitle("miaokon-sj 设置")
                .setView(scroll)
                .setPositiveButton("完成", (dialog, which) -> dialog.dismiss())
                .show();
    }

    private interface ValueChanged { void onChange(double value); }
    private interface CheckedChanged { void onChange(boolean checked); }

    private void addLogSlider(LinearLayout parent, String label, double value,
                              double min, double mid, double max, ValueChanged changed) {
        LinearLayout section = new LinearLayout(this);
        section.setOrientation(LinearLayout.VERTICAL);
        TextView title = new TextView(this);
        title.setTextColor(Color.WHITE);
        title.setTextSize(14);
        SeekBar slider = new SeekBar(this);
        slider.setMax(1_000);
        title.setText(formatSetting(label, value));
        slider.setProgress(toPosition(value, min, mid, max));
        slider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                double next = fromPosition(progress, min, mid, max);
                title.setText(formatSetting(label, next));
                if (fromUser) changed.onChange(next);
            }
            @Override public void onStartTrackingTouch(SeekBar seekBar) { }
            @Override public void onStopTrackingTouch(SeekBar seekBar) { }
        });
        section.addView(title);
        section.addView(slider);
        parent.addView(section);
    }

    private String formatSetting(String label, double value) {
        return String.format(java.util.Locale.ROOT, "%s  %.1f×", label, value);
    }

    private static int toPosition(double value, double min, double mid, double max) {
        double p;
        if (value <= mid) p = 0.5 * Math.log(Math.max(min, value) / min) / Math.log(mid / min);
        else p = 0.5 + 0.5 * Math.log(value / mid) / Math.log(max / mid);
        return (int) Math.round(Math.max(0, Math.min(1, p)) * 1000);
    }

    private static double fromPosition(int progress, double min, double mid, double max) {
        double p = progress / 1000.0;
        if (p <= 0.5) return min * Math.pow(mid / min, p * 2);
        return mid * Math.pow(max / mid, (p - 0.5) * 2);
    }

    private void addCheckBox(LinearLayout parent, String label, boolean value, CheckedChanged changed) {
        CheckBox box = new CheckBox(this);
        box.setText(label);
        box.setTextColor(Color.WHITE);
        box.setChecked(value);
        box.setOnCheckedChangeListener((button, checked) -> changed.onChange(checked));
        parent.addView(box);
    }

    private void testConnection() {
        pendingTestId = UUID.randomUUID().toString();
        statusView.setText("发送连接测试…");
        transport.send("pause", null, null, null, null, pendingTestId, "manual_connection_test");
        String id = pendingTestId;
        handler.postDelayed(() -> {
            if (id.equals(pendingTestId) && "发送连接测试…".contentEquals(statusView.getText())) {
                statusView.setText("未收到 Mac 回执；检查电脑端是否运行");
            }
        }, 3_000);
    }

    @Override
    public void onState(String state) {
        if (statusView != null) statusView.setText(state);
    }

    @Override
    public void onAck(String id) {
        if (id != null && id.equals(pendingTestId)) {
            pendingTestId = null;
            if (statusView != null) statusView.setText("USB 已连通，Mac 已回应 ✓");
        }
    }

    @Override
    public void vibrate(int style) { vibrate(style, false); }

    private void vibrate(int style, boolean force) {
        if (!force && settings != null && !settings.hapticEnabled) return;
        Vibrator vibrator;
        if (Build.VERSION.SDK_INT >= 31) {
            VibratorManager manager = (VibratorManager) getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
            vibrator = manager == null ? null : manager.getDefaultVibrator();
        } else {
            vibrator = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
        }
        if (vibrator == null || !vibrator.hasVibrator()) return;
        int basePulses = style == 0 ? 1 : style == 1 ? 2 : 3;
        int pulses = Math.max(1, Math.min(4, (int) Math.round(basePulses * (settings == null ? 0.7 : settings.hapticStrength))));
        long[] timings = new long[pulses * 2];
        int[] amplitudes = new int[pulses * 2];
        for (int i = 0; i < pulses; i++) {
            timings[i * 2] = i == 0 ? 0 : 100;
            timings[i * 2 + 1] = 70;
            amplitudes[i * 2] = 0;
            amplitudes[i * 2 + 1] = 80;
        }
        vibrator.vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1));
    }

    private void hideSystemUi() {
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacks(heartbeat);
        handler.removeCallbacks(gestureTicker);
        if (transport != null) transport.stop();
        super.onDestroy();
    }
}
