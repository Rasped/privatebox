#!/bin/bash
# Helper script to send strings via qm sendkey
# Usage: qm-sendstring.sh <vmid> <string> [delay]

VMID=$1
STRING=$2
DELAY=${3:-0.05}  # Default 50ms between keys

if [ -z "$VMID" ] || [ -z "$STRING" ]; then
    echo "Usage: $0 <vmid> <string> [delay]"
    exit 1
fi

# Send each character
for (( i=0; i<${#STRING}; i++ )); do
    char="${STRING:$i:1}"
    
    # Handle special characters
    case "$char" in
        " ") key="spc" ;;
        "-") key="minus" ;;
        "_") key="shift-minus" ;;
        ".") key="dot" ;;
        "/") key="slash" ;;
        ":") key="shift-semicolon" ;;
        "!") key="shift-1" ;;
        "@") key="shift-2" ;;
        "#") key="shift-3" ;;
        "$") key="shift-4" ;;
        "%") key="shift-5" ;;
        "^") key="shift-6" ;;
        "&") key="shift-7" ;;
        "*") key="shift-8" ;;
        "(") key="shift-9" ;;
        ")") key="shift-0" ;;
        *) key="$char" ;;
    esac
    
    qm sendkey $VMID "$key"
    sleep $DELAY
done