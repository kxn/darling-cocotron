/* SPDX-License-Identifier: GPL-3.0-or-later
 * This file is part of Darling.
 * Copyright (C) 2026 Darling contributors.
 */
#ifndef DARLING_CA_RENDER_SERVER_H
#define DARLING_CA_RENDER_SERVER_H

#include <stdbool.h>
#include <stdint.h>
#include <mach/mach.h>

#ifdef __cplusplus
extern "C" {
#endif

bool CARenderServerGetDebugOption(mach_port_t server, unsigned int option);
void CARenderServerSetDebugOption(mach_port_t server, unsigned int option, bool enabled);
uint32_t CARenderServerGetFrameCounter(mach_port_t server);

#ifdef __cplusplus
}
#endif
#endif
