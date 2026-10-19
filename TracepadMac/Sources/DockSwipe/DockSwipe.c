// Horizontal Spaces gesture synthesis, adapted from joshuarli/iss (0BSD).
// macOS 27 requires the serialized raw IOHID payload on Dock swipe events.
// See https://github.com/joshuarli/iss and its LICENSE.

#include "DockSwipe.h"

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum {
    kCGSEventTypeField = 55,
    kCGSEventGesture = 29,
    kCGSEventDockControl = 30,
    kCGEventGestureHIDType = 110,
    kIOHIDEventTypeDockSwipe = 23,
    kCGEventGestureSwipeMotion = 123,
    kCGGestureMotionHorizontal = 1,
    kCGEventGestureSwipeProgress = 124,
    kCGEventGestureSwipeVelocityX = 129,
    kCGEventGestureSwipeVelocityY = 130,
    kCGEventGesturePhase = 132,
    kCGEventGestureSwipePositionX = 125,
    kCGEventGesturePhaseAlias = 134,
    kCGEventGestureZoomDeltaY = 138,
    kCGEventSourceProcessAlias = 169,
    kCGEventRawIOHIDPayload = 4205,
    kGestureBegan = 1,
    kGestureChanged = 2,
    kGestureEnded = 4,
    kGestureCancelled = 8,
    kIOHIDEventTypeVelocity = 9,
    kIOHIDEventTypeFluidTouchGesture = 23,
    kIOHIDGestureFlavorDockPrimary = 3,
};

#pragma pack(push, 1)
typedef struct {
    uint32_t size;
    uint32_t type;
    uint32_t options;
    uint8_t depth;
    uint8_t reserved[3];
} IOHIDEventBase;

typedef struct {
    IOHIDEventBase base;
    int32_t positionX;
    int32_t positionY;
    int32_t positionZ;
    uint32_t swipeMask;
    uint16_t gestureMotion;
    uint16_t gestureFlavor;
    int32_t swipeProgress;
} IOHIDFluidTouchGestureData;

typedef struct {
    IOHIDEventBase base;
    int32_t velocityX;
    int32_t velocityY;
    int32_t velocityZ;
} IOHIDVelocityEventData;

typedef struct {
    uint64_t timestamp;
    uint64_t senderID;
    uint32_t options;
    uint32_t attributeLength;
    uint32_t eventCount;
} IOHIDSystemQueueElementHeader;
#pragma pack(pop)

_Static_assert(sizeof(IOHIDEventBase) == 16, "unexpected IOHID event base layout");
_Static_assert(sizeof(IOHIDFluidTouchGestureData) == 40, "unexpected IOHID gesture layout");
_Static_assert(sizeof(IOHIDVelocityEventData) == 28, "unexpected IOHID velocity layout");
_Static_assert(sizeof(IOHIDSystemQueueElementHeader) == 28, "unexpected IOHID queue header layout");

static int32_t fixed1616(double value) {
    int32_t result = (int32_t)(value * 65536.0);
    if (result == 0 && value != 0.0) return value > 0.0 ? 1 : -1;
    return result;
}

static uint8_t *make_hid_payload(CGEventRef event, size_t *outLength) {
    const CGEventField phaseField = (CGEventField)kCGEventGesturePhase;
    const CGEventField motionField = (CGEventField)kCGEventGestureSwipeMotion;
    const CGEventField progressField = (CGEventField)kCGEventGestureSwipeProgress;
    const CGEventField velocityXField = (CGEventField)kCGEventGestureSwipeVelocityX;
    const CGEventField velocityYField = (CGEventField)kCGEventGestureSwipeVelocityY;
    const CGEventField positionXField = (CGEventField)kCGEventGestureSwipePositionX;

    const int64_t phase = CGEventGetIntegerValueField(event, phaseField);
    const int64_t motion = CGEventGetIntegerValueField(event, motionField);
    const double progress = CGEventGetDoubleValueField(event, progressField);
    const double positionX = CGEventGetDoubleValueField(event, positionXField);
    const double velocityX = CGEventGetDoubleValueField(event, velocityXField);
    const double velocityY = CGEventGetDoubleValueField(event, velocityYField);
    const bool includeVelocity = velocityX != 0.0 || velocityY != 0.0 || phase == kGestureEnded;
    const uint32_t eventCount = includeVelocity ? 2 : 1;
    size_t length = sizeof(IOHIDSystemQueueElementHeader) + sizeof(IOHIDFluidTouchGestureData);
    if (includeVelocity) length += sizeof(IOHIDVelocityEventData);

    uint8_t *payload = calloc(1, length);
    if (!payload) return NULL;

    IOHIDSystemQueueElementHeader *header = (IOHIDSystemQueueElementHeader *)payload;
    uint64_t timestamp = CGEventGetTimestamp(event);
    header->timestamp = timestamp ? timestamp : mach_absolute_time();
    header->eventCount = eventCount;

    IOHIDFluidTouchGestureData *fluid = (IOHIDFluidTouchGestureData *)
        (payload + sizeof(IOHIDSystemQueueElementHeader));
    fluid->base.size = sizeof(IOHIDFluidTouchGestureData);
    fluid->base.type = kIOHIDEventTypeFluidTouchGesture;
    fluid->base.options = (uint32_t)((phase & 0xFF) << 24);
    fluid->positionX = fixed1616(positionX);
    fluid->gestureMotion = (uint16_t)motion;
    fluid->gestureFlavor = kIOHIDGestureFlavorDockPrimary;
    fluid->swipeProgress = fixed1616(progress);

    if (includeVelocity) {
        IOHIDVelocityEventData *velocity = (IOHIDVelocityEventData *)
            (payload + sizeof(IOHIDSystemQueueElementHeader) + sizeof(IOHIDFluidTouchGestureData));
        velocity->base.size = sizeof(IOHIDVelocityEventData);
        velocity->base.type = kIOHIDEventTypeVelocity;
        velocity->base.depth = 1;
        velocity->velocityX = fixed1616(velocityX);
        velocity->velocityY = fixed1616(velocityY);
    }

    *outLength = length;
    return payload;
}

static CGEventRef add_hid_payload(CGEventRef event) {
    CFDataRef serialized = CGEventCreateData(kCFAllocatorDefault, event);
    if (!serialized) return NULL;
    const uint8_t *bytes = CFDataGetBytePtr(serialized);
    const CFIndex length = CFDataGetLength(serialized);
    if (length < 4 || bytes[0] != 0 || bytes[1] != 0 || bytes[2] != 0 || bytes[3] != 2) {
        CFRelease(serialized);
        return NULL;
    }

    size_t payloadLength = 0;
    uint8_t *payload = make_hid_payload(event, &payloadLength);
    if (!payload || payloadLength > UINT16_MAX || kCGEventRawIOHIDPayload > UINT16_MAX) {
        free(payload);
        CFRelease(serialized);
        return NULL;
    }

    const size_t newLength = (size_t)length + 4 + payloadLength;
    uint8_t *newBytes = malloc(newLength);
    if (!newBytes) {
        free(payload);
        CFRelease(serialized);
        return NULL;
    }
    memcpy(newBytes, bytes, (size_t)length);
    newBytes[length] = (uint8_t)(payloadLength >> 8);
    newBytes[length + 1] = (uint8_t)payloadLength;
    newBytes[length + 2] = (uint8_t)(kCGEventRawIOHIDPayload >> 8);
    newBytes[length + 3] = (uint8_t)kCGEventRawIOHIDPayload;
    memcpy(newBytes + length + 4, payload, payloadLength);

    free(payload);
    CFRelease(serialized);
    CFDataRef augmented = CFDataCreate(kCFAllocatorDefault, newBytes, (CFIndex)newLength);
    free(newBytes);
    if (!augmented) return NULL;
    CGEventRef result = CGEventCreateFromData(kCFAllocatorDefault, augmented);
    CFRelease(augmented);
    return result;
}

static CGEventRef make_dock_swipe(int phase, double progress, double velocity) {
    CGEventRef event = CGEventCreate(NULL);
    if (!event) return NULL;
    CGEventSetIntegerValueField(event, (CGEventField)kCGSEventTypeField, kCGSEventDockControl);
    CGEventSetIntegerValueField(event, (CGEventField)kCGEventGestureHIDType, kIOHIDEventTypeDockSwipe);
    CGEventSetIntegerValueField(event, (CGEventField)kCGEventGesturePhase, phase);
    CGEventSetDoubleValueField(event, (CGEventField)kCGEventGestureSwipeProgress, progress);
    CGEventSetIntegerValueField(event, (CGEventField)kCGEventGestureSwipeMotion, kCGGestureMotionHorizontal);
    CGEventSetIntegerValueField(event, (CGEventField)kCGEventGesturePhaseAlias, phase);
    CGEventSetDoubleValueField(event, (CGEventField)kCGEventGestureZoomDeltaY, 3.0);
    CGEventSetDoubleValueField(event, (CGEventField)kCGEventSourceProcessAlias, (double)mach_absolute_time());
    CGEventSetDoubleValueField(event, (CGEventField)kCGEventGestureSwipePositionX, 0.1);
    if (phase == kGestureEnded) {
        CGEventSetDoubleValueField(event, (CGEventField)kCGEventGestureSwipeVelocityX, velocity);
    }
    return event;
}

static bool post_pair(CGEventRef dockEvent) {
    CGEventRef companion = CGEventCreate(NULL);
    if (!companion) {
        CFRelease(dockEvent);
        return false;
    }
    CGEventSetIntegerValueField(companion, (CGEventField)kCGSEventTypeField, kCGSEventGesture);
    CGEventPost(kCGSessionEventTap, dockEvent);
    CGEventPost(kCGSessionEventTap, companion);
    CFRelease(dockEvent);
    CFRelease(companion);
    return true;
}

bool tracepad_space_swipe(int phase, double progress, double velocity) {
    if (phase != kGestureBegan && phase != kGestureChanged &&
        phase != kGestureEnded && phase != kGestureCancelled) return false;
    if (!isfinite(progress) || !isfinite(velocity)) return false;
    CGEventRef raw = make_dock_swipe(phase, progress, velocity);
    if (!raw) return false;
    CGEventRef event = add_hid_payload(raw);
    CFRelease(raw);
    if (!event) return false;
    return post_pair(event);
}

bool tracepad_switch_space(bool toRight) {
    const double progress = toRight ? -1.0 : 1.0;
    const double velocity = toRight ? -9999.0 : 9999.0;
    return tracepad_space_swipe(kGestureBegan, progress, 0.0) &&
           tracepad_space_swipe(kGestureChanged, progress, 0.0) &&
           tracepad_space_swipe(kGestureEnded, progress, velocity);
}
