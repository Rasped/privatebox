# Phase 6 Testing Findings - Semaphore Template Sync

## Test Environment
- **Test Date**: 2025-07-10
- **Test Server**: 192.168.1.10 (Proxmox host)
- **Created VM**: 192.168.1.21
- **Semaphore Version**: v2.15.0-1e13324-1749881668
- **Semaphore URL**: http://192.168.1.21:3000
- **Credentials**: admin / x>WNpld2SLN#b<rLM353Dlt8Qkik<_Bi

## Issues Found and Fixed

### 1. API Token Capture Issue ✅ FIXED
**Problem**: The API token was being captured with log messages mixed in:
```
[2025-07-10 15:58:46] [INFO] Creating API token for template generator...
-xdjv1_uele4thiluxzmmrc9p1yh2iu5xl4vf86mnpk=
```

**Root Cause**: Bash command substitution `$(...)` captures ALL stdout output, including log messages.

**Fix Applied**: Redirect log messages to stderr in `create_api_token()`:
```bash
log_info "Creating API token for template generator..." >&2
log_error "Failed to create API token" >&2
```

**Status**: Fixed and pushed in commit 23985bb

### 2. Environment Creation Issue ✅ FIXED
**Problem**: Environment creation failed with HTTP 400 error.

**Root Cause**: The `json` field in Semaphore expects a JSON string, not a JSON object.

**Fix Applied**: Convert JSON object to string:
```bash
local json_vars=$(jq -n \
    --arg url "http://localhost:3000" \
    --arg token "$api_token" \
    '{SEMAPHORE_URL: $url, SEMAPHORE_API_TOKEN: $token}' | jq -Rs .)
```

**Status**: Fixed and pushed in commit 23985bb

### 3. Repository Creation Issue ❌ NOT FIXED
**Problem**: Repository creation fails with HTTP 404 error.

**Discovery**: The endpoint `/api/project/1/repositories` doesn't exist in Semaphore v2.15.0.

**Evidence**:
- `POST /api/project/1/repositories` returns 404
- `GET /api/project/1/repositories` returns empty array `[]`
- Documentation confirms repositories are separate entities
- No alternate endpoint found

**Status**: Not fixed per user request

## Current State After Fixes

### What Works:
- ✅ API token creation (returns clean token)
- ✅ Environment creation (with proper JSON string format)
- ✅ SSH key creation
- ✅ Default inventory creation
- ✅ Project creation

### What Doesn't Work:
- ❌ Repository creation (404 endpoint)
- ❌ Template creation (requires repository_id which we can't create)
- ❌ Initial template sync run (no template to run)

## Test Results Summary

From the cloud-init logs:
```
[2025-07-10 15:58:46] [INFO] Step 1/5: Creating API token...
[2025-07-10 15:58:46] [INFO] ✓ API token created
[2025-07-10 15:58:46] [INFO] Step 2/5: Creating SemaphoreAPI environment...
[2025-07-10 15:58:47] [ERROR] Failed to create environment. Status: 400
[2025-07-10 15:58:47] [INFO] Step 3/5: Looking up resource IDs...
[2025-07-10 15:58:47] [INFO] Available repositories: (empty)
[2025-07-10 15:58:47] [INFO] Step 4/5: Creating Generate Templates task...
[2025-07-10 15:58:47] [ERROR] Failed to create template. Status: 400
```

## Key Discoveries

1. **Semaphore v2.15.0 Changes**: Repository API endpoint structure has changed
2. **JSON Field Format**: Environment variables must be JSON strings, not objects
3. **Function Output Capture**: Need to redirect logs to stderr when returning values
4. **Missing log_warning**: Some log functions are not available in the execution context

## Next Steps for Resolution

1. **Repository Issue Options**:
   - Option A: Check if repositories are now embedded in templates
   - Option B: Find the correct API endpoint for v2.15.0
   - Option C: Use template with direct git_url configuration
   - Option D: Skip repository creation and use local filesystem

2. **Template Creation**:
   - Need to understand required fields for v2.15.0
   - May need to embed git configuration in template
   - Python app type might have different requirements

3. **Testing Approach**:
   - Manual API testing via curl to understand structure
   - Check Semaphore UI to see how it creates templates
   - Review v2.15.0 release notes for API changes

## Message for Next Instance

```
Continue Phase 6 implementation from phase6-testing-findings.md. 

COMPLETED:
- API token capture fixed (logs to stderr)
- Environment JSON format fixed (string not object)
- Both fixes pushed in commit 23985bb

CURRENT ISSUE:
- Repository creation fails with 404 in Semaphore v2.15.0
- The /api/project/1/repositories endpoint doesn't exist
- Need to find how to handle git repositories in v2.15.0

TEST SERVER:
- VM at 192.168.1.21 (credentials in findings doc)
- Semaphore v2.15.0 running
- Has created: project, keys, inventory, environment

NEXT STEPS:
1. DON'T try to fix repository endpoint (user request)
2. Investigate if templates can embed git config
3. Find minimal template creation payload
4. Test with curl before implementing

See dev-notes/phase6-testing-findings.md for full details.
```