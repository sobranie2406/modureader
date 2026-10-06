# WebDAV request policy

## Jianguoyun

Identify the parsed hostname `jianguoyun.com` or its subdomains, not URL
substrings. The first automatic sync uses the existing two-second start gate.
Subsequent automatic sync starts are at least ten minutes apart; triggers in
that interval coalesce. Manual sync bypasses this interval, not server cooldown.
Leaving the foreground, disabling automatic sync or changing accounts cancels
the applicability of a pending start. Local records remain durable.

All outbound requests (including authentication retries) share a conservative
480-request rolling 30-minute budget per device/account. Reservations are
serialized and saved before transport. Cached local OPTIONS responses consume
no quota. The application stores the last automatic start, reservations and
server cooldown in device-local application support, using a hashed account
filename with no passwords, URLs or book contents. Temporary-file replacement
avoids partial policy writes. Manual sync and restart do not reset the budget.

Negative conditional-write capability results are cached for thirty minutes
on Jianguoyun (thirty seconds elsewhere). Positive results are still verified
before a later sync uses conditional writes. No consistency checks or immutable
log verification passes are removed.

## All WebDAV servers

After successful Basic authentication, redundant per-file OPTIONS probes reuse
the successful result for five minutes within that client. Explicit ping is
always sent; Digest and anonymous authentication retain their probes. Account
changes and permission failures invalidate the probe hint. GET/PUT permissions,
conditional writes, metadata rereads and checksums are never skipped.

HTTP 429 and 503 open a shared, per-account circuit breaker across WebDAV client
instances. New requests, including manual actions, are rejected locally until
the cooldown expires. Requests already in flight are not cancelled or replayed.
Preflight and bookshelf status queries do not immediately retry these statuses.

Without a longer `Retry-After`, fallback cooldown starts at five minutes for
Jianguoyun and one minute elsewhere, doubling on later failed bursts to thirty
minutes. Both delta-seconds and HTTP-date hints are supported. A successful
in-flight response cannot clear a cooldown set by another request.

Concurrent standalone bookshelf status queries share only their in-flight file
listing. During a full sync, book/cover listings are reused only within that
run. Changed local/merged file references invalidate the affected directory;
successful uploads and exact-path checks update the hint. Final status refresh
uses that hint without an extra listing. The next sync always starts fresh.
Database and record-log listings are never cached by this mechanism.
Servers other than Jianguoyun retain the existing normal sync frequency.

Old replaced-file reclamation is checked at most every six hours per endpoint
and account after a successful sync. A failed attempt waits one hour. The device
stores the maintenance schedule in a local file (hashed endpoint identity, no
credentials), so restarting does not reset it. Publication, replacement backup
verification and fresh concurrent-reference checks remain unchanged. This does
not throttle the separate, safety-critical journal merge/compaction protocol.

## Boundaries and follow-up work

The budget is device-local, not a global account coordinator: other devices and
applications can still exhaust the server limit. Large syncs stop before the
local budget is exceeded and retain unacknowledged changes for later retry.
Ordinary WebDAV servers have no local request quota or ten-minute interval, but
their server cooldown is also persisted. Never infer an unchanged log directory
from a database ETag alone. Clearing application storage resets local policy.

Default tests use fake clocks and a local HTTP WebDAV server. Coverage includes
domain spoofing, account isolation, ordinary server timing, Retry-After,
cross-client request blocking, concurrent budget reservations, restart recovery,
Basic/Digest/anonymous authentication, conditional writes and new-device discovery.
The explicit opt-in Jianguoyun live test uses a fresh isolated folder and synthetic
data; it never writes to the production library. It bounds outbound requests and
stops on 429/503 rather than deliberately exhausting a real account's allowance.
