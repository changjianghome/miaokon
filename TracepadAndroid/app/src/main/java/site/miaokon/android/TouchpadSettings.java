package site.miaokon.android;

import android.content.Context;
import android.content.SharedPreferences;

final class TouchpadSettings {
    double horizontalSpeed;
    double verticalSpeed;
    double scrollSpeed;
    double zoomSpeed;
    double hapticStrength;
    double slowMoveMultiplier;
    boolean naturalScroll;
    boolean twoFingerRightClick;
    boolean singleFingerDrag;
    boolean hapticEnabled;
    boolean adaptiveMoveSpeed;

    private final SharedPreferences preferences;

    TouchpadSettings(Context context) {
        preferences = context.getSharedPreferences("miaokon_settings", Context.MODE_PRIVATE);
        horizontalSpeed = preferences.getFloat("horizontalSpeed", 1f);
        verticalSpeed = preferences.getFloat("verticalSpeed", 1f);
        scrollSpeed = preferences.getFloat("scrollSpeed", 1f);
        zoomSpeed = preferences.getFloat("zoomSpeed", 1f);
        hapticStrength = preferences.getFloat("hapticStrength", 0.7f);
        slowMoveMultiplier = preferences.getFloat("slowMoveMultiplier", 0.35f);
        naturalScroll = preferences.getBoolean("naturalScroll", true);
        twoFingerRightClick = preferences.getBoolean("twoFingerRightClick", true);
        singleFingerDrag = preferences.getBoolean("singleFingerDrag", true);
        hapticEnabled = preferences.getBoolean("hapticEnabled", true);
        adaptiveMoveSpeed = preferences.getBoolean("adaptiveMoveSpeed", true);
    }

    void save() {
        preferences.edit()
                .putFloat("horizontalSpeed", (float) horizontalSpeed)
                .putFloat("verticalSpeed", (float) verticalSpeed)
                .putFloat("scrollSpeed", (float) scrollSpeed)
                .putFloat("zoomSpeed", (float) zoomSpeed)
                .putFloat("hapticStrength", (float) hapticStrength)
                .putFloat("slowMoveMultiplier", (float) slowMoveMultiplier)
                .putBoolean("naturalScroll", naturalScroll)
                .putBoolean("twoFingerRightClick", twoFingerRightClick)
                .putBoolean("singleFingerDrag", singleFingerDrag)
                .putBoolean("hapticEnabled", hapticEnabled)
                .putBoolean("adaptiveMoveSpeed", adaptiveMoveSpeed)
                .apply();
    }
}
