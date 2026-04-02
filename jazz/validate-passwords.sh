#!/bin/bash
# Validate passwords meet Oracle 19c and shell/SQL/JDBC safety requirements.
# Called during docker build to fail fast on bad passwords.

errors=0

check_password() {
    local name="$1"
    local pw="$2"
    local len=${#pw}

    if [ ${len} -lt 8 ]; then
        echo "FAIL: ${name} is ${len} chars (need 8+). Value: [${pw}]"
        errors=1
        return
    fi

    if echo "${pw}" | grep -qP '[!@#$%^&*(){}\[\]|\\;:'"'"'"` <>?/~\s]'; then
        echo "FAIL: ${name} contains special characters or spaces. Value: [${pw}]"
        errors=1
        return
    fi

    if ! echo "${pw}" | grep -qP '[A-Z]'; then
        echo "FAIL: ${name} has no uppercase letter. Value: [${pw}]"
        errors=1
        return
    fi

    if ! echo "${pw}" | grep -qP '[a-z]'; then
        echo "FAIL: ${name} has no lowercase letter. Value: [${pw}]"
        errors=1
        return
    fi

    if ! echo "${pw}" | grep -qP '[0-9]'; then
        echo "FAIL: ${name} has no digit. Value: [${pw}]"
        errors=1
        return
    fi

    echo "  OK: ${name} (${len} chars) [${pw}]"
}

echo "Validating passwords..."
check_password "JAZZ_ADMIN_PASSWORD" "$1"
check_password "ORACLE_PASSWORD" "$2"

if [ $errors -ne 0 ]; then
    echo ""
    echo "Password rules: 8+ chars, at least 1 uppercase, 1 lowercase, 1 digit."
    echo "No spaces or special characters. Use word-verb phrases like OrangeTiger42runs."
    exit 1
fi

echo "All passwords OK."
