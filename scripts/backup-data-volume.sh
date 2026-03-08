#!/bin/bash
# ============================================================
# Automated OCI Block Volume Backup Script
# Location: /usr/local/bin/backup-data-volume.sh
# Schedule: crontab — 0 3 * * 0 (every Sunday at 3 AM)
#
# Setup:
#   1. Replace VOLUME_OCID with your actual volume OCID
#   2. sudo chmod +x /usr/local/bin/backup-data-volume.sh
#   3. (crontab -l 2>/dev/null; echo "0 3 * * 0 /usr/local/bin/backup-data-volume.sh") | crontab -
# ============================================================

set -euo pipefail

VOLUME_OCID="ocid1.volume.oc1.REGION.YOUR_VOLUME_OCID"
BACKUP_NAME="auto-backup-$(date +%Y%m%d)"
LOG_FILE="/var/log/backup-data-volume.log"

echo "[$(date)] Starting backup: ${BACKUP_NAME}" >> "${LOG_FILE}"

if oci bv backup create \
    --volume-id "${VOLUME_OCID}" \
    --display-name "${BACKUP_NAME}" \
    --type INCREMENTAL >> "${LOG_FILE}" 2>&1; then
    echo "[$(date)] Backup completed successfully: ${BACKUP_NAME}" >> "${LOG_FILE}"
else
    echo "[$(date)] ERROR: Backup failed for ${BACKUP_NAME}" >> "${LOG_FILE}"
    exit 1
fi
