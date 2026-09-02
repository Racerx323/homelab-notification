# Durable Apprise container-update pilot prompt

Use this prompt only after the generic durable Apprise framework has been
implemented, independently validated, and assigned an exact release version.

```text
Plan—but do not deploy—the first production pilot of the generic durable
Apprise framework for container update notifications in:

/home/aaron/code/homelab-notification/durable-apprise
/home/aaron/code/homelab-notification/apprise-api

Use the repository rules in:

/home/aaron/code/AGENTS.md
/home/aaron/code/homelab-notification/AGENTS.md

The pilot replaces only the direct network-delivery step in
apprise-api/scripts/notify-container-updates.sh. Keep the weekly read-only
registry comparison, exact-digest manual update authorization, systemd
lifecycle ownership, lifecycle lock, notification state machine, and updater
rollback policy unchanged. Do not enable Podman auto-update.

The target flow is:

container update checker
    -> generic durable enqueue helper
    -> persistent pending queue
    -> generic delivery worker
    -> local Apprise API

Use producer `container-update-check` and application
`notification-infrastructure`. Add that producer/application pair through the
generic framework's bounded configurable allowlist; do not weaken validation
or add a wildcard. Every queued event must use the generic versioned schema and
an identity derived from the host, container, event class, and candidate
platform digest. The identity must be stable for the same observation and must
change when the candidate digest changes.

Map the existing notification transitions into durable events:

- first pending digest: warning;
- unchanged pending digest after the reminder interval: warning reminder;
- changed candidate digest: new warning;
- pending or failed comparison becoming current: recovery;
- registry/comparison failure: failure;
- initial and unchanged current state: journal only, no queue record.

Each record must contain bounded, validated fields for source, application,
event, severity, host, affected container, running image ID, candidate platform
digest, an operator evidence command, and the repository lifecycle guide. It
must not contain notification URLs, authorization headers, Apprise persistent
configuration contents, response bodies, registry credentials, environment
contents, or other secrets. The enqueue result, queue record, worker receipt,
and journal must never claim network delivery before the worker records remote
acceptance.

The checker becomes a producer and must not call Apprise API directly. A local
enqueue failure must leave the prior notification acknowledgement state
unchanged, return a failed service result, and use bounded producer-local retry.
Network retry, inflight recovery, delivered receipts, and dead-letter handling
belong exclusively to the generic durable worker. Delivery failure must remain
non-recursive.

Keep the queue and receipts on J1-SVMF persistent across service restarts and
host reboots. This protects against an Apprise outage or ordinary reboot, but
not loss of the host or filesystem. Record Uptime Kuma as a future external
health-monitoring project; do not implement or deploy it in this pilot.

Acceptance must execute the real packaged entrypoints and prove:

1. an all-current check creates no record;
2. a pending digest creates one valid queue record with the expected identity;
3. repeating the same check before the reminder interval does not duplicate it;
4. changing the digest creates a distinct warning;
5. stopping Apprise API does not lose a successfully enqueued record;
6. reboot/inflight recovery preserves the pending record;
7. restarting Apprise API causes eventual delivery and a durable receipt;
8. the post-request, pre-receipt ambiguity remains documented as at-least-once;
9. malformed, oversized, secret-like, or unallowlisted records fail closed;
10. the authorized exact-digest updater and checker cannot overlap because the
    existing lifecycle lock still applies;
11. disabling the pilot restores the direct-notification package without
    deleting queue, receipt, dead-letter, or prior notification-state evidence.

Produce an implementation-ready pilot plan, exact version pins, file-level
change list, migration and rollback transactions, test matrix, sanitized
acceptance evidence schema, and a separate production deployment bundle.
Identify any conflict with the released generic framework and stop for operator
input rather than changing its schema or security boundary ad hoc.

Stop after planning and repository-only validation. Do not install systemd
units, enqueue production events, send notifications, contact J1-SVMF, or
mutate any running container. Installation, recurring execution, test
notifications, failure injection, reboot, and rollback each require explicit
reviewed production authorization.
```
