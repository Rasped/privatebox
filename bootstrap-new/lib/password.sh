#!/bin/bash
# Password generation utilities for PrivateBox

# Source common library if not already sourced
if [[ -z "${COMMON_LIB_SOURCED:-}" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
    COMMON_LIB_SOURCED=true
fi

# Phonetic alphabet for password generation (avoiding ambiguous characters)
readonly PHONETIC_CONSONANTS="bcdfghjkmnpqrstvwxyz"
readonly PHONETIC_VOWELS="aeiou"
readonly PHONETIC_DIGITS="23456789"  # Avoiding 0 and 1

# Generate a phonetic password block (6 characters)
generate_password_block() {
    local block=""
    
    # Pattern: consonant-vowel-consonant-vowel-consonant-digit
    # This creates pronounceable blocks
    for pattern in C V C V C D; do
        case $pattern in
            C)  # Consonant
                local index=$((RANDOM % ${#PHONETIC_CONSONANTS}))
                block="${block}${PHONETIC_CONSONANTS:$index:1}"
                ;;
            V)  # Vowel
                local index=$((RANDOM % ${#PHONETIC_VOWELS}))
                block="${block}${PHONETIC_VOWELS:$index:1}"
                ;;
            D)  # Digit
                local index=$((RANDOM % ${#PHONETIC_DIGITS}))
                block="${block}${PHONETIC_DIGITS:$index:1}"
                ;;
        esac
    done
    
    echo "$block"
}

# Generate a full phonetic password (3 blocks separated by dashes)
generate_phonetic_password() {
    local blocks=()
    
    # Generate 3 blocks
    for i in {1..3}; do
        blocks+=("$(generate_password_block)")
    done
    
    # Join with dashes
    local password="${blocks[0]}-${blocks[1]}-${blocks[2]}"
    
    # Convert to mixed case for better security
    # Capitalize first letter of each block
    password=$(echo "$password" | sed 's/\b\([a-z]\)/\u\1/g')
    
    echo "$password"
}

# Generate a random alphanumeric password
generate_random_password() {
    local length="${1:-16}"
    local chars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local password=""
    
    for i in $(seq 1 "$length"); do
        local index=$((RANDOM % ${#chars}))
        password="${password}${chars:$index:1}"
    done
    
    echo "$password"
}

# Generate SSH key pair
generate_ssh_keypair() {
    local key_path="${1:-/root/.ssh/id_rsa}"
    local key_comment="${2:-privatebox@$(hostname)}"
    
    # Create directory if it doesn't exist
    local key_dir=$(dirname "$key_path")
    if [[ ! -d "$key_dir" ]]; then
        mkdir -p "$key_dir"
        chmod 700 "$key_dir"
    fi
    
    # Generate key if it doesn't exist
    if [[ ! -f "$key_path" ]]; then
        log_info "Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f "$key_path" -N "" -C "$key_comment" >/dev/null 2>&1
        
        if [[ $? -eq 0 ]]; then
            chmod 600 "$key_path"
            chmod 644 "${key_path}.pub"
            log_success "SSH key pair generated successfully"
            return 0
        else
            log_error "Failed to generate SSH key pair"
            return 1
        fi
    else
        log_info "SSH key already exists at $key_path"
        return 0
    fi
}

# Encrypt credentials to a file
encrypt_credentials() {
    local credentials_file="$1"
    local recipient="${2:-root@localhost}"
    local output_file="${3:-${credentials_file}.gpg}"
    
    # Check if GPG is available
    if ! command_exists gpg; then
        log_warn "GPG not available, storing credentials in plain text"
        return 1
    fi
    
    # Check if we have a key for the recipient
    if ! gpg --list-keys "$recipient" >/dev/null 2>&1; then
        log_warn "No GPG key found for $recipient, generating one..."
        
        # Generate a GPG key non-interactively
        cat > /tmp/gpg-genkey-batch <<EOF
%echo Generating GPG key for PrivateBox
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: PrivateBox Admin
Name-Email: $recipient
Expire-Date: 0
%no-protection
%commit
%echo done
EOF
        
        gpg --batch --generate-key /tmp/gpg-genkey-batch 2>/dev/null
        rm -f /tmp/gpg-genkey-batch
    fi
    
    # Encrypt the file
    if gpg --trust-model always --encrypt --recipient "$recipient" --output "$output_file" "$credentials_file" 2>/dev/null; then
        log_success "Credentials encrypted to $output_file"
        # Secure delete the original
        shred -u "$credentials_file" 2>/dev/null || rm -f "$credentials_file"
        return 0
    else
        log_error "Failed to encrypt credentials"
        return 1
    fi
}

# Generate password hash for cloud-init
generate_password_hash() {
    local password="$1"
    
    # Use openssl to generate SHA-512 hash (cloud-init compatible)
    if command_exists openssl; then
        # Generate a random salt
        local salt=$(openssl rand -base64 6)
        # Generate SHA-512 hash
        echo "$(openssl passwd -6 -salt "$salt" "$password")"
    else
        # Fallback to python if available
        if command_exists python3; then
            python3 -c "import crypt; print(crypt.crypt('$password', crypt.mksalt(crypt.METHOD_SHA512)))"
        else
            log_error "Cannot generate password hash - no suitable tool found"
            return 1
        fi
    fi
}

# Generate and store all credentials
generate_all_credentials() {
    local output_dir="${1:-/root/.privatebox}"
    local vm_name="${2:-privatebox}"
    
    # Create output directory
    mkdir -p "$output_dir"
    chmod 700 "$output_dir"
    
    local credentials_file="$output_dir/credentials.txt"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Generate passwords
    local vm_password=$(generate_phonetic_password)
    local portainer_password=$(generate_phonetic_password)
    local semaphore_password=$(generate_phonetic_password)
    
    # Generate password hash for cloud-init
    local vm_password_hash=$(generate_password_hash "$vm_password")
    
    # Generate SSH key
    local ssh_key_path="$output_dir/id_rsa"
    generate_ssh_keypair "$ssh_key_path" "${vm_name}@privatebox"
    
    # Write credentials to file
    cat > "$credentials_file" <<EOF
# PrivateBox Credentials
# Generated: $timestamp
# IMPORTANT: Keep this file secure!

## VM Access
VM_USERNAME: $vm_name
VM_PASSWORD: $vm_password
SSH_PRIVATE_KEY: $ssh_key_path
SSH_PUBLIC_KEY: ${ssh_key_path}.pub

## Service Passwords
PORTAINER_ADMIN_PASSWORD: $portainer_password
SEMAPHORE_ADMIN_PASSWORD: $semaphore_password

## Notes
- These passwords are phonetic and easier to type
- SSH key authentication is preferred over passwords
- Change these passwords after first login
EOF
    
    # Set secure permissions
    chmod 600 "$credentials_file"
    
    # Attempt to encrypt
    encrypt_credentials "$credentials_file" "root@localhost" "$output_dir/credentials.gpg"
    
    # Return the passwords for use in scripts
    echo "VM_PASSWORD=$vm_password"
    echo "VM_PASSWORD_HASH=$vm_password_hash"
    echo "PORTAINER_PASSWORD=$portainer_password"
    echo "SEMAPHORE_PASSWORD=$semaphore_password"
    echo "SSH_PUBLIC_KEY=$(cat ${ssh_key_path}.pub)"
}

# Test password generation (for debugging)
test_password_generation() {
    echo "Testing password generation..."
    echo "Phonetic password: $(generate_phonetic_password)"
    echo "Random password (16 chars): $(generate_random_password 16)"
    echo "Password block: $(generate_password_block)"
}