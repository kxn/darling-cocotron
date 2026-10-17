/* SPDX-License-Identifier: GPL-3.0-or-later
 * This file is part of Darling.
 * Copyright (C) 2026 Darling contributors.
 *
 * Client-side Core Animation render-server debug-option query. This does not
 * create a rendering service. A missing service or failed RPC returns false.
 */
#include <QuartzCore/CARenderServer.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mig.h>
#include <mach/mig_errors.h>
#include <mach/ndr.h>
#include <servers/bootstrap.h>
#include <stddef.h>
#include <stdint.h>

enum {
    CA_GET_DEBUG_OPTION = 40256,
    CA_GET_DEBUG_OPTION_REPLY = CA_GET_DEBUG_OPTION + 100,
    CA_SET_DEBUG_OPTION = 40257,
    CA_COPY_STATISTICS = 40231,
};

struct ca_debug_request {
    mach_msg_header_t head;
    NDR_record_t ndr;
    uint32_t option;
};
struct ca_debug_reply {
    mach_msg_header_t head;
    NDR_record_t ndr;
    kern_return_t result;
    uint32_t enabled;
};
union ca_debug_message {
    struct ca_debug_request request;
    struct ca_debug_reply reply;
    unsigned char receive_buffer[48];
};
_Static_assert(sizeof(struct ca_debug_request) == 36, "CA request wire layout");
_Static_assert(sizeof(struct ca_debug_reply) == 40, "CA reply wire layout");
_Static_assert(offsetof(struct ca_debug_reply, result) == 32, "CA result wire layout");

bool CARenderServerGetDebugOption(mach_port_t server, unsigned int option)
{
    bool own_server = false;
    if (server == MACH_PORT_NULL) {
        kern_return_t lookup = bootstrap_look_up(bootstrap_port,
                "com.apple.CARenderServer", &server);
        if (lookup != KERN_SUCCESS || !MACH_PORT_VALID(server))
            return false;
        own_server = true;
    }

    union ca_debug_message message = {0};
    mach_port_t reply_port = mig_get_reply_port();
    message.request.head.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND,
            MACH_MSG_TYPE_MAKE_SEND_ONCE);
    message.request.head.msgh_size = sizeof(message.request);
    message.request.head.msgh_remote_port = server;
    message.request.head.msgh_local_port = reply_port;
    message.request.head.msgh_id = CA_GET_DEBUG_OPTION;
    message.request.ndr = NDR_record;
    message.request.option = option;
    voucher_mach_msg_set(&message.request.head);

    kern_return_t status = mach_msg(&message.request.head,
            MACH_SEND_MSG | MACH_RCV_MSG, sizeof(message.request),
            sizeof(message.receive_buffer), reply_port, MACH_MSG_TIMEOUT_NONE,
            MACH_PORT_NULL);
    bool enabled = false;
    if (status != MACH_MSG_SUCCESS) {
        // Keep the cached receive port for send errors which never queued a
        // request. Other failures invalidate the MIG reply-port cache.
        if (status == MACH_SEND_INVALID_DATA || status == MACH_SEND_INVALID_DEST
                || status == MACH_SEND_INVALID_HEADER)
            mig_put_reply_port(reply_port);
        else
            mig_dealloc_reply_port(reply_port);
    } else {
        struct ca_debug_reply *reply = &message.reply;
        bool valid = !(reply->head.msgh_bits & MACH_MSGH_BITS_COMPLEX)
                && reply->head.msgh_id == CA_GET_DEBUG_OPTION_REPLY
                && reply->head.msgh_remote_port == MACH_PORT_NULL
                && reply->head.msgh_size == sizeof(*reply)
                && reply->result == KERN_SUCCESS;
        if (valid)
            enabled = reply->enabled != 0;
        else
            mach_msg_destroy(&reply->head);
    }

    if (own_server)
        mach_port_deallocate(mach_task_self(), server);
    return enabled;
}

static mach_port_t ca_acquire_server(mach_port_t server)
{
    if (server != MACH_PORT_NULL)
        return server;
    if (bootstrap_look_up(bootstrap_port, "com.apple.CARenderServer", &server)
            != KERN_SUCCESS || !MACH_PORT_VALID(server))
        return MACH_PORT_NULL;
    return server;
}

static kern_return_t ca_exchange(mach_msg_header_t *message,
        mach_msg_size_t send_size, mach_msg_size_t receive_size)
{
    mach_port_t reply_port = mig_get_reply_port();
    message->msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND,
            MACH_MSG_TYPE_MAKE_SEND_ONCE);
    message->msgh_size = send_size;
    message->msgh_local_port = reply_port;
    voucher_mach_msg_set(message);
    kern_return_t result = mach_msg(message, MACH_SEND_MSG | MACH_RCV_MSG,
            send_size, receive_size, reply_port, MACH_MSG_TIMEOUT_NONE,
            MACH_PORT_NULL);
    if (result != MACH_MSG_SUCCESS) {
        if (result == MACH_SEND_INVALID_DATA || result == MACH_SEND_INVALID_DEST
                || result == MACH_SEND_INVALID_HEADER)
            mig_put_reply_port(reply_port);
        else
            mig_dealloc_reply_port(reply_port);
    }
    return result;
}

void CARenderServerSetDebugOption(mach_port_t requested_server,
        unsigned int option, bool enabled)
{
    mach_port_t server = ca_acquire_server(requested_server);
    if (server == MACH_PORT_NULL)
        return;
    union {
        struct {
            struct ca_debug_request query;
            uint32_t enabled;
        } request;
        mig_reply_error_t reply;
        unsigned char receive_buffer[44];
    } message = {0};
    _Static_assert(sizeof(message.request) == 40, "CA set option request");
    message.request.query.head.msgh_remote_port = server;
    message.request.query.head.msgh_id = CA_SET_DEBUG_OPTION;
    message.request.query.ndr = NDR_record;
    message.request.query.option = option;
    message.request.enabled = enabled;
    if (ca_exchange(&message.request.query.head, sizeof(message.request),
                sizeof(message.receive_buffer)) == MACH_MSG_SUCCESS) {
        if ((message.reply.Head.msgh_bits & MACH_MSGH_BITS_COMPLEX)
                || message.reply.Head.msgh_id != CA_SET_DEBUG_OPTION + 100
                || message.reply.Head.msgh_remote_port != MACH_PORT_NULL
                || message.reply.Head.msgh_size != sizeof(message.reply)
                || message.reply.RetCode != KERN_SUCCESS)
            mach_msg_destroy(&message.reply.Head);
    }
    if (requested_server == MACH_PORT_NULL)
        mach_port_deallocate(mach_task_self(), server);
}

static CFPropertyListRef ca_copy_statistics(mach_port_t requested_server)
{
    mach_port_t server = ca_acquire_server(requested_server);
    if (server == MACH_PORT_NULL)
        return NULL;
    union {
        struct ca_debug_request request;
        struct {
            mach_msg_header_t head;
            mach_msg_body_t body;
            mach_msg_ool_descriptor_t data;
            NDR_record_t ndr;
            uint32_t count;
        } reply;
        unsigned char receive_buffer[64];
    } message = {0};
    _Static_assert(sizeof(message.reply) == 56, "CA statistics reply");
    _Static_assert(offsetof(typeof(message.reply), data) == 28,
            "CA statistics OOL offset");
    _Static_assert(offsetof(typeof(message.reply), count) == 52,
            "CA statistics count offset");
    message.request.head.msgh_remote_port = server;
    message.request.head.msgh_id = CA_COPY_STATISTICS;
    message.request.ndr = NDR_record;
    // The native frame-counter path requests the complete statistics array.
    message.request.option = 0;
    kern_return_t result = ca_exchange(&message.request.head,
            sizeof(message.request), sizeof(message.receive_buffer));
    if (requested_server == MACH_PORT_NULL)
        mach_port_deallocate(mach_task_self(), server);
    if (result != MACH_MSG_SUCCESS)
        return NULL;
    bool valid = (message.reply.head.msgh_bits & MACH_MSGH_BITS_COMPLEX)
            && message.reply.head.msgh_id == CA_COPY_STATISTICS + 100
            && message.reply.head.msgh_remote_port == MACH_PORT_NULL
            && message.reply.head.msgh_size == sizeof(message.reply)
            && message.reply.body.msgh_descriptor_count == 1
            && message.reply.data.type == MACH_MSG_OOL_DESCRIPTOR
            && message.reply.data.size == message.reply.count;
    if (!valid) {
        mach_msg_destroy(&message.reply.head);
        return NULL;
    }
    CFDataRef data = CFDataCreate(kCFAllocatorDefault, message.reply.data.address,
            message.reply.count);
    vm_deallocate(mach_task_self(), (vm_address_t)message.reply.data.address,
            message.reply.data.size);
    if (data == NULL)
        return NULL;
    CFPropertyListRef statistics = CFPropertyListCreateWithData(
            kCFAllocatorDefault, data, kCFPropertyListImmutable, NULL, NULL);
    CFRelease(data);
    return statistics;
}

uint32_t CARenderServerGetFrameCounter(mach_port_t server)
{
    CFPropertyListRef statistics = ca_copy_statistics(server);
    if (statistics == NULL)
        return 0;
    uint32_t count = 0;
    if (CFGetTypeID(statistics) == CFArrayGetTypeID()
            && CFArrayGetCount(statistics) > 0) {
        CFTypeRef display = CFArrayGetValueAtIndex(statistics, 0);
        if (display != NULL && CFGetTypeID(display) == CFDictionaryGetTypeID()) {
            CFTypeRef value = CFDictionaryGetValue(display,
                    CFSTR("kCADisplayFrameCount"));
            if (value != NULL) {
                if (CFGetTypeID(value) == CFBooleanGetTypeID())
                    count = CFBooleanGetValue(value) ? 1 : 0;
                else if (CFGetTypeID(value) == CFNumberGetTypeID())
                    CFNumberGetValue(value, kCFNumberSInt32Type, &count);
            }
        }
    }
    CFRelease(statistics);
    return count;
}
