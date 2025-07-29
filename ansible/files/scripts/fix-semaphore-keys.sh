#!/bin/bash
# Fix Ansible playbooks by removing invalid semaphore_* keys from vars_prompt

echo "Fixing Ansible playbooks with invalid semaphore_* keys..."

# Find all YAML files with semaphore_ keys
files=$(grep -r "semaphore_" ansible/playbooks/services/ --include="*.yml" -l)

for file in $files; do
    echo "Processing: $file"
    
    # Create backup
    cp "$file" "${file}.bak"
    
    # Remove semaphore_* lines from vars_prompt sections
    # Using perl for better cross-platform compatibility
    perl -i -pe 's/^\s+semaphore_.*\n//g' "$file"
    
    # Check if file was modified
    if ! diff -q "$file" "${file}.bak" > /dev/null; then
        echo "  - Fixed: removed semaphore_* keys"
        rm "${file}.bak"
    else
        echo "  - No changes needed"
        rm "${file}.bak"
    fi
done

echo "Done! All playbooks fixed."