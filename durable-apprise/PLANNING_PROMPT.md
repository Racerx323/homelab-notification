# Generic durable Apprise framework planning prompt

Use this prompt to define the generic framework before implementation.

```text
Plan—but do not implement—a generic durable Apprise notification framework in:

/home/aaron/code/homelab-notification/durable-apprise

Use the repository rules in:

/home/aaron/code/AGENTS.md
/home/aaron/code/homelab-notification/AGENTS.md

The framework is derived from the accepted Caddy/DNS durable notification
architecture, but it is an independent homelab-notification project. Do not
modify, deploy, rename, or replace the current Caddy/DNS implementation. Do not
contact the Caddy/DNS HA nodes or the Apprise API host. Do not expose endpoint
credentials, configuration contents, notification URLs, authorization headers,
or retained payloads.

First audit the current generic repository and the following read-only source
contracts:

- homelab-server-configs/Caddy/docs/APPRISE_DELIVERY.md
- homelab-server-configs/Caddy/scripts/caddy-apprise-enqueue.sh
- homelab-server-configs/Caddy/scripts/caddy-apprise-delivery-worker.sh
- homelab-server-configs/Caddy/systemd/caddy-apprise-worker.service
- homelab-server-configs/Caddy/systemd/caddy-apprise-worker.path
- homelab-server-configs/Caddy/systemd/caddy-apprise-worker.timer
- homelab-server-configs/Caddy/configs/tmpfiles.d/caddy-ha.conf
- homelab-server-configs/Caddy/tests/durable-apprise-queue-regression.sh
- homelab-dns/Keepalived/scripts/keepalived-notify.sh
- homelab-dns/Keepalived/docs/keepalived-dual-stack-runbook.md

Separate reusable mechanics from Caddy/DNS integration. The ownership boundary
must be:

- homelab-notification owns the generic queue schema, enqueue helper, delivery
  worker, administrative tool, systemd units, tmpfiles contract, installer,
  uninstaller, tests, and reusable documentation;
- homelab-server-configs owns Caddy integration, production pins and
  inventories, Caddy producers, and Caddy-specific operator procedures;
- homelab-dns owns Keepalived/DNS producers, producer transition
  acknowledgement state, and DNS-specific notification content.

Plan this package layout:

durable-apprise/
├── README.md
├── docs/
│   ├── ARCHITECTURE.md
│   ├── OPERATIONS.md
│   ├── PRODUCER_INTEGRATION.md
│   └── SECURITY.md
├── scripts/
│   ├── durable-apprise-enqueue
│   ├── durable-apprise-worker
│   └── durable-apprise-admin
├── systemd/
│   ├── durable-apprise-worker.service
│   ├── durable-apprise-worker.path
│   └── durable-apprise-worker.timer
├── tmpfiles.d/
│   └── durable-apprise.conf
├── config/
│   └── durable-apprise.conf.example
├── install.sh
├── uninstall.sh
└── tests/

The plan must specify:

- a neutral versioned schema such as durable-apprise-queue/v1;
- configurable endpoint, Apprise configuration key, queue and runtime paths,
  service identity, retry limits, and bounded producer/application allowlists;
- bounded structured and raw payload interfaces with strict UTF-8, control
  character, size, key, path, schema, and secret-like-content validation;
- atomic same-filesystem enqueue and a stable producer-supplied identity for
  every durable transition;
- explicit separation between producer-local enqueue retry and worker-owned
  network delivery retry;
- pending, inflight, delivered-receipt, and dead-letter states that survive
  reboot;
- exclusive worker locking, oldest-eligible-first delivery, bounded
  exponential backoff, deterministic jitter, maximum attempts, and exact
  journald events;
- at-least-once delivery semantics and the post-request, pre-receipt crash
  ambiguity;
- Idempotency-Key as best-effort endpoint input, not an exactly-once or
  duplicate-suppression guarantee;
- safe read-only queue inspection and explicit validated dead-letter replay;
- receipt retention, disk-capacity limits, disk-exhaustion behavior, queue
  health, schema upgrades, and incompatible-version rejection;
- ordinary uninstall that preserves queue evidence and a separate explicitly
  destructive purge operation;
- hardened systemd identities, filesystem permissions, namespace and syscall
  restrictions, network-family limits, boot persistence, and path-plus-timer
  activation;
- non-recursive handling of notification-delivery failure;
- an installation and upgrade model suitable for unrelated applications and
  servers without assuming the user pi, Caddy paths, DNS, VRRP, or HA.

Tests must execute the real generic entrypoints and cover:

- atomic enqueue, stable identity, deduplication, malformed input, unsafe
  paths, symlinks, permissions, oversized records, secrets, and schema drift;
- producer acknowledgement and local enqueue retry without fabricating queue
  success;
- worker crash before request, during request, after remote acceptance, and
  before receipt commit;
- inflight recovery, receipt reconciliation, retry scheduling, jitter,
  maximum-attempt dead-lettering, and safe replay;
- SIGTERM and timeout handling with no child or temporary-file residue;
- reboot recovery, simultaneous path/timer activation, lock contention, disk
  exhaustion, receipt retention, and incompatible upgrades;
- exact systemd and tmpfiles contracts in a network-disabled Debian test
  environment;
- rejection of fabricated command, request, response, queue, receipt,
  dead-letter, or success evidence.

The plan must include migration boundaries but must not authorize migration.
Publish and validate the generic framework independently first. Any future
Caddy/DNS adoption is a separately reviewed and authorized project in which
those repositories pin exact generic framework versions while retaining their
integration-specific producers and production inventories.

Deliver an implementation-ready plan containing architecture, state machines,
schemas, configuration and security contracts, package ownership, test matrix,
installation and rollback design, compatibility policy, phased implementation,
acceptance criteria, and unresolved decisions. Identify any conflict or
technically unsound requirement and request operator input rather than making
an assumption.

Stop after planning and repository-only validation. Do not implement the
framework, send a notification, contact a production host, or change another
repository.
```

After the generic framework is implemented and released, use
[CONTAINER_UPDATE_PILOT_PROMPT.md](CONTAINER_UPDATE_PILOT_PROMPT.md) to plan its
first production pilot without weakening the generic ownership boundary.
