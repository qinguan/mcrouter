/**
 *  Copyright (c) 2014, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 */
#ifndef FB_MEMCACHE_MC_UMBRELLA_PROTOCOL_H
#define FB_MEMCACHE_MC_UMBRELLA_PROTOCOL_H

#include <stdint.h>
#include <sys/types.h>

#include "mcrouter/lib/fbi/decls.h"
#include "mcrouter/lib/mc/msg.h"

__BEGIN_DECLS

/**
 *
 * Umbrella parsing (bytes on wire -> mc_msg_t)
 *
 */

typedef struct um_parser_s um_parser_t;

/**
 * Initializes an umbrella parser. Returns 0 on success, -1 on error.
 */
int um_parser_init(um_parser_t* um_parser);

/**
 * Frees the parser's internal structures if needed and resets the parser
 * to initial state, ready to be used again. Returns 0 on success, -1 on error.
 */
int um_parser_reset(um_parser_t* um_parser);

// a '}' looks like an umbrella on it's side, obviously
#define ENTRY_LIST_MAGIC_BYTE '}'

/**
 * First byte on a connection decides if it's an Umbrella stream.
 * Returns 1 if 'first_byte' is the Umbrella magic byte.
 */
static inline int um_is_umbrella_stream(const char first_byte) {
  return first_byte == ENTRY_LIST_MAGIC_BYTE;
}

/**
 * Consumes bytes from 'buf' until either a full message is read or
 * 'nbuf' bytes were consumed. If no full message was read, buffers the bytes
 * internally for future calls.
 *
 * *reqid_out will contain the request id of the incoming message.
 * The pointer to the newly created message will be stored in *msg_out
 * (the ownership is passed to the caller).  If no full message was read
 * or an error occurred, *msg_out will be set to NULL.
 *
 * Makes a copy of any needed data, so the buffer doesn't have to be alive
 * after this call.
 *
 * Returns the number of bytes consumed or -1 on error (with errno set).
 */
ssize_t um_consume_one_message(um_parser_t* um_parser,
                               const uint8_t* buf, size_t nbuf,
                               uint64_t* reqid_out,
                               mc_msg_t** msg_out);

typedef enum um_status_e {
  um_ok,
  um_not_umbrella_message,
  um_not_enough_data,
  um_header_parse_error,
  um_invalid_range,
  um_message_parse_error,
} um_status_t;

/**
 * header_size + body_size == message_size
 */
typedef struct um_message_info_s {
  size_t message_size;

  /* Header contains the message info and the array of entry tag/types */
  size_t header_size;

  /* Body of the message contains the strings */
  size_t body_size;
} um_message_info_t;

/**
 * Attempts to figure out header_size and body_size from the
 * (possibly incomplete) message stored in [buf, buf + nbuf).
 *
 * Returns um_ok if info_out was filled out successfully.
 */
um_status_t um_parse_header(const uint8_t* buf, size_t nbuf,
                            um_message_info_t* info_out);

/**
 * Parses the message from the concatenation of
 * [header, header+nheader), [body, body+nbody).
 *
 * Guarantees to not allocate any dynamic memory and not move any data.
 *
 * Allows body of the message to be read from a different buffer,
 * for example you might want to allocate a buffer dynamically based
 * on the size reported by um_parse_header().
 *
 * msg_out must point to a valid mc_msg_t and will be filled out with
 * correct values.  Note that msg_out might point into the provided buffers
 * for key and value strings.
 *
 * Return value:
 *  - um_not_enough_data if nheader < size of header
 *  - um_header_parse_error if header could not be parsed
 *  - um_invalid_range if (nheader == header_size && nbody == body_size &&
 *      nheader + nbody == message_size) is false.
 *  - um_message_parse_error if contents of the message could not be parsed
 */
um_status_t um_consume_no_copy(const uint8_t* header, size_t nheader,
                               const uint8_t* body, size_t nbody,
                               uint64_t* reqid_out,
                               mc_msg_t* msg_out);

typedef void (msg_ready_cb)(void* context, uint64_t reqid, mc_msg_t* msg);

/**
 * Consumes 'nbuf' bytes from 'buf'.  Will call msg_ready callback on every
 * completed umbrella message.
 *
 * This is a convenience method and is equivalent to calling
 * um_consume_one_message() repeatedly until 'nbuf' bytes were consumed.
 *
 * Returns 0 on success, -1 on errors (with errno set).
 */
int um_consume_buffer(um_parser_t* um_parser,
                      const uint8_t* buf, size_t nbuf,
                      msg_ready_cb* msg_ready,
                      void* context);


/**
 *
 * Umbrella serialization (mc_msg_t -> bytes on wire)
 *
 */

typedef struct um_backing_msg_s um_backing_msg_t;

/**
 * Serialize the 'msg' into Umbrella bytes on the wire.
 *
 * Use um_write_iovs() if you have a pre-allocated array of iovs.
 * Use um_emit_iovs() if you want to process each iov one by one.
 *
 * Both versions make use of a backing message struct that
 * must be initialized with um_backing_msg_init() and cleaned up after the call
 * to um_backing_msg_cleanup(). The iovs cannot be used after cleanup().
 * The backing message will maintain a reference to 'msg' as long as it's alive.
 *
 * The methods return -1 on error (with errno set).
 */

int um_backing_msg_init(um_backing_msg_t* bmsg);

void um_backing_msg_cleanup(um_backing_msg_t* bmsg);

/**
 * Return number of iovs used or -1 on error.
 *
 * Note: The caller must ensure that value_iovs are alive while accessing the
 * iovs generated by this function
 */
ssize_t um_write_iovs_extended(um_backing_msg_t* bmsg,
                               uint64_t reqid,
                               mc_msg_t* msg,
                               struct iovec* value_iovs,
                               size_t n_value_iovs,
                               struct iovec* iovs,
                               size_t n_iovs);

static inline
ssize_t um_write_iovs(um_backing_msg_t* bmsg,
                      uint64_t reqid,
                      mc_msg_t* msg,
                      struct iovec* iovs,
                      size_t n_iovs) {
  return um_write_iovs_extended(bmsg, reqid, msg, NULL, 0, iovs, n_iovs);
}

/**
 * um_emit_iovs calls this function on every new iov ready to be transmitted.
 * The return value must be 0 on success and non-zero on any errors.
 */
typedef int (emit_iov_cb)(void* context, const void *buf, size_t len);

/**
 * Note: The caller must ensure that value_iovs are alive while accessing the
 * iovs generated by this function
 */
int um_emit_iovs_extended(um_backing_msg_t* bmsg,
                          uint64_t reqid,
                          mc_msg_t* msg,
                          struct iovec* value_iovs,
                          size_t n_value_iovs,
                          emit_iov_cb* emit_iov,
                          void* context);

static inline
int um_emit_iovs(um_backing_msg_t* bmsg,
                 uint64_t reqid,
                 mc_msg_t* msg,
                 emit_iov_cb* emit_iov,
                 void* context) {
  return um_emit_iovs_extended(bmsg, reqid, msg, NULL, 0, emit_iov, context);
}


__END_DECLS


#endif
