/*
 * Vendored from musl libc 1.2.5 (src/math/pow_data.h) for AstronomyKit.
 * Externally-visible symbols are prefixed with ak_ so nothing here can
 * collide with or resolve to the host libm at link time. Purpose:
 * bit-identical ephemeris results across operating systems (issue #28).
 * Original musl copyright/attribution comments are preserved below.
 */
/*
 * Copyright (c) 2018, Arm Limited.
 * SPDX-License-Identifier: MIT
 */
#ifndef _POW_DATA_H
#define _POW_DATA_H


#define POW_LOG_TABLE_BITS 7
#define POW_LOG_POLY_ORDER 8
extern const struct pow_log_data {
	double ln2hi;
	double ln2lo;
	double poly[POW_LOG_POLY_ORDER - 1]; /* First coefficient is 1.  */
	/* Note: the pad field is unused, but allows slightly faster indexing.  */
	struct {
		double invc, pad, logc, logctail;
	} tab[1 << POW_LOG_TABLE_BITS];
} ak___pow_log_data;

#endif
