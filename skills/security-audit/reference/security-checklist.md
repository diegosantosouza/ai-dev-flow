# Security checklist

Twelve areas to walk for every audit, regardless of stack. For each, follow untrusted input
from entry point through validation, authorization, persistence, and logging — verify the
route actually passes through the control you're about to credit, and that failure closes
access rather than opening it.

## 1. Authentication and session

Token creation, validation, expiry, revocation. Replay and fixation resistance. Constant-time
comparison for secrets. Where sessions/tokens are stored (cookie flags, local storage,
server-side cache) and whether they survive logout.

## 2. Authorization and tenant isolation

Deny by default. Every read and write checks object/tenant scope, not just "is authenticated."
Watch for confused-deputy patterns (a service account acting on behalf of a user without
re-checking that user's scope) and mass assignment (a client-supplied field silently changing
an owner/tenant/role field). Check for TOCTOU between an authorization check and the operation
it guards.

## 3. Tenant/data isolation

Every storage key, cache key, search index, and file path that holds tenant data includes the
tenant identity, and a missing or partial identity fails closed rather than falling back to "no
filter." Check for cross-tenant inference through counts, error messages, shared logs, shared
embeddings/search indexes, or background jobs that iterate without a tenant filter.

## 4. Injection

SQL/query construction (parameterized vs. string-built), shell/argument injection, path
traversal, SSRF on any server-side fetch of a user-supplied URL, template injection, header
injection (CRLF, host header trust), deserialization of untrusted data, regex that can
catastrophically backtrack on attacker input.

## 5. Secrets and privacy

No secrets in source, comments, logs, error messages, or client-visible responses. Config and
environment variables that hold secrets aren't echoed into logs or crash dumps. Data retention
and deletion actually removes what it claims to.

## 6. Execution and extensibility

Subprocess calls use an argv array, not a shell string built from input. Any plugin/webhook/
dynamic-loading surface is scoped and can't reach the host filesystem or credentials beyond its
stated purpose.

## 7. Persistence and integrity

Transactions and atomic writes where partial state would be dangerous. Migration rollback path
exists and was actually exercised, not just written. Concurrent writers don't corrupt shared
state. Destructive operations (delete, mass update) have a confirmation or dry-run path.

## 8. Network and web

TLS actually enforced (no `rejectUnauthorized: false` / `InsecureSkipVerify` left from
debugging). CORS is not `*` alongside credentialed requests. CSRF protection where cookies
carry auth. Request size/time limits exist so one client can't exhaust the service. Webhook
signatures are verified, not just "the URL is a secret."

## 9. Cryptography and randomness

Established primitives only — no home-grown crypto. CSPRNG for tokens/keys, never
`Math.random()` or a non-cryptographic Go `math/rand` for anything security-relevant.
Certificate validation isn't disabled anywhere in the call path.

## 10. Availability

Bounded input size, bounded recursion/concurrency, timeouts on every outbound call, rate limits
on public endpoints, retries with backoff (not a tight retry loop that amplifies an outage).

## 11. Supply chain and CI

New dependencies checked for typosquatting, unexpected registries, or a lifecycle/install
script doing more than the package needs. CI workflows: no `pull_request_target` combined with
untrusted checkout and secrets; actions pinned to a SHA or a trusted tag, not a mutable branch;
deploy credentials scoped to what the job actually needs.

## 12. Malicious-code review

Covert network calls, credential discovery/exfiltration, obfuscated or encoded payloads,
conditional/delayed activation, hidden debug/admin bypasses. This applies to test files and
fixtures too — a payload can hide in a test runner or a migration just as easily as in
application code.

## Severity discipline

- Name the exact attacker prerequisites and the realistic exploit path — not just "this could
  be bad."
- A gap already blocked by another enforced layer is `Informational`, not the same severity as
  an unguarded path — state which layer blocks it and why that's sufficient.
- Never let an unresolved "I couldn't check this" become a finding with a severity. It's
  `needs-validation`, full stop.
