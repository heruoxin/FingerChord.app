// SPDX-License-Identifier: GPL-3.0-only
#ifndef TOUCH_BRIDGE_H
#define TOUCH_BRIDGE_H
#include <stdint.h>
#include <stdbool.h>

typedef struct {
    int32_t identifier;
    float x, y;
} FCContact;

typedef void (*FCFrameCallback)(uintptr_t device, const FCContact *contacts, int32_t count, void *context);
typedef void (*FCButtonCallback)(uintptr_t device, bool down, void *context);

// Start/stop are called on the main run loop. Callbacks may arrive on framework threads.
// Frames carry touching contacts only. Without streaming, a count of one or zero is skipped
// once it has held for 300 ms.
int32_t FCStart(FCFrameCallback frames, FCButtonCallback buttons, void *context);
void FCStop(void);
void FCSetStreaming(bool streaming);
const char *FCError(void);
bool FCDevicesHealthy(void);
// Match a HID mouse service to the exact trackpad whose service descends from it.
uintptr_t FCDeviceForHIDService(uint32_t service);
uint64_t FCSenderID(uintptr_t device);
#endif
