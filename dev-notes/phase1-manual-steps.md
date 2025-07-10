# Phase 1: Manual Semaphore Setup Steps

## Prerequisites
- Semaphore UI is accessible
- You have admin credentials
- The PrivateBox repository is available (either already added or you can add it)

## Steps to Test Phase 1

1. **Log into Semaphore**
   - Access your Semaphore web interface
   - Log in with admin credentials

2. **Add Repository (if not already present)**
   - Go to "Key Store" → "Repository"
   - Click "New Repository"
   - Name: `PrivateBox`
   - Git URL: `https://github.com/Rasped/privatebox.git`
   - Branch: `main`
   - Authentication: None (public repo)

3. **Create Test Template**
   - Navigate to "Task Templates"
   - Click "New Template"
   - Fill in:
     - **Name**: `Test Template Generator`
     - **Playbook**: `ansible/playbooks/maintenance/generate-templates.yml`
     - **Inventory**: `Default Inventory`
     - **Repository**: `PrivateBox`
     - **Environment**: (leave empty)
     - **Vault Pass**: (leave empty)
   - Click "Create"

4. **Run the Test**
   - Find "Test Template Generator" in the template list
   - Click "Run" button
   - Watch the task output

## Expected Output

You should see output similar to:
```
=== Semaphore Template Generator ===
Python version: 3.x.x (details...)
Current working directory: /tmp/semaphore_1_X/
Script location: /tmp/semaphore_1_X/tools/generate-templates.py
Repository root check: True

Environment variables:
  ANSIBLE_xxx: ...
  PATH: ...
  PWD: /tmp/semaphore_1_X/
  SEMAPHORE_xxx: ...
  USER: ...
```

## What to Check

1. **Python Version**: Should be Python 3.x
2. **Working Directory**: Should be a temporary directory where Semaphore cloned the repo
3. **Repository Check**: Should show `True` indicating the script can find `ansible/playbooks`
4. **Environment Variables**: Note which SEMAPHORE_* variables are available

## Troubleshooting

- **Script not found**: Check if the repository was cloned correctly
- **Python errors**: Verify Python 3 is available in the container
- **Repository check fails**: Ensure the playbook path in template is correct

## Next Steps

Once this works, we'll proceed to Phase 2 where we'll:
- Generate an API token
- Create an environment with API credentials
- Test API connectivity from the script