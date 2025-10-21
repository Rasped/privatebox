#!/bin/bash
# Phonetic password generator for PrivateBox
# Generates memorable passwords using 5-letter words with number substitutions

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORD_FILE="${SCRIPT_DIR}/phonetic-words.txt"

# Letter to number substitution map
apply_substitutions() {
    local word="$1"
    local result=""
    local has_number=false
    local eligible_positions=()
    
    # First pass: identify eligible positions for substitution
    for ((i=0; i<${#word}; i++)); do
        local char="${word:$i:1}"
        local lower_char=$(echo "$char" | tr '[:upper:]' '[:lower:]')
        
        case "$lower_char" in
            e|o|i|l|a|s) eligible_positions+=($i) ;;
        esac
    done
    
    # If no eligible letters, return original word
    if [[ ${#eligible_positions[@]} -eq 0 ]]; then
        echo "$word"
        return
    fi
    
    # Ensure at least one substitution
    local guaranteed_pos=${eligible_positions[$((RANDOM % ${#eligible_positions[@]}))]}
    
    # Process each character
    for ((i=0; i<${#word}; i++)); do
        local char="${word:$i:1}"
        local lower_char=$(echo "$char" | tr '[:upper:]' '[:lower:]')

        # Only do the one guaranteed substitution per word
        if [[ $i -eq $guaranteed_pos ]]; then
            case "$lower_char" in
                e) char="3"; has_number=true ;;
                o) char="0"; has_number=true ;;
                i) char="1"; has_number=true ;;
                l) char="1"; has_number=true ;;
                a) char="4"; has_number=true ;;
                s) char="5"; has_number=true ;;
            esac
        fi

        result+="$char"
    done
    
    echo "$result"
}

# Generate phonetic password
generate_phonetic_password() {
    local word_count="${1:-3}"
    local words=()
    
    # Check if word file exists
    if [[ ! -f "$WORD_FILE" ]]; then
        echo "Error: Word file not found at $WORD_FILE" >&2
        return 1
    fi
    
    # Read all words from file (excluding comments and empty lines)
    local all_words=()
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ -n "$line" && ! "$line" =~ ^# ]]; then
            all_words+=("$line")
        fi
    done < "$WORD_FILE"
    
    # Check if we have enough words
    if [[ ${#all_words[@]} -lt $word_count ]]; then
        echo "Error: Not enough words in word file" >&2
        return 1
    fi
    
    # Select random words
    local selected_indices=()
    while [[ ${#words[@]} -lt $word_count ]]; do
        local index=$((RANDOM % ${#all_words[@]}))
        
        # Ensure we don't select the same word twice
        if [[ ! " ${selected_indices[@]} " =~ " ${index} " ]]; then
            selected_indices+=($index)
            local word="${all_words[$index]}"
            
            # Apply random capitalization (approximately 1 in 5 letters)
            local capitalized=""
            for ((i=0; i<${#word}; i++)); do
                local char="${word:$i:1}"
                if (( RANDOM % 5 == 0 )); then
                    char=$(echo "$char" | tr '[:lower:]' '[:upper:]')
                fi
                capitalized+="$char"
            done
            word="$capitalized"
            
            # Apply substitutions
            word=$(apply_substitutions "$word")
            
            words+=("$word")
        fi
    done
    
    # Join with hyphens
    local password=""
    for ((i=0; i<${#words[@]}; i++)); do
        if [[ $i -gt 0 ]]; then
            password+="-"
        fi
        password+="${words[$i]}"
    done
    
    echo "$password"
}

# Generate fallback password using original method if phonetic fails
generate_fallback_password() {
    local length="${1:-32}"
    local password=""
    
    # Ensure required character types
    local upper=$(tr -dc 'A-Z' < /dev/urandom | head -c 1)
    local lower=$(tr -dc 'a-z' < /dev/urandom | head -c 1)
    local digit=$(tr -dc '0-9' < /dev/urandom | head -c 1)
    local special=$(tr -dc '@*+=' < /dev/urandom | head -c 1)
    
    # Generate remaining characters
    local remaining=$((length - 4))
    local chars=$(tr -dc 'A-Za-z0-9@*+=' < /dev/urandom | head -c $remaining)
    
    # Combine and shuffle
    local all_chars="${upper}${lower}${digit}${special}${chars}"
    password=$(echo "$all_chars" | fold -w1 | shuf | tr -d '\n')
    
    echo "$password"
}

# Wrapper function that tries phonetic first, falls back to random
generate_password() {
    local type="${1:-services}"  # "services" or "admin"
    
    case "$type" in
        services)
            # Try phonetic with 3 words
            if password=$(generate_phonetic_password 3 2>/dev/null); then
                echo "$password"
            else
                # Fallback to random 20 chars
                generate_fallback_password 20
            fi
            ;;
        admin)
            # Try phonetic with 5 words
            if password=$(generate_phonetic_password 5 2>/dev/null); then
                echo "$password"
            else
                # Fallback to random 32 chars
                generate_fallback_password 32
            fi
            ;;
        *)
            # Default to random password with specified length
            generate_fallback_password "${type:-32}"
            ;;
    esac
}

# Allow direct execution for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse command line arguments
    case "${1:-}" in
        --services)
            generate_password services
            ;;
        --admin)
            generate_password admin
            ;;
        --phonetic)
            generate_phonetic_password "${2:-3}"
            ;;
        --random)
            generate_fallback_password "${2:-32}"
            ;;
        *)
            echo "Usage: $0 [--services|--admin|--phonetic N|--random N]"
            echo "  --services  Generate services password (3 words)"
            echo "  --admin     Generate admin password (5 words)"
            echo "  --phonetic N Generate N-word phonetic password"
            echo "  --random N   Generate N-character random password"
            exit 1
            ;;
    esac
fi