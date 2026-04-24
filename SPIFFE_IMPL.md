# dagger-zig SPIFFE Workload API — v0.1.1 Implementation Spec

> **Status.** This document specifies the pure-Zig Workload API client that
> lands in v0.1.1 as `NativeWorkloadAPISource`. v0.1.0 ships the type
> surface and the `ShelloutSource` backend; no user-code changes needed
> to upgrade.

## 1. Scope

The native backend implements the SPIFFE Workload API subset needed for
Dagger-driven workloads:

| RPC              | Direction     | v0.1.1 | v0.2  |
| :--------------- | :------------ | :----: | :---: |
| FetchX509SVID    | server-stream |   ✅    |   —   |
| FetchX509Bundles | server-stream |   ✅    |   —   |
| FetchJWTSVID     | unary         |   ✅    |   —   |
| FetchJWTBundles  | server-stream |   —    |   ✅   |
| ValidateJWTSVID  | unary         |   —    |   ✅   |

Federation (multi-trust-domain bundles) is out of scope until v0.2.

## 2. Protocol layering

```
┌──────────────────────────────────────┐
│  NativeWorkloadAPISource (facade)    │  src/spiffe/native.zig
├──────────────────────────────────────┤
│  WorkloadAPI (RPC dispatch)          │  src/spiffe/workload_api.zig
├──────────────────────────────────────┤
│  gRPC client (length-prefix framing) │  src/spiffe/grpc.zig
├──────────────────────────────────────┤
│  HTTP/2 subset                       │  src/spiffe/h2.zig
├──────────────────────────────────────┤
│  Unix domain socket (std.Io.net)     │  std.Io
└──────────────────────────────────────┘
```

Each layer is testable in isolation against the layer below. The top three
layers live in dagger-zig; HTTP/2 framing is custom because Zig 0.16's
`std.http.Client` does not expose its HTTP/2 primitives as a public API,
and gRPC requires HTTP/2 (not HTTP/1.1).

## 3. HTTP/2 subset (`h2.zig`)

We implement the **minimum HTTP/2 needed for gRPC-over-UDS**. Not a
conformant general-purpose HTTP/2 client.

### 3.1 Connection preface

On connect, client sends exactly:

```
PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n
```

(24 bytes; ASCII constant, defined in `h2.zig` as `preface_bytes`.)

### 3.2 Frames we send

| Type          | Code | Notes                                       |
| ------------- | ---- | ------------------------------------------- |
| SETTINGS      | 0x4  | Empty frame + ACK of server's SETTINGS      |
| HEADERS       | 0x1  | END_HEADERS set; CONTINUATION not supported |
| DATA          | 0x0  | END_STREAM on the last frame of a request   |
| WINDOW_UPDATE | 0x8  | Flow control; connection + stream scope     |
| PING          | 0x6  | Keepalive + ACK on receipt                  |
| GOAWAY        | 0x7  | On client shutdown                          |

### 3.3 Frames we receive

Same set plus:

- RST_STREAM (0x3) — surface as `error.StreamClosed`
- PUSH_PROMISE (0x5) — reject with PROTOCOL_ERROR (gRPC disallows push)
- CONTINUATION (0x9) — reject initially; v0.2 if needed

Unknown frame types: ignored (per RFC 7540 §5.5).

### 3.4 HPACK

Full HPACK is complex; for gRPC-over-UDS we only need:

- Static table (61 entries, hardcoded in Zig)
- Literal header representation WITHOUT indexing (opcode 0x0)
- No dynamic table maintenance needed — we send the same ~5 headers on
  every request, and the server's dynamic table updates are parsed but
  not required for correctness.

Required request headers (HPACK-encoded):

```
:method          POST
:scheme          http
:authority       localhost
:path            /SpiffeWorkloadAPI/FetchX509SVID  (per RPC)
content-type     application/grpc
te               trailers
workload.spiffe.io  true          (required "security" header)
user-agent       grpc-zig/0.1.1 dagger-zig
```

Note: `workload.spiffe.io: true` is the well-known SPIFFE security header
that tells the SPIRE agent this call is not a misrouted request. Absence
is rejected by compliant agents.

### 3.5 Flow control

Default window = 65535 bytes. We advertise a larger window
(1 MiB) via SETTINGS after the preface. Server's X.509-SVID responses are
typically 2–8 KiB; JWT-SVIDs are ~1 KiB. Flow control rarely bites.

On stream close, we send WINDOW_UPDATE only for the connection; per-stream
updates are unnecessary because streams are short-lived.

## 4. gRPC framing (`grpc.zig`)

Every gRPC request body (and each response frame in a stream) is a
sequence of **length-prefixed messages**:

```
  ┌───┬──────┬────────────────────────┐
  │ c │  L   │   payload (L bytes)    │
  └───┴──────┴────────────────────────┘
   1B   4B           (protobuf)
```

- `c` is the compression flag (1 byte). Always 0 — we do not implement gzip.
- `L` is message length, big-endian uint32.
- Payload is a protobuf-encoded message.

Stream termination uses HTTP/2 trailers containing gRPC status:

```bash
grpc-status: 0          (OK) or non-zero code
grpc-message: ...       (human text on failure)
```

Error code mapping (RFC-standard + our error set):

| grpc-status | Meaning           | Zig error                 |
| ----------- | ----------------- | ------------------------- |
| 0           | OK                | (no error)                |
| 1           | Canceled          | error.Canceled            |
| 2, 13       | Unknown, Internal | error.TransportError      |
| 3           | InvalidArgument   | error.ProtocolError       |
| 5           | NotFound          | error.NoSvidAvailable     |
| 7           | PermissionDenied  | error.TrustDomainMismatch |
| 14          | Unavailable       | error.SocketUnreachable   |
| 16          | Unauthenticated   | error.NoSvidAvailable     |
| others      |                   | error.TransportError      |

## 5. Protobuf codec (`pb.zig`)

Hand-transcribed from
[workload.proto](https://github.com/spiffe/spiffe/blob/main/proto/spiffe/workload/workload.proto).

We implement only the 9 message types the Workload API uses. No runtime
reflection; each message has a hand-written encoder and decoder.

### 5.1 Wire format primitives

- Varints (little-endian, MSB continuation bit)
- Zigzag encoding for sint32/sint64 (not used by Workload API)
- Length-delimited fields (tag + varint length + bytes)
- Fixed64 for timestamps (not used)

### 5.2 Messages we implement

```proto
message X509SVIDRequest {}

message X509SVIDResponse {
  repeated X509SVID svids               = 1;  // tag 1, length-delimited
  repeated bytes    crl                 = 2;  // ignored in v0.1.1
  map<string, bytes> federated_bundles  = 3;  // ignored in v0.1.1
}

message X509SVID {
  string spiffe_id  = 1;
  bytes  x509_svid  = 2;  // concatenated DER leaf + intermediates
  bytes  x509_svid_key = 3;  // PKCS#8 DER
  bytes  bundle     = 4;  // concatenated DER CA certs for the trust domain
  int64  hint       = 5;  // ignored
}

message JWTSVIDRequest {
  repeated string audience = 1;
  string spiffe_id         = 2;  // optional, selects a specific identity
}

message JWTSVIDResponse {
  repeated JWTSVID svids = 1;
}

message JWTSVID {
  string spiffe_id = 1;
  string svid      = 2;  // the JWT
  int64  hint      = 3;  // ignored
}

message X509BundlesRequest {}

message X509BundlesResponse {
  map<string, bytes> bundles = 1;  // trust_domain -> concatenated DER CA certs
  repeated bytes crl         = 2;  // ignored in v0.1.1
}

message JWTBundlesRequest {}   // v0.2
message JWTBundlesResponse {}  // v0.2
```

### 5.3 Encoder/decoder contract

```zig
// Each message type T provides:
fn T.encode(self: T, writer: *std.Io.Writer) !void;
fn T.decode(allocator: std.mem.Allocator, bytes: []const u8) !T;
fn T.deinit(self: *T, allocator: std.mem.Allocator) void;
```

Fuzz target: `zig build fuzz-pb` (v0.1.2) — the decoder on random bytes
must never crash, only return `error.ProtocolError`.

## 6. X.509 handling

The Workload API returns cert chains as concatenated DER:

```bash
x509_svid = DER(leaf) || DER(intermediate_1) || ... || DER(intermediate_n)
```

There is no length prefix between certs — we parse one DER structure at a
time using `std.crypto.Certificate`, advancing the offset by the parsed
length. The X.509 DER wrapper is `SEQUENCE { ... }`, so the leading byte
is 0x30, followed by a length-of-length or short-form length that lets us
compute the total cert length without parsing fields.

Private keys are PKCS#8 DER; parsed via `std.crypto.Certificate.parsePkcs8Key`
(if exposed in 0.16 stdlib; else via a ~50-line fallback for RSA and
ECDSA-P256 only — the two key types SPIRE agents issue).

Expiry: extracted from the leaf's `notAfter` field. SPIFFE spec allows a
leaf validity of up to 24 hours; typical SPIRE deployments use 1 hour.
`X509SVID.expires_at_unix` is this field converted to Unix seconds.

## 7. Trust domain enforcement

After parsing each SVID, we compare its SPIFFE ID's trust domain against
`options.expected_trust_domain`:

```zig
if options.expected_trust_domain != null and
   parsed_svid.trust_domain != options.expected_trust_domain:
   return error.TrustDomainMismatch
```

This catches the misconfigured-agent attack and is documented in the
API docs as "always set in production."

## 8. Streaming semantics

`FetchX509SVID` returns a stream. The SPIRE agent sends one response
immediately (the current SVID) and then sends an updated response on
every rotation.

`watchX509SVID` returns a `Future<X509SVID>` resolving to the **next**
message. The common pattern in user code:

```zig
var fut = try src.watchX509SVID(io, gpa);
defer _ = fut.cancel(io) catch {};  // always cancel on function exit

while (true) {
    const next_svid = fut.await(io) catch |e| switch (e) {
        error.Canceled => return,
        else => return e,
    };
    defer next_svid.deinit();
    current_svid = next_svid;

    // Re-arm by requesting another future on the same stream
    fut = try src.watchX509SVID(io, gpa);
}
```

Under the hood, `watchX509SVID` maintains a persistent gRPC stream and
issues a new `Future` for each received message. Stream loss surfaces as
`error.StreamClosed` on the next await; callers reconnect at their
discretion.

## 9. Test-vector layout

`tests/fixtures/spiffe/`:

```bash
fixtures/spiffe/
├── x509_svid_response_simple.bin    captured bytes from real SPIRE agent
├── x509_svid_response_simple.json   decoded expected value
├── x509_svid_response_chain_3.bin   3-cert chain case
├── x509_svid_response_chain_3.json
├── jwt_svid_response_audience_1.bin
├── jwt_svid_response_audience_1.json
├── jwt_svid_response_audiences_3.bin
├── jwt_svid_response_audiences_3.json
├── x509_bundle_response_simple.bin
├── x509_bundle_response_simple.json
└── README.md  (how captures were generated)
```

Each `.bin` is a raw byte buffer suitable for feeding into the decoder.
Each `.json` is the canonical decoded form. Every time we change the
decoder, we re-run fixtures to catch regressions.

Capture procedure (also in `tests/fixtures/spiffe/README.md`):

```bash
# Requires a running SPIRE agent on /tmp/spire-agent.sock
socat -v UNIX-LISTEN:/tmp/intercept.sock,fork UNIX-CONNECT:/tmp/spire-agent.sock \
  2>capture.log
# Then run any SPIFFE client pointing at /tmp/intercept.sock
# The frames in capture.log are what we commit.
```

## 10. Performance budget

| Operation            | Target latency     | Notes                               |
| -------------------- | ------------------ | ----------------------------------- |
| fetchX509SVID (cold) | < 20 ms            | Includes socket connect + handshake |
| fetchX509SVID (warm) | < 5 ms             | Reuses connection                   |
| watchX509SVID await  | ~rotation interval | Blocks on stream; no polling        |
| fetchJWTSVID         | < 10 ms            | Unary, warm connection              |

The shellout backend clocks ~50–100 ms cold (subprocess fork + spire-agent
startup), which is why native exists.

## 11. Open questions for v0.1.1 implementation

1. **HTTP/2 CONTINUATION frames.** If an agent's response headers exceed
   our frame size limit, we need CONTINUATION. Observed never in SPIRE
   but allowed by the spec. v0.1.1 will reject; v0.2 supports.
2. **Cert-chain length limit.** SPIRE bundles can be large (tens of CAs
   in federation deployments). We cap bundle responses at 1 MiB; larger
   fails. Bump if users hit this.
3. **RSA key parsing.** `std.crypto` in 0.16 may or may not have RSA-PKCS8
   support; need to verify. If absent, we hand-write it (~60 LOC). ECDSA
   is the default for SPIRE and is definitely supported.
4. **HPACK dynamic table.** Correctness doesn't require maintenance, but
   the agent may reference dynamic-table indices in its responses. We
   parse and track; cost is ~100 LOC.

## 12. Security considerations

- **Socket permissions.** SPIRE agents chmod the socket to 0660; we do not
  re-chmod. If the caller can't open the socket, we surface
  `error.SocketUnreachable` — the user's deployment is misconfigured.
- **No session-token fallback.** If SPIFFE is enabled, it's the *only*
  auth; we never fall back to basic auth. A failed fetch is a hard error.
- **Trust-domain pinning.** `expected_trust_domain` is strongly encouraged
  in production. The docs make this explicit, and the
  `dagger-zig-ssdlc` reference CI sets it.
- **No credential logging.** SVID contents never go through `std.debug.print`
  or the configured `Logger`. X.509 private keys are held as opaque `[]u8`
  slices and zeroed on `X509SVID.deinit` (implementation detail: TODO in
  v0.1.1, document in v0.1.0).
- **Wire-format fuzzing.** `zig build fuzz-spiffe` runs the decoder on
  arbitrary bytes. Target: zero crashes. v0.1.2 adds corpora from
  AFL-captured sessions.

## 13. Migration checklist (v0.1.0 → v0.1.1)

From a caller's perspective:

1. Bump `dagger-zig` dependency version.
2. Optionally swap `ShelloutSource` for `NativeWorkloadAPISource` —
   purely a performance optimization, interface is identical.
3. `JWTSVID` operations that returned `error.NotImplementedInV010` in
   v0.1.0 now return live results.
4. `watchX509SVID` no longer polls — updates arrive on rotation.

No Zig types change. No function signatures change. No error set changes
(we reserve the right to add *new* errors to `SpiffeError`; no removals).
