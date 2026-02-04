# Task007 - UID/GID migration (Deferred)

## Status
Deferred by product decision for now.

## Why deferred
We are intentionally leaving ownership behavior to Docker/current startup behavior in this iteration.

## Known limitation to document
An image committed by one UID/GID and restored/run by another UID/GID may cause permission issues in `/home/coder`.

## Future implementation intent
When resumed, implement marker-based ownership migration in `booth-entry` with targeted UID/GID reassignment and clear user messaging.

## Exit criteria for re-activation
- Decision to support cross-user restore reliably.
- Agreed performance/safety policy for ownership changes.
