#ifndef TRACEPAD_DOCK_SWIPE_H
#define TRACEPAD_DOCK_SWIPE_H

#include <stdbool.h>

/// Synthesizes one phase of a continuous horizontal Dock swipe.
/// Progress is signed and cumulative; velocity is applied only at gesture end.
bool tracepad_space_swipe(int phase, double progress, double velocity);

/// Legacy one-shot switch retained for older protocol events.
bool tracepad_switch_space(bool toRight);

#endif
