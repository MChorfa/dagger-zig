/*
 * dagger.h — C bindings for dagger-zig
 *
 * Stable C ABI for the Dagger programmable CI/CD engine SDK. Any language
 * with a C FFI (Python/cffi, Ruby/FFI, Swift, .NET P/Invoke, LuaJIT,
 * Julia/ccall, Go/cgo, Haskell/FFI, OCaml/ctypes, …) can drive Dagger
 * pipelines via this header.
 *
 * # ABI guarantees
 *
 *   - DAGGER_ABI_VERSION is bumped on every breaking change.
 *   - Opaque struct pointers — callers NEVER dereference them.
 *   - All returned strings are heap-allocated; free with dagger_string_free().
 *   - All functions that can fail return a negative int on error; call
 *     dagger_last_error() (thread-local) to retrieve the message.
 *   - Functions are thread-safe ONLY across different clients. One client
 *     must be used from one thread at a time (matches the Rust/Go SDKs).
 *
 * # Example
 *
 *     #include <dagger.h>
 *     #include <stdio.h>
 *
 *     int main(void) {
 *         DaggerClient *c = dagger_connect();
 *         if (!c) { fprintf(stderr, "%s\n", dagger_last_error()); return 1; }
 *
 *         DaggerContainer *ctr = dagger_query_container(dagger_client_dag(c));
 *         ctr = dagger_container_from(ctr, "alpine:latest");
 *         const char *argv[] = {"echo", "hello from C"};
 *         ctr = dagger_container_with_exec(ctr, argv, 2);
 *
 *         char *out = NULL;
 *         int rc = dagger_container_stdout(ctr, &out);
 *         if (rc < 0) { fprintf(stderr, "%s\n", dagger_last_error()); return 1; }
 *
 *         printf("%s", out);
 *         dagger_string_free(out);
 *         dagger_client_close(c);
 *         return 0;
 *     }
 *
 * # License
 *
 *   Apache-2.0. Copyright 2026 MChorfa Labs / MNChorfa.
 */

#ifndef DAGGER_H
#define DAGGER_H

#ifdef __cplusplus
extern "C"
{
#endif

#include <stddef.h>
#include <stdint.h>

#define DAGGER_ABI_VERSION 1

    /* ── return codes ─────────────────────────────────────────────────────── */

#define DAGGER_OK 0
#define DAGGER_ERR_ALLOC -1
#define DAGGER_ERR_CONNECT -2
#define DAGGER_ERR_TRANSPORT -3
#define DAGGER_ERR_HTTP_STATUS -4
#define DAGGER_ERR_DOMAIN -5
#define DAGGER_ERR_MALFORMED -6
#define DAGGER_ERR_BUILD -7
#define DAGGER_ERR_NULL_ARG -8
#define DAGGER_ERR_SHUTDOWN -9
#define DAGGER_ERR_INTERNAL -99

    /* ── opaque handles ───────────────────────────────────────────────────── */

    typedef struct DaggerClient DaggerClient;
    typedef struct DaggerQuery DaggerQuery;
    typedef struct DaggerContainer DaggerContainer;
    typedef struct DaggerDirectory DaggerDirectory;
    typedef struct DaggerFile DaggerFile;
    typedef struct DaggerSecret DaggerSecret;
    typedef struct DaggerCacheVol DaggerCacheVol;

    /* ── lifecycle ────────────────────────────────────────────────────────── */

    /**
     * Connect to the Dagger engine using default configuration.
     * Returns NULL on failure — check dagger_last_error().
     *
     * The returned client owns all handles derived from it. Calling
     * dagger_client_close() invalidates every derived handle — do not use
     * them afterwards.
     */
    DaggerClient *dagger_connect(void);

    /**
     * Close the client and shut down the session.
     * Safe to call with NULL. Idempotent.
     */
    void dagger_client_close(DaggerClient *client);

    /**
     * Get the root Query handle. Does not allocate; do not free.
     * The returned handle is valid until dagger_client_close().
     */
    DaggerQuery *dagger_client_dag(DaggerClient *client);

    /**
     * Reset the internal arena, reclaiming memory while retaining buffer capacity.
     * Call periodically for long-running clients to prevent unbounded memory growth.
     * Returns DAGGER_OK (0) on success, or DAGGER_ERR_INTERNAL if a query is in progress.
     * Check dagger_last_error() for details on failure.
     */
    int dagger_client_reset_arena(DaggerClient *client);

    /* ── root queries ─────────────────────────────────────────────────────── */

    DaggerContainer *dagger_query_container(DaggerQuery *q);
    DaggerDirectory *dagger_query_directory(DaggerQuery *q);

    /** Load a named cache volume. */
    DaggerCacheVol *dagger_query_cache_volume(DaggerQuery *q, const char *key);

    /** Create a new secret from plaintext. */
    DaggerSecret *dagger_query_set_secret(DaggerQuery *q, const char *name,
                                          const char *plaintext);

    /* ── Container ────────────────────────────────────────────────────────── */

    DaggerContainer *dagger_container_from(DaggerContainer *c, const char *address);
    DaggerContainer *dagger_container_with_workdir(DaggerContainer *c, const char *path);
    DaggerContainer *dagger_container_with_env_variable(DaggerContainer *c,
                                                        const char *name,
                                                        const char *value);

    /**
     * Run a command. argv_len is the length of the argv array.
     * Strings are copied — caller may free immediately after the call returns.
     */
    DaggerContainer *dagger_container_with_exec(DaggerContainer *c,
                                                const char *const *argv,
                                                size_t argv_len);

    DaggerContainer *dagger_container_with_mounted_cache(DaggerContainer *c,
                                                         const char *path,
                                                         DaggerCacheVol *cache);

    /**
     * Capture stdout of the most recent exec.
     * On success, *out points to a NUL-terminated heap string the caller must
     * free with dagger_string_free(). On failure, *out is set to NULL and a
     * negative code is returned.
     */
    int dagger_container_stdout(DaggerContainer *c, char **out);
    int dagger_container_stderr(DaggerContainer *c, char **out);

    /**
     * Force evaluation and return the container's opaque ID.
     * *out is a heap string; free with dagger_string_free().
     */
    int dagger_container_sync(DaggerContainer *c, char **out_id);

    /**
     * Publish the container to a registry. *out_digest is the pushed digest.
     */
    int dagger_container_publish(DaggerContainer *c, const char *address,
                                 char **out_digest);

    /* ── Directory ────────────────────────────────────────────────────────── */

    DaggerFile *dagger_directory_file(DaggerDirectory *d, const char *path);

    /**
     * List entries. *out_entries receives a heap array of heap strings, both
     * null-terminated; *out_len receives the count. Free with
     * dagger_string_array_free(*out_entries, *out_len).
     */
    int dagger_directory_entries(DaggerDirectory *d,
                                 char ***out_entries,
                                 size_t *out_len);

    /* ── File ─────────────────────────────────────────────────────────────── */

    /**
     * Read file contents. *out is a heap string; free with dagger_string_free().
     * Use only for text files; binary content is returned as-is but may not be
     * NUL-terminated safely.
     */
    int dagger_file_contents(DaggerFile *f, char **out);

    /* ── error reporting ──────────────────────────────────────────────────── */

    /**
     * Return the last error message from the calling thread. The string is
     * owned by the SDK and valid until the next SDK call on this thread.
     * Returns "" if no error is set.
     */
    const char *dagger_last_error(void);

    /* ── memory management ────────────────────────────────────────────────── */

    /** Free a string returned by an SDK function. NULL-safe. */
    void dagger_string_free(char *s);

    /** Free an array of strings returned by an SDK function. NULL-safe. */
    void dagger_string_array_free(char **arr, size_t len);

    /* ── metadata ─────────────────────────────────────────────────────────── */

    /** SDK version string, e.g. "0.1.0". Statically allocated; do not free. */
    const char *dagger_sdk_version(void);

    /** Pinned engine version string, e.g. "v0.20.6". */
    const char *dagger_engine_version(void);

    /** ABI version — compare against DAGGER_ABI_VERSION at compile time. */
    int dagger_abi_version(void);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* DAGGER_H */
