#!/bin/bash

LOG_FILE="$RECOVERY_DIR/recovery.log"
ERROR_LOG="$RECOVERY_DIR/error.log"
RECOVERY_SUCCESS=true

send_email_report() {
    if $USE_EMAIL; then
        ERROR_COUNT=$(wc -l < "$ERROR_LOG")
        
        if [[ "$ERROR_COUNT" -eq 0 ]]; then
            EMAIL_SUBJECT="✅ Linux Recovery Successful - $(hostname) ($(date))"
            EMAIL_BODY="Recovery process completed successfully on $(hostname).\n\nLogs saved at: $RECOVERY_DIR\n\nNo errors detected."
        else
            EMAIL_SUBJECT="❌ Linux Recovery Failed - $(hostname) ($(date))"
            EMAIL_BODY="Recovery encountered $ERROR_COUNT errors on $(hostname).\n\nError log:\n$(cat $ERROR_LOG)\n\nCheck $RECOVERY_DIR for details."
        fi
        
        if command -v mailx &>/dev/null; then
            echo -e "$EMAIL_BODY" | mailx -s "$EMAIL_SUBJECT" "$RECOVERY_EMAIL"
        elif command -v sendmail &>/dev/null; then
            echo -e "Subject: $EMAIL_SUBJECT\n\n$EMAIL_BODY" | sendmail "$RECOVERY_EMAIL"
        else
            log_warning "⚠️ No email utility found! Install mailx or sendmail to enable notifications."
        fi
    fi
}

encrypt_backup() {
    BACKUP_ARCHIVE="$RECOVERY_DIR/recovery_data.tar.gz"
    ENCRYPTED_BACKUP="$BACKUP_ARCHIVE.gpg"

    log "Creating archive for backup..."
    tar -czf "$BACKUP_ARCHIVE" -C "$RECOVERY_DIR" .

    log "Encrypting backup using AES256..."
    echo "$BACKUP_PASSPHRASE" | gpg --batch --passphrase-fd 0 --symmetric --cipher-algo AES256 "$BACKUP_ARCHIVE" || {
        log_error "Encryption failed"
        return 1
    }

    log "Backup encrypted successfully: $ENCRYPTED_BACKUP"
    rm -f "$BACKUP_ARCHIVE"
}

backup_to_server() {
    if $USE_BACKUP && command -v rsync &>/dev/null; then
        if $USE_ENCRYPTION; then
            encrypt_backup
            BACKUP_FILE="$RECOVERY_DIR/recovery_data.tar.gz.gpg"
        else
            BACKUP_FILE="$RECOVERY_DIR/recovery_data.tar.gz"
            tar -czf "$BACKUP_FILE" -C "$RECOVERY_DIR" .
        fi
        
        log "Transferring backup to $BACKUP_SERVER..."
        rsync -avz "$BACKUP_FILE" "$BACKUP_SERVER" || log_error "Remote backup failed"
        
        log "Removing local backup file after transfer..."
        rm -f "$BACKUP_FILE"
    fi
}

list_crashed_processes() {
    log "Listing crashed processes..."
    journalctl -xe --no-pager | grep -i "segfault\|crash\|oom" | tail -n 20 > "$RECOVERY_DIR/crashed_processes.log"
}

extract_memory_dump() {
    log "Extracting memory dump..."
    sudo cat /proc/kcore > "$RECOVERY_DIR/memory_dump.img" 2>/dev/null || log_error "Failed to extract memory dump"
}

recover_databases() {
    log "Checking for databases..."

    if command -v mysqlcheck &>/dev/null && systemctl is-active --quiet mysql; then
        log "Recovering MySQL databases..."
        sudo mysqlcheck --all-databases --auto-repair || log_error "MySQL recovery failed"
    fi

    if command -v pg_isready &>/dev/null && systemctl is-active --quiet postgresql; then
        log "Recovering PostgreSQL databases..."
        sudo -u postgres psql -c "REINDEX DATABASE postgres;" || log_error "PostgreSQL recovery failed"
    fi
}

recover_deleted_files() {
    PARTITION=$(df / | tail -1 | awk '{print $1}')
    
    if command -v extundelete &>/dev/null; then
        log "Recovering deleted files from $PARTITION..."
        sudo extundelete "$PARTITION" --restore-all --output-dir "$RECOVERY_DIR" || log_error "Failed to recover files"
    else
        log "extundelete not found! Skipping deleted file recovery..."
    fi
}

repair_file_system() {
    for DEV in $(lsblk -nr -o NAME,FSTYPE,MOUNTPOINT | awk '$2!="" && $3=="" {print "/dev/"$1}'); do
        FSTYPE=$(blkid -o value -s TYPE "$DEV")
        log "Attempting file system repair on $DEV ($FSTYPE)..."
        
        case "$FSTYPE" in
            ext[2-4]) sudo fsck -y "$DEV" || log_error "Failed to repair $DEV" ;;
            xfs) sudo xfs_repair "$DEV" || log_error "Failed to repair $DEV" ;;
            btrfs) sudo btrfs check --repair "$DEV" || log_error "Failed to repair $DEV" ;;
            zfs) sudo zpool scrub "$(basename "$DEV")" || log_error "Failed to repair $DEV" ;;
            *) log "Unknown file system, skipping repair for $DEV" ;;
        esac
    done
}

recover_raid() {
    if command -v mdadm &>/dev/null; then
        log "Checking for RAID arrays..."
        sudo mdadm --detail --scan | tee -a "$RECOVERY_DIR/raid_status.txt"
        
        for ARRAY in $(cat /proc/mdstat | awk '/md/ {print $1}'); do
            log "Repairing RAID array: $ARRAY..."
            sudo mdadm --assemble --scan || log_error "Failed to assemble RAID"
            sudo mdadm --add "$ARRAY" /dev/sd* || log_error "Failed to add drives to RAID"
        done
    fi
}

create_snapshot() {
    if command -v lvs &>/dev/null && sudo lvs | grep -q "LV"; then
        log "Creating LVM snapshot..."
        sudo lvcreate --size 5G --snapshot --name recovery_snapshot /dev/mapper/rootvg-root || log_error "Failed to create LVM snapshot"
    elif command -v btrfs &>/dev/null && sudo btrfs subvolume list / | grep -q "@"; then
        log "Creating Btrfs snapshot..."
        sudo btrfs subvolume snapshot / /@recovery_snapshot || log_error "Failed to create Btrfs snapshot"
    fi
}

check_system_logs() {
    log "Checking system logs for failure information..."
    journalctl -xb -n 100 > "$RECOVERY_DIR/system_logs.txt"
    dmesg | tail -n 50 > "$RECOVERY_DIR/dmesg_logs.txt"
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | \033[33mWARNING:\033[0: $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | \033[31mERROR:\033[0m: $1" | tee -a "$ERROR_LOG"
    RECOVERY_SUCCESS=false
}

main() {
    echo "-----------------------------------------"
    echo "  🔥 Linux Recovery Script 🔥  "
    echo "-----------------------------------------"

    read -p "Enter recovery directory (default: ~/recovery): " RECOVERY_DIR
    RECOVERY_DIR=${RECOVERY_DIR:-$HOME/recovery}
    mkdir -p "$RECOVERY_DIR"

    read -p "Enter your email for recovery notifications (leave blank to skip): " RECOVERY_EMAIL
    USE_EMAIL=false
    if [[ -n "$RECOVERY_EMAIL" ]]; then
        USE_EMAIL=true
    fi

    read -p "Would you like to back up recovered files remotely? (y/n): " BACKUP_CHOICE
    if [[ "$BACKUP_CHOICE" =~ ^[Yy]$ ]]; then
        read -p "Enter backup server (e.g., user@backupserver:/path): " BACKUP_SERVER
        USE_BACKUP=true

        # Ask if user wants encryption
        read -p "Do you want to encrypt the backup before sending? (y/n): " ENCRYPT_CHOICE
        if [[ "$ENCRYPT_CHOICE" =~ ^[Yy]$ ]]; then
            USE_ENCRYPTION=true
            read -s -p "Enter a passphrase for encryption: " BACKUP_PASSPHRASE
            echo
        else
            USE_ENCRYPTION=false
        fi
    else
        USE_BACKUP=false
    fi

    echo "Starting recovery process at $(date)" | tee -a "$LOG_FILE"

    check_system_logs
    create_snapshot
    recover_raid
    repair_file_system
    recover_deleted_files
    recover_databases
    extract_memory_dump
    list_crashed_processes
    backup_to_server
    send_email_report

    log "✅ Recovery process completed. Please check $RECOVERY_DIR for details."
}

main