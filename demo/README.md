# Local demo data

`fixtures/board_storyboard_v1.json` is a deterministic, synthetic, read-only
projection for reviewing the six-column administration UI before PostgreSQL is
connected. It is not an export of live state, migration evidence, or a source
of domain truth.

The fixture uses the exact `macsad.case-board-view/1` row shape so the frontend
can later replace the demo provider with the PostgreSQL projection without
renaming fields or changing UUID, integer, enum, null, or timestamp formats.
The one closed case deliberately has no live-task fields; presentation code
must map `case_state = closed` to the Closed column explicitly.

The mechanical development gateway may load this file once at startup and
serve its canonical bytes from `GET /api/v1/demo/snapshot`. The route has no
mutation methods, authorization simulation, persistence, workflow decisions,
or fallback data. Invalid data prevents the demo endpoint from starting.

Lifecycle: edit or replace this fixture only with its validator and browser
expectations in the same change. Remove the demo route when the real typed
PostgreSQL read adapter becomes the default local provider.

## Build and inspect on a development workstation

These are temporary foreground workstation commands. On Firebat, Compose is
the sole authority for long-running services; do not launch these processes
beside that stack.

Build deterministic bundles from the pinned clean LOGOS checkout:

```bash
export LOGOS_WORKSPACE=/absolute/path/to/logicaffeine-private
mkdir -p .runtime/local-demo/admin .runtime/local-demo/public
(
  cd logos/admin
  ../../scripts/logos.sh emit wasm-dom \
    --output ../../.runtime/local-demo/admin/macsad_admin.wasm \
    --color never
)
(
  cd logos/public-site
  ../../scripts/logos.sh emit wasm-dom \
    --output ../../.runtime/local-demo/public/macsad_public.wasm \
    --color never
)
```

Run the health-only LOGOS gateway in one terminal:

```bash
export LOGOS_WORKSPACE=/absolute/path/to/logicaffeine-private
cd logos/gateway
../../scripts/logos.sh serve --color never
```

Run the loopback-only admin preview and demo endpoint in another terminal:

```bash
python3 host_adapters/dev_static_gateway.py \
  --root .runtime/local-demo/admin \
  --port 18080 \
  --logos-health-url http://127.0.0.1:18081/api/v1/health \
  --demo-snapshot demo/fixtures/board_storyboard_v1.json
```

The admin UI is at `http://127.0.0.1:18080/`; the exact demo bytes are at
`http://127.0.0.1:18080/api/v1/demo/snapshot`. The current pinned browser host
can fetch text but cannot yet decode and render this structured contract safely,
so the board continues to render its existing hardcoded, visibly labelled
baseline until LOGOS gaps G1 and G11 land.

The public empty-state preview needs no backend:

```bash
python3 -m http.server 18082 \
  --bind 127.0.0.1 \
  --directory .runtime/local-demo/public
```

Open `http://127.0.0.1:18082/macsad_public.html`.

SQLite is intentionally absent. If the projection later becomes too large for
one bounded in-memory document, SQLite may be introduced only as a disposable,
read-only index generated from this same versioned contract. It must never copy
the PostgreSQL domain schema, accept commands, or survive as authoritative
state.
