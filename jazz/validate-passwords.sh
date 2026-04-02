#!/bin/bash
# Validate passwords meet Oracle 19c and shell/SQL/JDBC safety requirements.
# Called during docker build to fail fast on bad passwords.

errors=0

# Basic check: no special chars, no spaces
check_basic() {
    local name="$1"
    local pw="$2"
    local len=${#pw}

    if [ ${len} -lt 4 ]; then
        echo "FAIL: ${name} is ${len} chars (need 4+). Value: [${pw}]"
        errors=1
        return 1
    fi

    if echo "${pw}" | grep -qP '[!@#$%^&*(){}\[\]|\\;:'"'"'"` <>?/~\s]'; then
        echo "FAIL: ${name} contains special characters or spaces. Value: [${pw}]"
        errors=1
        return 1
    fi

    return 0
}

# Oracle-strict check: 8+ chars, upper+lower+digit (Oracle 19c requirement)
check_oracle_password() {
    local name="$1"
    local pw="$2"
    local len=${#pw}

    check_basic "${name}" "${pw}" || return

    if [ ${len} -lt 8 ]; then
        echo "FAIL: ${name} is ${len} chars (Oracle requires 8+). Value: [${pw}]"
        errors=1
        return
    fi

    if ! echo "${pw}" | grep -qP '[A-Z]'; then
        echo "FAIL: ${name} has no uppercase letter (Oracle requires it). Value: [${pw}]"
        errors=1
        return
    fi

    if ! echo "${pw}" | grep -qP '[a-z]'; then
        echo "FAIL: ${name} has no lowercase letter (Oracle requires it). Value: [${pw}]"
        errors=1
        return
    fi

    if ! echo "${pw}" | grep -qP '[0-9]'; then
        echo "FAIL: ${name} has no digit (Oracle requires it). Value: [${pw}]"
        errors=1
        return
    fi

    echo "  OK: ${name} (${len} chars) [${pw}]"
}

# Jazz/LDAP check: just no special chars (LDAP may have its own rules)
check_jazz_password() {
    local name="$1"
    local pw="$2"
    local len=${#pw}

    check_basic "${name}" "${pw}" || return

    echo "  OK: ${name} (${len} chars) [${pw}]"
}

echo "Validating passwords..."
check_jazz_password "JAZZ_ADMIN_PASSWORD" "$1"
check_oracle_password "ORACLE_PASSWORD" "$2"

if [ $errors -ne 0 ]; then
    echo ""
    echo "JAZZ_ADMIN_PASSWORD: must match your LDAP password. No special chars or spaces."
    echo "ORACLE_PASSWORD: 8+ chars, at least 1 uppercase, 1 lowercase, 1 digit. No special chars."
    exit 1
fi

echo "All passwords OK."
