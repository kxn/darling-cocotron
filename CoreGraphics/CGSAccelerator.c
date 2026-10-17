/* SPDX-License-Identifier: GPL-3.0-or-later
 * This file is part of Darling.
 * Copyright (C) 2026 Darling contributors.
 */
#include <CoreGraphics/CGDisplayConfiguration.h>
#include <CoreGraphics/CGError.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/graphics/IOGraphicsLib.h>
#include <pthread.h>
#include <stdlib.h>

/* Like the native client, retain the accelerator in a process-local cache.
 * The output is borrowed; repeated queries do not create extra send rights.
 * Holding the framebuffer right also keeps its port name from being reused
 * for a different device while it remains a cache key.
 */
struct cgs_accelerator_entry {
    io_service_t framebuffer;
    io_service_t accelerator;
    uint32_t framebuffer_index;
    struct cgs_accelerator_entry *next;
};
static pthread_mutex_t accelerator_lock = PTHREAD_MUTEX_INITIALIZER;
static struct cgs_accelerator_entry *accelerators;

CGError CGSAcceleratorForDisplayNumber(CGDirectDisplayID display,
        io_service_t *accelerator, uint32_t *framebuffer_index)
{
    if (accelerator != NULL)
        *accelerator = MACH_PORT_NULL;
    if (framebuffer_index != NULL)
        *framebuffer_index = 0;
    if (accelerator == NULL || framebuffer_index == NULL)
        return kCGErrorIllegalArgument;

    io_service_t framebuffer = CGDisplayIOServicePort(display);
    if (!MACH_PORT_VALID(framebuffer))
        return kCGErrorFailure;

    pthread_mutex_lock(&accelerator_lock);
    for (struct cgs_accelerator_entry *entry = accelerators; entry;
            entry = entry->next) {
        if (entry->framebuffer == framebuffer) {
            *accelerator = entry->accelerator;
            *framebuffer_index = entry->framebuffer_index;
            IOObjectRelease(framebuffer);
            pthread_mutex_unlock(&accelerator_lock);
            return kCGErrorSuccess;
        }
    }

    io_service_t found = MACH_PORT_NULL;
    uint32_t index = 0;
    IOReturn result = IOAccelFindAccelerator(framebuffer, &found, &index);
    struct cgs_accelerator_entry *entry = NULL;
    if (result == kIOReturnSuccess && MACH_PORT_VALID(found))
        entry = malloc(sizeof(*entry));
    if (entry == NULL) {
        if (MACH_PORT_VALID(found))
            IOObjectRelease(found);
        IOObjectRelease(framebuffer);
        pthread_mutex_unlock(&accelerator_lock);
        return kCGErrorFailure;
    }
    *entry = (struct cgs_accelerator_entry) {
        .framebuffer = framebuffer,
        .accelerator = found,
        .framebuffer_index = index,
        .next = accelerators,
    };
    accelerators = entry;
    *accelerator = found;
    *framebuffer_index = index;
    pthread_mutex_unlock(&accelerator_lock);
    return kCGErrorSuccess;
}

__attribute__((destructor))
static void cgs_release_accelerators(void)
{
    pthread_mutex_lock(&accelerator_lock);
    while (accelerators != NULL) {
        struct cgs_accelerator_entry *entry = accelerators;
        accelerators = entry->next;
        IOObjectRelease(entry->accelerator);
        IOObjectRelease(entry->framebuffer);
        free(entry);
    }
    pthread_mutex_unlock(&accelerator_lock);
}
