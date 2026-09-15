#include "TouchBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stddef.h>
#include <pthread.h>
#include <stdio.h>

// ABI declarations, checked against the framework in macOS 27.0 (26A428).
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } Vector;
typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier, state, fingerID, handID;
    Vector normalized;
    float total, pressure, angle, majorAxis, minorAxis;
    Vector absolute;
    int32_t field14, field15;
    float density;
} RawTouch;
_Static_assert(sizeof(RawTouch) == 96, "Multitouch contact ABI size");
_Static_assert(offsetof(RawTouch, normalized) == 32, "Multitouch position ABI offset");

typedef void *Device;
typedef void (*RawFrameCallback)(Device, RawTouch *, int32_t, double, int32_t);
typedef void (*RawButtonCallback)(Device, uint32_t, uint32_t, void *);
static CFArrayRef (*createList)(void);
static bool (*isOpaque)(Device);
static bool (*isRunning)(Device);
static bool (*registerFrame)(Device, RawFrameCallback);
static bool (*unregisterFrame)(Device, RawFrameCallback);
static bool (*registerButton)(Device, RawButtonCallback, void *);
static bool (*unregisterButton)(Device, RawButtonCallback);
static void (*startDevice)(Device, int32_t);
static void (*stopDevice)(Device);
static void *framework;
static CFArrayRef deviceList;
static Device activeDevices[16];
static int32_t activeCount;
static FCFrameCallback frameSink;
static FCButtonCallback buttonSink;
static void *sinkContext;
static pthread_mutex_t sinkLock = PTHREAD_MUTEX_INITIALIZER;
static char errorText[256];

static void onFrame(Device device, RawTouch *touches, int32_t count, double timestamp, int32_t frame) {
    (void)timestamp; (void)frame;
    if (count < 0 || count > 32 || (count > 0 && !touches)) return;
    FCContact copied[32];
    for (int32_t i = 0; i < count; i++) {
        copied[i] = (FCContact){ touches[i].identifier, touches[i].state,
            touches[i].normalized.position.x, touches[i].normalized.position.y, touches[i].pressure };
    }
    pthread_mutex_lock(&sinkLock);
    if (frameSink) frameSink((uintptr_t)device, copied, count, sinkContext);
    pthread_mutex_unlock(&sinkLock);
}

// macOS 27 disassembly: registration takes (device, callback, refcon), callback receives
// (device, newButtonMask, previousButtonMask, refcon). This is physical button state.
static void onButton(Device device, uint32_t current, uint32_t previous, void *context) {
    (void)context;
    if ((current != 0) == (previous != 0)) return;
    pthread_mutex_lock(&sinkLock);
    if (buttonSink) buttonSink((uintptr_t)device, current != 0, sinkContext);
    pthread_mutex_unlock(&sinkLock);
}

static bool loadFramework(void) {
    if (!framework) framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL);
    if (!framework) { snprintf(errorText, sizeof(errorText), "无法加载系统触摸板接口"); return false; }
#define LOAD(variable, symbol) do { *(void **)(&variable) = dlsym(framework, symbol); \
    if (!variable) { snprintf(errorText, sizeof(errorText), "缺少系统接口：%s", symbol); return false; } } while (0)
    LOAD(createList, "MTDeviceCreateList");
    LOAD(isOpaque, "MTDeviceIsOpaqueSurface");
    LOAD(isRunning, "MTDeviceIsRunning");
    LOAD(registerFrame, "MTRegisterContactFrameCallback");
    LOAD(unregisterFrame, "MTUnregisterContactFrameCallback");
    LOAD(registerButton, "MTRegisterButtonStateCallback");
    LOAD(unregisterButton, "MTUnregisterButtonStateCallback");
    LOAD(startDevice, "MTDeviceStart");
    LOAD(stopDevice, "MTDeviceStop");
#undef LOAD
    return true;
}

int32_t FCStart(FCFrameCallback frames, FCButtonCallback buttons, void *context) {
    FCStop();
    errorText[0] = 0;
    if (!loadFramework()) return -1;
    deviceList = createList();
    if (!deviceList) { snprintf(errorText, sizeof(errorText), "未找到触摸板"); return 0; }
    pthread_mutex_lock(&sinkLock);
    frameSink = frames; buttonSink = buttons; sinkContext = context;
    pthread_mutex_unlock(&sinkLock);
    for (CFIndex i = 0; i < CFArrayGetCount(deviceList) && activeCount < 16; i++) {
        Device device = (Device)CFArrayGetValueAtIndex(deviceList, i);
        if (!device || !isOpaque(device)) continue; // Exclude Magic Mouse and non-trackpad surfaces.
        if (!registerFrame(device, onFrame)) continue;
        if (!registerButton(device, onButton, NULL)) { unregisterFrame(device, onFrame); continue; }
        startDevice(device, 0);
        if (isRunning(device)) { activeDevices[activeCount++] = device; }
        else { unregisterFrame(device, onFrame); unregisterButton(device, onButton); stopDevice(device); }
    }
    if (!activeCount) snprintf(errorText, sizeof(errorText), "无法启动触摸板，请检查输入监控权限并重新连接触摸板");
    return activeCount;
}

void FCStop(void) {
    pthread_mutex_lock(&sinkLock);
    frameSink = NULL; buttonSink = NULL; sinkContext = NULL;
    pthread_mutex_unlock(&sinkLock);
    for (int32_t i = 0; i < activeCount; i++) {
        unregisterFrame(activeDevices[i], onFrame);
        unregisterButton(activeDevices[i], onButton);
        stopDevice(activeDevices[i]);
    }
    activeCount = 0;
    if (deviceList) { CFRelease(deviceList); deviceList = NULL; }
}
const char *FCError(void) { return errorText; }
int32_t FCDeviceCount(void) { return activeCount; }
