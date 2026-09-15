// SPDX-License-Identifier: GPL-3.0-only
#ifndef TOUCH_BRIDGE_H
#define TOUCH_BRIDGE_H
#include <stdint.h>
#include <stdbool.h>

typedef struct {
    int32_t identifier;
    int32_t state;
    float x, y, pressure;
} FCContact;

typedef void (*FCFrameCallback)(uintptr_t device, const FCContact *contacts, int32_t count, void *context);
typedef void (*FCButtonCallback)(uintptr_t device, bool down, void *context);

// Start/stop are called on the main run loop. Callbacks may arrive on framework threads.
int32_t FCStart(FCFrameCallback frames, FCButtonCallback buttons, void *context);
void FCStop(void);
const char *FCError(void);
int32_t FCDeviceCount(void);
bool FCDevicesHealthy(void);
// Match a HID mouse service to the exact trackpad whose service descends from it.
uintptr_t FCDeviceForHIDService(uint32_t service);
uint64_t FCSenderID(uintptr_t device);
#endif
