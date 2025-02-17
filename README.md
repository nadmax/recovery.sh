# recovery.sh

This Linux recovery script is designed to perform a comprehensive system recovery after a crash or failure.  
Below is a detailed breakdown of each feature.  

## 📝 1. Interactive User Input  

Before starting recovery, the script prompts the user for:  
✅ Recovery directory (Default: ~/recovery)  
✅ Email address for notifications  
✅ Remote backup preference  
✅ Backup encryption choice (AES256)  

## 📜 2. System Logs Collection  

✅ Extracts system logs (journalctl -xb -n 100) to analyze crash causes.  
✅ Stores dmesg logs (last 50 entries) to check for hardware issues.  
✅ Saves logs in $RECOVERY_DIR/system_logs.txt and $RECOVERY_DIR/dmesg_logs.txt.  

## 💾 3. Snapshot Creation (LVM & Btrfs)  

✅ LVM Snapshots: If using LVM, creates a 5GB snapshot to prevent further data loss.  
✅ Btrfs Snapshots: If using Btrfs, makes a subvolume snapshot for rollback.  

## 🔄 4. RAID Recovery (mdadm)  

✅ Checks for RAID arrays (/proc/mdstat) and logs status.  
✅ Assembles degraded RAID arrays using mdadm.  
✅ Attempts to re-add missing drives to the RAID array.  

## 🛠️ 5. File System Repair  

✅ Detects unmounted file systems using lsblk.  
✅ Automatically repairs them using the correct tool:  
```
fsck -y for ext2/ext3/ext4
xfs_repair for XFS
btrfs check --repair for Btrfs
zpool scrub for ZFS
```

## 📂 6. Deleted File Recovery  

✅ Uses extundelete to restore deleted files on ext-based partitions.  
✅ If extundelete is missing, logs a warning but continues execution.  

## 🗄️ 7. Database Recovery  

✅ Detects and attempts to recover:  
```
MySQL/MariaDB (mysqlcheck --all-databases --auto-repair)
PostgreSQL (REINDEX DATABASE postgres)
```

## 🖥️ 8. Memory Dump Extraction  

✅ Extracts the kernel memory dump (/proc/kcore) for forensic analysis.  

## 🔍 9. Crashed Process Analysis  

✅ Analyzes journalctl logs for crashes, segfaults, and out-of-memory errors.  
✅ Saves the last 20 crash logs in $RECOVERY_DIR/crashed_processes.log.  

## 🔐 10. Encrypted Backup (AES256 via GPG)  

✅ User can choose encryption before remote backup.  
✅ Encrypts using GPG AES256 for secure storage.  
✅ Passphrase is prompted securely before encryption.  
✅ Original unencrypted backup is deleted after encryption.  

## 📤 11. Remote Backup (Rsync)  

✅ Uses rsync to transfer recovered files to a remote backup server.  
✅ Encrypts backup before transfer if user selected encryption.  
✅ Deletes local backup after successful upload to save disk space.  

## 📧 12. Email Notification System  

✅ Sends success/failure reports via email.  
✅ Includes error count and log summary.  
✅ Works with mailx or sendmail (warns if neither is installed).  

## 🛑 13. Error Logging & Reporting  

✅ All actions are logged in $RECOVERY_DIR/recovery.log.  
✅ Errors are recorded separately in $RECOVERY_DIR/error.log.  
✅ If any step fails, script marks recovery as unsuccessful.  

## How this script works in a recovery scenario

1️⃣ User starts the script with root privileges and provides necessary inputs.

```bash
sudo ./recovery.sh
```
2️⃣ The script:
- Collects system logs & crash details
- Creates LVM/Btrfs snapshots
- Repairs RAID & file systems
- Recovers deleted files & databases
- Extracts memory dumps
- If chosen, the script backs up recovered data (optionally encrypted).
- If chosen, an email report is sent with a success/failure summary.

## ✅ Why this script is powerful
- Full System Recovery 🔄 (File System, RAID, Databases, Memory) 
- Interactive & Configurable 🎛️ (User chooses backup & encryption options)
- Secure Backups 🔐 (AES256 Encryption Available)
- Comprehensive Logging & Reporting 📑 (Error tracking & email alerts)