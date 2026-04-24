//! SPIFFE-specific error sets. Separate from dagger-core errors so callers
//! can match narrowly.

pub const SpiffeError = error{
    // Parsing
    EmptyId,
    IdTooLong,
    BadScheme,
    EmptyTrustDomain,
    TrustDomainTooLong,
    InvalidTrustDomainChar,
    EmptyPathSegment,
    InvalidPathSegment,
    InvalidPathChar,

    // Transport (Workload API)
    SocketUnreachable,
    HandshakeFailed,
    StreamClosed,
    TransportError,
    ProtocolError, // unexpected HTTP/2 or gRPC frame
    Canceled,

    // Semantic
    NoSvidAvailable, // agent returned empty SVID list
    TrustDomainMismatch, // expected_trust_domain check failed
    SvidExpired, // SVID presented has already expired
    InvalidCertChain, // DER parse failure
    InvalidKey,

    // Lifecycle
    AlreadyClosed,
    NotInitialized,

    // v0.1.0 placeholder — removed in v0.1.1
    NotImplementedInV010,

    // Allocation
    OutOfMemory,
};
