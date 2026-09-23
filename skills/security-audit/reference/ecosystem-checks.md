# Ecosystem-specific checks

Read only the sections whose manifest/platform actually exists in the audited scope. Detect
by file presence, not by assumption.

## Node.js / TypeScript / NestJS (`package.json` present)

- Guards (`@UseGuards`) and interceptors actually applied to every controller/route that
  touches tenant data — a route missing the module-level guard is a common regression when a
  new controller is added.
- DTOs use `class-validator`/`class-transformer` with `whitelist: true` (or equivalent) so
  extra client-supplied fields are stripped, not silently accepted (mass assignment).
- ORM/query builder calls use parameter binding — flag any raw query built via string
  concatenation or template literals with user input.
- `child_process.exec`/`execSync` with a string built from user input; prefer `execFile`/`spawn`
  with an argv array.
- JWT verification specifies algorithm and audience/issuer explicitly — reject
  `alg: none` and don't trust a client-supplied `kid`/`alg` without validation.
- Dependency lockfile committed and `npm audit`/`pnpm audit` (or equivalent) run in CI if
  configured — note if it exists but isn't gating.

## Go / Fiber (`go.mod` present)

- Middleware chain (`app.Use(...)`) actually wraps every route group that needs auth — check
  route registration order, since Fiber applies middleware only to routes registered after it.
- `context.Context` cancellation propagated into outbound calls (DB, HTTP) so a client
  disconnect doesn't leave orphaned work.
- `fmt.Sprintf` building a SQL string with user input instead of a parameterized query
  (`database/sql` placeholders or the ORM's parameter binding).
- `crypto/rand` (not `math/rand`) for tokens/keys.
- `http.Client` with an explicit `Timeout` set on every outbound call; TLS config without
  `InsecureSkipVerify: true`.

## Docker

- Base image pinned to a digest or specific tag, not `latest`.
- No secrets baked into image layers (`ARG`/`ENV` with a literal credential, or a `COPY` of a
  `.env` file into the image).
- Container doesn't run as root when it doesn't need to (`USER` directive present).

## Kubernetes / Helm (manifests, `values.yaml`, or `.github/workflows` deploying to GKE)

These map directly to Housi's GKE environments (sandbox/homolog share tooling with produção
on `gke-prd-housi-01`, distinguished by namespace — see the `k8s` skill):

- `securityContext.privileged: true` — should essentially never appear.
- `hostPath` volumes, `hostNetwork: true`, or `hostPID: true` — these break namespace
  isolation between services/tenants sharing the cluster.
- `allowPrivilegeEscalation` not explicitly set to `false`.
- `runAsUser: 0` / no `runAsNonRoot: true`.
- Secrets injected as literal `env:` values in the manifest instead of `valueFrom.secretKeyRef`
  or a mounted Secret — literal values leak into `kubectl describe`/`kubectl get -o yaml`
  output and CI logs.
- RBAC `Role`/`ClusterRole` with `resources: ["*"]` or `verbs: ["*"]` broader than the
  workload's actual needs.
- Resource `limits` missing (a single misbehaving pod can starve neighbors on a shared node).
- NetworkPolicy absent where a service handles tenant data and shares a namespace/cluster with
  others.

## GitHub Actions (`.github/workflows/*.yml`)

- `pull_request_target` combined with a checkout of the PR's untrusted head and a step that
  has access to repository secrets.
- Actions referenced by a mutable tag/branch (`@main`, `@v1`) instead of a pinned SHA, for any
  third-party action.
- Workflow `permissions:` broader than the job needs (default `write-all` left unset to something
  narrower).
- Secrets passed to a step that also runs untrusted code (e.g. a lint/build script from a fork
  PR) before that code has been reviewed.

## Keycloak / OIDC (Housi's auth provider)

- Token validation checks `iss` and `aud` explicitly, not just signature validity — a token
  from a different realm/client can otherwise pass signature checks and still be accepted.
- Refresh-token rotation is enabled and old refresh tokens are invalidated on rotation.
- Role/claim mapping from Keycloak roles to internal tenant/permission checks doesn't trust a
  client-supplied claim that Keycloak itself doesn't attest (e.g. a custom header overriding
  the token's role).
- Token expiry is actually enforced service-side, not just relied upon client-side.
- Logout/session revocation actually invalidates the token server-side (not just clears the
  client's local storage) if the flow claims to support it.

## Multi-tenant checks (Housi marketplace model)

- Any query joining across the tenant boundary (e.g. an admin/aggregate report) explicitly
  documents why it's exempt from per-tenant scoping, rather than being an accidental omission.
- Search/index services (Elasticsearch) apply the tenant filter at the query level, not only in
  the UI layer — a direct API call must not be able to bypass it.
- File storage paths (uploads, exports) are namespaced by tenant, and a predictable/sequential
  ID doesn't let one tenant enumerate another's files.
