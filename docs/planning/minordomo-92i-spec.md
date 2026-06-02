# Implementation Spec: Fix check-usage.py 403 (minordomo-92i)

## Background

`shared/check-usage.py` calls `https://api.anthropic.com/api/oauth/usage` with a Bearer token
and `anthropic-beta: oauth-2025-04-20` header. It consistently receives a 403 response. Because
the script currently only logs the HTTP status code (not the response body) and fails open, the
root cause is unknown and the usage gate is never enforced.

The user asked that we "test different theories and ensure a working query before fully
implementing a solution." The approach here is to embed theory-testing directly in the production
code: the script tries multiple authentication header combinations in sequence, uses the first
that succeeds, and logs all attempts' full response bodies when all fail. This means the "research
phase" runs in the live environment against the real API — the most reliable way to find what works.

---

## Stage 1: Embed multi-approach auth with full diagnostics

### Description

Rewrite the HTTP request logic in `shared/check-usage.py` to:

1. **Log full response bodies on failure.** `urllib.error.HTTPError` exposes `.read()`. Capture
   and include it in the warning so Jenkins build logs show exactly why auth failed.

2. **Try auth approaches in sequence.** On a 4xx response, retry with the next approach before
   giving up. Defined approaches (tried in order):
   - **Approach A** (current): `Authorization: Bearer <token>` + `anthropic-beta: oauth-2025-04-20`
   - **Approach B**: `Authorization: Bearer <token>` (no beta header)
   - **Approach C**: `Authorization: Bearer <token>` + `anthropic-version: 2023-06-01` (no beta header)
   - **Approach D**: `Authorization: Bearer <token>` + `anthropic-version: 2023-06-01` + `anthropic-beta: oauth-2025-04-20`

3. **Use the first successful approach.** Log which approach index succeeded.

4. **If all approaches fail, fail-open with full diagnostics.** The warning should include each
   approach's HTTP status code AND response body, so the next build log contains everything
   needed to understand the failure.

5. **Network errors (non-HTTP) still fail-open immediately** (no point retrying connection
   failures with different headers).

The overall fail-open contract is preserved: if no approach succeeds, the script exits 0 and
Majordomo proceeds. The fix is purely in how the script responds to auth failures.

### Acceptance Criteria

- When approach A succeeds (status 200), the script exits with current behavior (compare
  utilization vs threshold, exit 0 or 1, log JSON).
- When approach A returns a 4xx, the script retries with approach B, C, D in order.
- When any approach succeeds after a retry, the output JSON includes a `"auth_approach"` field
  indicating which approach index (0-based) worked.
- When all approaches fail with 4xx responses, the script exits 0 (fail-open) with a warning
  that includes each attempt's status code and response body text.
- When the server returns a non-4xx HTTP error (e.g. 503), the script fails open immediately
  without retrying other approaches (server errors are not auth errors).
- Existing bats tests in `test/bats/check-usage.bats` all pass.
- New bats tests cover:
  - Approach A fails with 403, approach B succeeds → correct result returned, `auth_approach: 1`
    in output
  - All approaches fail with 403 → fail-open, warning includes response body text from each attempt
  - A 503 from approach A → fail-open immediately (no retry), warning includes body
- `make test` passes (shellcheck + bats).
