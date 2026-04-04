# Cloud Account Administration Workflows

> **Stub document.** Most workflows below are placeholders documenting expected
> SaaS account-management operations that do not yet have tooling. The only
> workflow currently implemented is API key reset via direct database access.
> As the internal admin dashboard is built out (ct-885), each stub should be
> replaced with the supported workflow and its UI/CLI entry point.
>
> See also: `build/docs/operations/qa-accounts.csv` for the QA account registry.

## Prerequisites

- SSH access to the production server: `ssh deploy@174.138.94.110`
- Docker Compose project at `/opt/contextify-cloud` on the server
- Containers: `contextify-cloud-api-1` (FastAPI app), `contextify-cloud-db-1` (PostgreSQL)

---

## 1. API Key Reset (lost key recovery)

**Status:** Manual SSH method only. No admin UI or CLI.

When a user loses their only API key, there is no self-service recovery path.
The rotate endpoint (`POST /api/v1/auth/api-keys/{id}/rotate`) requires
authenticating with the current key, and the web dashboard login also requires
a valid key. Direct database access is the only option.

### Procedure

1. Identify the user and tenant from `qa-accounts.csv` or the database:

   ```
   USER_ID="<user uuid>"
   TENANT_ID="<tenant uuid>"
   OLD_KEY_ID="<16-hex key_id prefix from qa-accounts.csv>"
   ```

2. SSH into the production server and exec into the API container:

   ```bash
   ssh deploy@174.138.94.110
   cd /opt/contextify-cloud
   docker compose exec api python -c "
   import asyncio, secrets, bcrypt
   from sqlalchemy import text
   from contextify_cloud.database import engine

   key_id = secrets.token_hex(8)
   secret = secrets.token_hex(12)
   full_key = f'ctx_{key_id}_{secret}'
   key_hash = bcrypt.hashpw(secret.encode(), bcrypt.gensalt()).decode()
   key_prefix = f'ctx_{key_id[:8]}...'

   async def reset():
       async with engine.begin() as conn:
           result = await conn.execute(text(
               'UPDATE api_keys SET revoked_at = NOW() '
               'WHERE key_id = :old AND revoked_at IS NULL'
           ), {'old': '$OLD_KEY_ID'})
           print(f'Revoked: {result.rowcount}')

           await conn.execute(text(
               'INSERT INTO api_keys '
               '(id, user_id, tenant_id, key_id, key_hash, key_prefix, name, scopes, created_at) '
               'VALUES (gen_random_uuid(), :uid, :tid, :kid, :kh, :kp, :name, ARRAY[\"sync\",\"search\"], NOW())'
           ), {
               'uid': '$USER_ID', 'tid': '$TENANT_ID',
               'kid': key_id, 'kh': key_hash, 'kp': key_prefix,
               'name': 'Reset Key',
           })

           row = await conn.execute(text(
               'SELECT key_id, key_prefix FROM api_keys WHERE key_id = :kid'
           ), {'kid': key_id})
           r = row.fetchone()
           print(f'New key in DB: {r[0]} ({r[1]})')

       print(f'FULL KEY: {full_key}')

   asyncio.run(reset())
   "
   ```

3. Verify the new key authenticates:

   ```bash
   curl -s -H "Authorization: Bearer <new-full-key>" \
     https://cloud.contextify.sh/api/v1/sync/status
   ```

4. Update `build/docs/operations/qa-accounts.csv` with the new `api_key_id` if this is a QA account.

5. Communicate the new key to the user through a secure channel. The full key is shown exactly once and is never stored in plaintext on the server.

### Key files

- Key generation: `contextify_cloud/middleware/auth.py` (`generate_api_key`, `hash_api_key`)
- ApiKey model: `contextify_cloud/models.py` (table `api_keys`)
- Database session: `contextify_cloud/database.py`

---

## 2. Create New Tenant

**Status:** Stub. No admin tooling.

Expected workflow: provision a new tenant with owner account and initial API key.

Current paths:
- Web registration at `/cloud/register` (disabled in production by default, requires `ENABLE_REGISTRATION=true`)
- API endpoint `POST /api/v1/auth/register`
- Both require registration to be enabled

<!-- TODO: Admin endpoint or CLI to create tenants without enabling public registration -->

---

## 3. Create New User on Existing Tenant

**Status:** Stub. No admin tooling.

Expected workflow: add a user to an existing tenant with a specified role.

Current paths:
- Invitation flow via `POST /api/v1/invitations` or web dashboard team page
- Requires an authenticated owner/admin on the tenant

<!-- TODO: Admin endpoint to add users directly without invitation flow -->

---

## 4. Change User Role

**Status:** Stub. Tenant-scoped only.

Expected workflow: change a user's role within their tenant.

Current path:
- `PUT /api/v1/team/members/{user_id}/role` (requires owner/admin auth on the tenant)
- Web dashboard team page

<!-- TODO: Cross-tenant admin role changes -->

---

## 5. Suspend / Unsuspend Tenant

**Status:** Stub. No admin tooling.

Expected workflow: temporarily disable a tenant's access without data deletion.

Current state:
- Tenant `status` field supports `active`, `deletion_scheduled`, `purge_in_progress`
- No "suspended" status exists
- `tenant_guard.py` checks status on mutating endpoints

<!-- TODO: Add suspended status, admin endpoint to toggle -->

---

## 6. Suspend / Unsuspend Individual User

**Status:** Stub. No admin tooling.

Expected workflow: disable a specific user's access while keeping the tenant active.

Current state:
- No user-level suspension field exists in the User model
- API keys can be individually revoked, which effectively disables access

<!-- TODO: User-level suspension flag, admin endpoint -->

---

## 7. Delete Tenant (with grace period)

**Status:** Partially implemented. Tenant-initiated only.

Current paths:
- `POST /api/v1/tenant/delete` (owner only, sets `deletion_scheduled`)
- `POST /api/v1/tenant/cancel-deletion` (owner only, cancels within grace period)
- `contextify-purge` CLI handles the actual data purge after grace period

<!-- TODO: Admin-initiated deletion, admin cancel -->

---

## 8. Delete Individual User

**Status:** Stub. No admin tooling.

Expected workflow: remove a user from a tenant, revoke their keys, optionally purge their synced data.

Current path:
- `DELETE /api/v1/team/members/{id}` (owner/admin, removes from tenant)

<!-- TODO: Admin endpoint, data purge option -->

---

## 9. Change Tenant Plan / Billing

**Status:** Partially implemented. Self-service via Stripe.

Current paths:
- Stripe Customer Portal via `POST /cloud/billing/portal`
- Plan stored in `tenants.plan` (free/pro)

<!-- TODO: Admin override for plan changes, comp accounts, trial extensions -->

---

## 10. View Audit Log

**Status:** Stub. No cross-tenant view.

Expected workflow: server admin views authentication attempts, key operations, and data access across all tenants.

Current state:
- Per-tenant audit log page exists at `/cloud/audit_log`
- No cross-tenant admin view

<!-- TODO: Cross-tenant audit log, failed auth tracking, export -->

---

## 11. Impersonate User / Tenant

**Status:** Not implemented.

Expected workflow: server admin assumes the identity of a tenant owner for debugging, with full audit trail.

<!-- TODO: Design impersonation with audit logging -->

---

## 12. Export Tenant Data

**Status:** Not implemented.

Expected workflow: export all data for a tenant (entries, projects, users, keys, audit log) for compliance or migration.

<!-- TODO: Data export endpoint, format specification -->

---

## 13. Password / Credential Rotation Policy

**Status:** Not applicable currently.

The system uses API keys, not passwords. Key expiry is supported (`expires_at` field on ApiKey) but no automatic rotation policy is enforced.

<!-- TODO: Configurable key expiry policy, rotation reminders -->
