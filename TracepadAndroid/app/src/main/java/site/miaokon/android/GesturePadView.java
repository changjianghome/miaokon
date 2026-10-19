package site.miaokon.android;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.view.MotionEvent;
import android.view.View;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Multi-touch gesture recognizer ported to Android MotionEvent, using the iOS event protocol. */
final class GesturePadView extends View {
    interface Feedback { void vibrate(int style); }

    private enum Mode {
        IDLE, SINGLE_CANDIDATE, SINGLE_MOVE, SINGLE_HOLD,
        TWO_CANDIDATE, TWO_SCROLL, TWO_PINCH,
        THREE_CANDIDATE, THREE_HOLD,
        FOUR_CANDIDATE, FOUR_SCROLL, FOUR_MISSION, FOUR_SPACE,
        IGNORE
    }

    private static final class TouchPoint {
        final float originX;
        final float originY;
        float lastX;
        float lastY;
        final long beganAt;

        TouchPoint(float x, float y, long now) {
            originX = lastX = x;
            originY = lastY = y;
            beganAt = now;
        }
    }

    private static final class Delta {
        final float dx;
        final float dy;
        Delta(float dx, float dy) { this.dx = dx; this.dy = dy; }
    }

    private final UsbTcpServer transport;
    private final TouchpadSettings settings;
    private final Feedback feedback;
    private final Map<Integer, TouchPoint> touches = new HashMap<>();
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private Mode mode = Mode.IDLE;
    private long gestureStartedAt;
    private int maxTouches;
    private boolean cancelled;
    private boolean twoFingerMoved;
    private float initialPinchDistance;
    private float lastPinchDistance;
    private float pinchAccumulator;
    private double spaceProgress;
    private double lastSpaceDelta;
    private long lastMoveSampleAt;
    private double filteredVelocity;
    private long lastPinchHapticAt;

    GesturePadView(Context context, UsbTcpServer transport, TouchpadSettings settings, Feedback feedback) {
        super(context);
        this.transport = transport;
        this.settings = settings;
        this.feedback = feedback;
        setBackgroundColor(0xFF121A24);
        setFocusable(true);
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        paint.setColor(0xFF354655);
        paint.setTextAlign(Paint.Align.CENTER);
        paint.setTextSize(getResources().getDisplayMetrics().scaledDensity * 15);
        canvas.drawText("多点触控板", getWidth() / 2f, getHeight() / 2f, paint);
        paint.setColor(0xFF233340);
        canvas.drawText("单指移动 · 双指滚动/捏合 · 三指拖动 · 四指切换桌面",
                getWidth() / 2f, getHeight() / 2f + paint.getTextSize() * 1.8f, paint);
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        int action = event.getActionMasked();
        switch (action) {
            case MotionEvent.ACTION_DOWN:
                beginTouch(event.getPointerId(0), event.getX(0), event.getY(0));
                return true;
            case MotionEvent.ACTION_POINTER_DOWN: {
                int index = event.getActionIndex();
                beginTouch(event.getPointerId(index), event.getX(index), event.getY(index));
                return true;
            }
            case MotionEvent.ACTION_MOVE:
                moveTouches(event);
                return true;
            case MotionEvent.ACTION_POINTER_UP: {
                int index = event.getActionIndex();
                updateTouches(event);
                endTouch(event.getPointerId(index), false);
                return true;
            }
            case MotionEvent.ACTION_UP:
                updateTouches(event);
                endTouch(event.getPointerId(0), false);
                performClick();
                return true;
            case MotionEvent.ACTION_CANCEL:
                cancelled = true;
                for (Integer id : new ArrayList<>(touches.keySet())) endTouch(id, true);
                return true;
            default:
                return true;
        }
    }

    @Override
    public boolean performClick() {
        super.performClick();
        return true;
    }

    void tick(long now) {
        if (mode == Mode.SINGLE_CANDIDATE && touches.size() == 1 && settings.singleFingerDrag
                && now - gestureStartedAt >= 550) {
            mode = Mode.SINGLE_HOLD;
            haptic(1);
            transport.send("dragBeg", null, null, null, null, null, "single-finger hold drag began");
        } else if (mode == Mode.THREE_CANDIDATE && touches.size() == 3
                && now - gestureStartedAt >= 550) {
            mode = Mode.THREE_HOLD;
            haptic(2);
            transport.send("dragBeg", null, null, null, null, null, "three-finger hold drag began");
        }
    }

    private void beginTouch(int id, float x, float y) {
        int priorCount = touches.size();
        if (priorCount == 0) {
            mode = Mode.SINGLE_CANDIDATE;
            gestureStartedAt = android.os.SystemClock.uptimeMillis();
            cancelled = false;
            twoFingerMoved = false;
            maxTouches = 0;
            spaceProgress = 0;
            lastSpaceDelta = 0;
            lastMoveSampleAt = 0;
            filteredVelocity = 0;
        } else if (priorCount == 1) {
            if (mode == Mode.SINGLE_CANDIDATE) mode = Mode.TWO_CANDIDATE;
            else if (mode == Mode.SINGLE_MOVE) mode = Mode.TWO_SCROLL;
            else mode = Mode.IGNORE;
        } else if (priorCount == 2) {
            if (mode == Mode.TWO_CANDIDATE) {
                mode = Mode.THREE_CANDIDATE;
            } else {
                if (mode == Mode.TWO_PINCH) {
                    transport.send("pinch", null, null, 0.0, "cancelled",
                            null, "two-finger pinch cancelled by third touch");
                    pinchAccumulator = 0;
                }
                mode = Mode.IGNORE;
            }
        } else if (priorCount == 3 && mode == Mode.THREE_CANDIDATE) {
            mode = Mode.FOUR_CANDIDATE;
        } else {
            mode = Mode.IGNORE;
        }
        touches.put(id, new TouchPoint(x, y, android.os.SystemClock.uptimeMillis()));
        maxTouches = Math.max(maxTouches, touches.size());
        if (touches.size() == 2 && mode == Mode.TWO_CANDIDATE) {
            initialPinchDistance = distanceBetweenTouches();
            lastPinchDistance = initialPinchDistance;
            pinchAccumulator = 0;
        }
    }

    private void updateTouches(MotionEvent event) {
        for (int i = 0; i < event.getPointerCount(); i++) {
            TouchPoint point = touches.get(event.getPointerId(i));
            if (point != null) {
                point.lastX = event.getX(i);
                point.lastY = event.getY(i);
            }
        }
    }

    private void moveTouches(MotionEvent event) {
        List<Delta> deltas = new ArrayList<>();
        for (int i = 0; i < event.getPointerCount(); i++) {
            TouchPoint point = touches.get(event.getPointerId(i));
            if (point == null) continue;
            float dx = event.getX(i) - point.lastX;
            float dy = event.getY(i) - point.lastY;
            point.lastX = event.getX(i);
            point.lastY = event.getY(i);
            deltas.add(new Delta(dx, dy));
        }
        if (deltas.isEmpty()) return;
        long now = android.os.SystemClock.uptimeMillis();
        if (mode == Mode.SINGLE_CANDIDATE && touches.size() == 1 && settings.singleFingerDrag
                && now - gestureStartedAt >= 550) {
            mode = Mode.SINGLE_HOLD;
            haptic(1);
            transport.send("dragBeg", null, null, null, null, null, "single-finger hold drag began");
        }
        if (mode == Mode.SINGLE_CANDIDATE && touches.size() == 1 && anyTravelAbove(12)) {
            mode = Mode.SINGLE_MOVE;
        } else if (mode == Mode.TWO_CANDIDATE && touches.size() == 2) {
            classifyTwoFingerGesture();
        } else if (mode == Mode.FOUR_CANDIDATE && touches.size() == 4) {
            classifyFourFingerGesture();
        } else if (mode == Mode.THREE_CANDIDATE && anyTravelAbove(12)) {
            mode = Mode.THREE_HOLD;
            haptic(2);
            transport.send("dragBeg", null, null, null, null, null, "three-finger move drag began");
            sendDrag(meanDeltaX(deltas), meanDeltaY(deltas));
            return;
        }

        switch (mode) {
            case SINGLE_MOVE:
                if (touches.size() == 1) sendMove(sumDx(deltas), sumDy(deltas));
                break;
            case SINGLE_HOLD:
            case THREE_HOLD:
                sendDrag(meanDeltaX(deltas), meanDeltaY(deltas));
                break;
            case TWO_SCROLL:
                if (touches.size() == 2) sendScroll(sumDx(deltas), sumDy(deltas), 80.0);
                break;
            case TWO_PINCH:
                float distance = distanceBetweenTouches();
                emitPinch(distance - lastPinchDistance);
                lastPinchDistance = distance;
                break;
            case FOUR_SCROLL:
                sendScroll(meanDeltaX(deltas), meanDeltaY(deltas), 40.0);
                break;
            case FOUR_SPACE:
                double progress = currentSpaceProgress();
                double delta = progress - spaceProgress;
                if (Math.abs(delta) > 0.00001) {
                    spaceProgress = progress;
                    lastSpaceDelta = delta;
                    transport.send("spaceSwipe", deltaX(progress), null, null,
                            "changed", null, null);
                }
                break;
            default:
                break;
        }
    }

    private void classifyTwoFingerGesture() {
        List<TouchPoint> points = orderedTouches();
        TouchPoint a = points.get(0), b = points.get(1);
        float centerX = ((a.lastX - a.originX) + (b.lastX - b.originX)) / 2f;
        float centerY = ((a.lastY - a.originY) + (b.lastY - b.originY)) / 2f;
        float centerTravel = (float) Math.hypot(centerX, centerY);
        float distanceDelta = distanceBetweenTouches() - initialPinchDistance;
        float baseline = Math.max(initialPinchDistance, 1f);
        float ux = (b.originX - a.originX) / baseline;
        float uy = (b.originY - a.originY) / baseline;
        float aOut = -((a.lastX - a.originX) * ux + (a.lastY - a.originY) * uy);
        float bOut = (b.lastX - b.originX) * ux + (b.lastY - b.originY) * uy;
        if (Math.abs(distanceDelta) >= 20 && (aOut > 4 && bOut > 4 || aOut < -4 && bOut < -4)) {
            mode = Mode.TWO_PINCH;
            lastPinchDistance = distanceBetweenTouches();
            pinchAccumulator = 0;
            haptic(1);
            emitPinch(distanceDelta);
        } else if (centerTravel >= 12 && Math.abs(distanceDelta) <= Math.max(16, centerTravel * 1.8f)) {
            mode = Mode.TWO_SCROLL;
            haptic(1);
        } else if (maxFingerTravel() > 12) {
            twoFingerMoved = true;
        }
    }

    private void classifyFourFingerGesture() {
        List<TouchPoint> points = orderedTouches();
        float dx = 0, dy = 0;
        int moved = 0, movedForSpace = 0;
        for (TouchPoint point : points) {
            float px = point.lastX - point.originX;
            float py = point.lastY - point.originY;
            dx += px / 4f;
            dy += py / 4f;
            if (Math.hypot(px, py) > 6) moved++;
            if (Math.hypot(px, py) > 12) movedForSpace++;
        }
        if (Math.abs(dx) > Math.abs(dy) && movedForSpace >= 3 && Math.abs(dx) >= 20) {
            mode = Mode.FOUR_SPACE;
            spaceProgress = currentSpaceProgress();
            lastSpaceDelta = 0;
            haptic(1);
            transport.send("spaceSwipe", deltaX(spaceProgress), null, null,
                    "began", null, "four-finger space swipe began");
        } else if (Math.abs(dy) >= Math.abs(dx) && moved >= 3 && Math.abs(dy) >= 12) {
            if (dy < 0) {
                if (Math.abs(dy) < 28) return;
                mode = Mode.FOUR_MISSION;
                haptic(2);
                transport.send("fourSwipe", null, null, 1.0, null, null,
                        "four-finger up: Mission Control");
            } else {
                mode = Mode.FOUR_SCROLL;
                haptic(1);
                sendScroll(0, dy, 40.0);
            }
        }
    }

    private void endTouch(int id, boolean wasCancelled) {
        TouchPoint point = touches.get(id);
        if (point == null) return;
        if (wasCancelled) cancelled = true;
        long now = android.os.SystemClock.uptimeMillis();
        float travel = (float) Math.hypot(point.lastX - point.originX, point.lastY - point.originY);
        if (mode == Mode.TWO_PINCH) {
            transport.send("pinch", null, null, 0.0, cancelled ? "cancelled" : "ended",
                    null, "two-finger pinch ended");
            pinchAccumulator = 0;
            mode = Mode.IGNORE;
        }
        if (mode == Mode.FOUR_SPACE) {
            transport.send("spaceSwipe", deltaX(spaceProgress), null,
                    cancelled ? 0.0 : lastSpaceDelta * 100.0,
                    cancelled ? "cancelled" : "ended", null, null);
            mode = Mode.IGNORE;
        }
        if (mode == Mode.SINGLE_HOLD || mode == Mode.THREE_HOLD) {
            transport.send("dragEnd", null, null, null, null, null, null);
            haptic(1);
            mode = Mode.IGNORE;
        }
        if (mode == Mode.SINGLE_CANDIDATE && maxTouches == 1
                && now - point.beganAt <= 350 && travel <= 12 && !cancelled) {
            transport.send("tap", null, null, null, null, null, null);
            haptic(0);
        } else if (mode == Mode.TWO_CANDIDATE && touches.size() == 1 && maxTouches == 2
                && now - point.beganAt <= 350 && !twoFingerMoved && !cancelled
                && settings.twoFingerRightClick) {
            transport.send("rightClick", null, null, null, null, null, null);
            haptic(1);
            mode = Mode.IGNORE;
        }
        touches.remove(id);
        if (touches.isEmpty()) {
            mode = Mode.IDLE;
            cancelled = false;
            twoFingerMoved = false;
        }
    }

    private boolean anyTravelAbove(float threshold) {
        for (TouchPoint point : touches.values()) {
            if (Math.hypot(point.lastX - point.originX, point.lastY - point.originY) > threshold) return true;
        }
        return false;
    }

    private float maxFingerTravel() {
        float max = 0;
        for (TouchPoint point : touches.values()) {
            max = Math.max(max, (float) Math.hypot(point.lastX - point.originX, point.lastY - point.originY));
        }
        return max;
    }

    private List<TouchPoint> orderedTouches() {
        List<Map.Entry<Integer, TouchPoint>> entries = new ArrayList<>(touches.entrySet());
        entries.sort(Comparator.comparingInt(Map.Entry::getKey));
        List<TouchPoint> result = new ArrayList<>();
        for (Map.Entry<Integer, TouchPoint> entry : entries) result.add(entry.getValue());
        return result;
    }

    private float distanceBetweenTouches() {
        List<TouchPoint> points = orderedTouches();
        if (points.size() != 2) return 0;
        return (float) Math.hypot(points.get(1).lastX - points.get(0).lastX,
                points.get(1).lastY - points.get(0).lastY);
    }

    private double currentSpaceProgress() {
        if (touches.size() != 4 || getWidth() <= 1) return spaceProgress;
        double dx = 0;
        for (TouchPoint point : touches.values()) dx += (point.lastX - point.originX) / 4.0;
        return Math.max(-3.0, Math.min(3.0, dx / getWidth() * 3.0));
    }

    private static double deltaX(double progress) { return progress; }

    private void sendMove(float dx, float dy) {
        if (getWidth() <= 1 || getHeight() <= 1) return;
        double gain = settings.adaptiveMoveSpeed ? adaptiveGain(dx, dy) : 1.0;
        transport.send("move", dx / getHeight() * settings.horizontalSpeed * gain,
                dy / getWidth() * settings.verticalSpeed * gain, null, null, null, null);
    }

    private double adaptiveGain(float dx, float dy) {
        long now = android.os.SystemClock.uptimeMillis();
        double elapsed = lastMoveSampleAt == 0 ? 0.016 : Math.min(0.25, Math.max(0.004, (now - lastMoveSampleAt) / 1000.0));
        double instant = Math.hypot(dx, dy) / elapsed;
        if (lastMoveSampleAt == 0 || now - lastMoveSampleAt > 250) filteredVelocity = instant;
        else {
            double smoothing = 1.0 - Math.exp(-elapsed / 0.075);
            filteredVelocity += (instant - filteredVelocity) * smoothing;
        }
        lastMoveSampleAt = now;
        double p = Math.max(0, Math.min(1, (filteredVelocity - 70) / (520 - 70)));
        double eased = p * p * (3 - 2 * p);
        double floor = Math.max(0.2, Math.min(0.8, settings.slowMoveMultiplier));
        return floor + (1 - floor) * eased;
    }

    private void sendDrag(float dx, float dy) {
        if (getWidth() <= 1 || getHeight() <= 1) return;
        transport.send("drag", dx / getHeight() * settings.horizontalSpeed,
                dy / getWidth() * settings.verticalSpeed, null, null, null, null);
    }

    private void sendScroll(float dx, float dy, double divisor) {
        double direction = settings.naturalScroll ? 1 : -1;
        transport.send("scroll", dx * settings.scrollSpeed * direction / divisor,
                dy * settings.scrollSpeed * direction / divisor, null, null, null, null);
    }

    private void emitPinch(float distanceDelta) {
        pinchAccumulator += distanceDelta;
        double speed = Math.max(0.3, Math.min(3.0, settings.zoomSpeed));
        double stepDistance = 30.0 / speed;
        boolean emitted = false;
        while (pinchAccumulator >= stepDistance) {
            transport.send("pinch", null, null, 1.0, "changed", null, null);
            pinchAccumulator -= stepDistance;
            emitted = true;
        }
        while (pinchAccumulator <= -stepDistance) {
            transport.send("pinch", null, null, -1.0, "changed", null, null);
            pinchAccumulator += stepDistance;
            emitted = true;
        }
        long now = android.os.SystemClock.uptimeMillis();
        if (emitted && now - lastPinchHapticAt >= 550) {
            lastPinchHapticAt = now;
            haptic(0);
        }
    }

    private static float sumDx(List<Delta> values) {
        float result = 0; for (Delta d : values) result += d.dx; return result;
    }
    private static float sumDy(List<Delta> values) {
        float result = 0; for (Delta d : values) result += d.dy; return result;
    }
    private static float meanDeltaX(List<Delta> values) { return sumDx(values) / Math.max(1, values.size()); }
    private static float meanDeltaY(List<Delta> values) { return sumDy(values) / Math.max(1, values.size()); }

    private void haptic(int style) {
        if (settings.hapticEnabled && feedback != null) feedback.vibrate(style);
    }
}
