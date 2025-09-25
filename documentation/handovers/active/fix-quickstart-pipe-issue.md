## Task: Fix quickstart.sh bootstrap pipe issue

Problem: Lines 282-291 pipe breaks when deploy-opnsense.sh completes
Requirements: Must work in `curl | bash`, preserve output filtering, propagate exit codes
Success: Bootstrap continues past Phase 1.5, all phases complete

## Root Cause
Pipe creates subshell that doesn't propagate bootstrap exit code when subprocess completes.

## Fix: Use PIPESTATUS Check
Replace lines 282-294 in quickstart.sh:

```bash
bash $bootstrap_cmd 2>&1 | while IFS= read -r line; do
    # Filter output for non-verbose mode
    if [[ "$line" =~ ^Phase ]] || [[ "$line" =~ ^✓ ]] || [[ "$line" =~ ^✅ ]] || \
       [[ "$line" =~ ERROR ]] || [[ "$line" =~ "Installation Complete" ]] || \
       [[ "$line" =~ "VM Details:" ]] || [[ "$line" =~ "Access Credentials:" ]] || \
       [[ "$line" =~ "Service Access:" ]] || [[ "$line" =~ "IP Address:" ]] || \
       [[ "$line" =~ "Password:" ]] || [[ "$line" =~ "http://" ]]; then
        echo "$line"
    fi
done
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    error_exit "Bootstrap failed. Check /tmp/privatebox-bootstrap.log for details"
fi
```

## Why This Solution
- Works reliably in non-interactive mode
- Preserves output filtering
- Captures bootstrap exit code via PIPESTATUS[0]
- Simple and maintainable