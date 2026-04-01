#!/bin/bash
#
# Tails the Oracle alert log so docker logs shows database initialization progress.
# Mounted as an Oracle startup script — runs after the database is created.
#

ALERT_LOG=$(find /opt/oracle/diag/rdbms -name "alert_*.log" 2>/dev/null | head -1)

if [[ -n "${ALERT_LOG}" ]]; then
    echo "=== Tailing Oracle alert log: ${ALERT_LOG} ==="
    tail -f "${ALERT_LOG}" 2>/dev/null | while IFS= read -r line; do
        # Filter to interesting lines only
        case "${line}" in
            *"Completed"*|*"Starting"*|*"CREATE"*|*"ALTER"*|*"Pluggable"*|*"PDB"*|*"open"*|*"JAZZPDB"*|*"ERROR"*|*"ORA-"*)
                echo "[Oracle] ${line}"
                ;;
        esac
    done &
fi
