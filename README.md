# Unraid VM Backup Script

A comprehensive Bash-based backup solution for managing virtual machines (VMs) on Unraid systems. This script automates the creation of snapshots, backups, and libvirt configuration preservation with intelligent retention and rotation policies.

## Quick Start

1. **Place the script and parameters.ini in the same directory** on your Unraid server
2. **Edit parameters.ini** with your paths and preferences (see Configuration section)
3. **Make the script executable**: `chmod +x script`
4. **Run the script**: `./script`
5. **Check the logs**: `tail -f /mnt/thegate/backup-vm/logs/backup-*.log`

That's it! The script will handle snapshots, backups, and libvirt configs automatically.

## Features

- **VM Snapshots**: Creates reflink (copy-on-write) snapshots of VM disk images for quick point-in-time copies
- **VM Backups**: Backs up VM disk images with optional compression using zstd
- **Libvirt Configuration Backup**: Automatically backs up libvirt configuration files
- **Intelligent Rotation**: Maintains snapshots and backups based on both count limits and retention days
- **Filesystem Safety**: Monitors disk usage and prevents operations if usage exceeds configured thresholds
- **Flexible VM Selection**: Target all VMs, specific VMs, or skip the operation entirely
- **Comprehensive Logging**: Detailed logging with timestamps for all operations
- **Unraid Share Support**: Handles backups to Unraid user shares, unassigned disks, and cache pools
- **Filesystem Flexibility**: Works with both btrfs and XFS (with reflink support) filesystems

## How It Works

### Core Operations

1. **Configuration Loading**: Reads settings from `parameters.ini` and validates all parameters
2. **Pre-flight Checks**: Verifies that required tools (virsh, zstd) are installed
3. **VM Target Determination**: Identifies which VMs to snapshot and back up based on configuration
4. **Mount Point Validation**: Ensures all mount points exist and support required filesystem features
5. **Libvirt Backup**: Creates compressed archive of libvirt configuration directory
6. **VM Snapshots**: Creates reflink snapshots of specified VM disk images
7. **VM Backups**: Backs up VM disk images with optional compression and rotation

### Backup Process Details

#### Libvirt Backup (`libvirt_backup()`)
- Archives the entire libvirt configuration directory to a tar.gz file
- Stores backups in `{VM_BACKUP_LOCATION}/libvirt/`
- Automatically rotates old backups based on `BACKUPS` count and `RETENTION_DAYS` age

#### VM Snapshots (`vm_snapshot()`)
- Creates reflink snapshots of all `.img` disk files in each VM's directory
- Snapshots are stored alongside original disk images with naming pattern: `{disk_name}_snapshot_{timestamp}.fullsnap`
- Snapshot files use reflink technology (copy-on-write) for minimal storage overhead
- Automatically rotates snapshots based on `SNAPSHOTS` count and `RETENTION_DAYS` age
- Includes pre-operation check to ensure filesystem isn't too full

#### VM Backups (`vm_backup()`)
- Intelligently identifies backup target location and routing:
  - **User Share** (`/mnt/user/*`): Attempts to find the physical disk backing the share via Unraid config
  - **Direct Disk/Cache Pool** (other paths): Uses the mount point directly
  - **Fallback Behavior**: If share config exists but has empty `shareInclude`, gracefully falls back to using the share path directly
- Optionally backs up only the primary disk (first boot device) or all disks
- Creates temporary reflinks of disk images for safe backup operations
- **With Compression (`BACKUP_COMPRESSION=Y`)**:
  - Compresses temporary reflinks using zstd
  - Stores as `{timestamp}-{disk_name}.zst` files
- **Without Compression (`BACKUP_COMPRESSION=N`)**:
  - Copies temporary reflinks using rsync
  - Stores as `{timestamp}-{disk_name}` files
- Automatically rotates old backups based on `BACKUPS` count and `RETENTION_DAYS` age
- Cleans up temporary reflinks after successful backup

### File Rotation Strategy

The `file_rotation()` function manages both snapshot and backup retention using two criteria:

1. **Age-Based Retention**: Deletes files older than `RETENTION_DAYS`
2. **Count-Based Rotation**: Keeps only the most recent N files (based on modification time)

This dual approach ensures you never exceed your count limits while also enforcing a minimum age threshold.

## Backup Location Routing

The script intelligently handles different backup location types automatically:

### 1. Cache Pool or Unassigned Disk (Recommended)
**Example**: `VM_BACKUP_LOCATION="/mnt/thegate/backup-vm"`

- Script detects the path is NOT a user share (doesn't start with `/mnt/user/`)
- Validates that `VM_BACKUP_MOUNTPOINT` (`/mnt/thegate`) is a proper btrfs or XFS mount
- Uses the path directly for all backups and logs
- **Advantages**: Simple, fast, no FUSE layer, predictable behavior

### 2. User Share with Physical Disk Assignment
**Example**: `VM_BACKUP_LOCATION="/mnt/user/backup-vm"`

- Script detects the path is a user share (starts with `/mnt/user/`)
- Reads the share config from `/boot/config/shares/backup-vm.cfg`
- Extracts the physical disk from the `shareInclude` field (e.g., `disk1`)
- Redirects backups to the physical disk path to bypass FUSE layer
- **Advantages**: Uses Unraid's share management while avoiding FUSE overhead

### 3. User Share WITHOUT Physical Disk Assignment (Fallback)
**Example**: `VM_BACKUP_LOCATION="/mnt/user/backup-vm"` but `shareInclude` is empty

- Script detects the path is a user share
- Attempts to read share config but finds empty `shareInclude` field
- **Gracefully falls back** to using the user share path directly
- Logs a warning but continues with backup operation
- **Behavior**: Still works, but may use FUSE layer
- **Solution**: Configure the share in Unraid UI to assign a physical disk for better performance

## Configuration (parameters.ini)

All settings are defined in `parameters.ini`, located in the same directory as the script.

### VM Backup Settings

| Parameter | Type | Example | Description |
|-----------|------|---------|-------------|
| `VM_SNAPSHOT_LIST` | String | `ALL`, `NONE`, or `vm1,vm2,vm3` | VMs to snapshot. Use "ALL" for all VMs, "NONE" to skip, or comma-separated list |
| `VM_BACKUP_LIST` | String | `ALL`, `NONE`, or `vm1,vm2,vm3` | VMs to back up. Use "ALL" for all VMs, "NONE" to skip, or comma-separated list |
| `VM_BACKUP_PRI_ONLY` | Y/N | `Y` | If "Y", back up only the primary disk (boot priority 1); if "N", back up all disks |
| `BACKUP_COMPRESSION` | Y/N | `Y` | If "Y", compress backups using zstd; if "N", store uncompressed copies |

### Retention & Rotation Settings

| Parameter | Type | Range | Default | Description |
|-----------|------|-------|---------|-------------|
| `SNAPSHOTS` | Integer | 1+ | 10 | Maximum number of snapshots to keep per disk |
| `BACKUPS` | Integer | 1+ | 7 | Maximum number of backup versions to keep per disk |
| `RETENTION_DAYS` | Integer | 7-365 | 30 | Minimum days to retain all backups; delete anything older |

### Path Settings

| Parameter | Type | Example | Description |
|-----------|------|---------|-------------|
| `VM_MOUNTPOINT` | Path | `/mnt/nvme_vm_cache` | Mount point where VMs are stored (must be btrfs or XFS with reflink) |
| `VM_BACKUP_MOUNTPOINT` | Path | `/mnt/thegate` | Physical mount point for backup validation. This should be the root of your backup destination (disk, cache pool, or array). Script validates that this path is a valid btrfs or XFS mount. |
| `LIBVERT_LOCATION` | Path | `/etc/libvirt` | Directory containing libvirt configuration files to back up |
| `VM_BACKUP_LOCATION` | Path | `/mnt/thegate/backup-vm` | Base directory where backups, logs, and libvirt backups are stored. Can be a user share (`/mnt/user/...`), unassigned disk, or cache pool. |
| `SHARES_CONFIG_DIR` | Path | `/boot/config/shares` | Directory containing Unraid share configuration files (for share analysis). Only used if `VM_BACKUP_LOCATION` is on a user share. |

### Safety Settings

| Parameter | Type | Range | Default | Description |
|-----------|------|-------|---------|-------------|
| `FILESYSTEM_MAX_PCT` | Integer | 0-100 | 80 | Halt backup if filesystem usage would exceed this percentage (safety threshold) |

### Debug & Logging

| Parameter | Type | Example | Description |
|-----------|------|---------|-------------|
| `DEBUG_MODE` | Y/N | `N` | If "Y", script runs in dry-run mode (no actual commands executed); if "N", normal operation |

## Directory Structure

After running the backup script, your backup location will have this structure:

### Example with Cache Pool (`/mnt/thegate/backup-vm`)

```
/mnt/thegate/backup-vm/
├── logs/
│   ├── backup-2026-03-10_074513.log
│   ├── backup-2026-03-10_083022.log
│   └── ...
├── libvirt/
│   ├── libvirt-backup-2026-03-10_074513.tar.gz
│   ├── libvirt-backup-2026-03-10_083022.tar.gz
│   └── ...
└── backups/
    ├── ubuntu-vm/
    │   ├── 20260310074513-vdisk1.img.zst    # Compressed backup (if BACKUP_COMPRESSION=Y)
    │   ├── 20260309074513-vdisk1.img.zst
    │   └── ...
    ├── windows-vm/
    │   ├── 20260310074513-vdisk1.img.zst
    │   ├── 20260309074513-vdisk1.img.zst
    │   └── ...
    └── ...
```

### VM Source Snapshots (`/mnt/nvme_vm_cache/domains/`)

```
/mnt/nvme_vm_cache/domains/
├── ubuntu-vm/
│   ├── vdisk1.img                                    # Original primary disk
│   ├── vdisk1.img_snapshot_20260310074513.fullsnap  # Reflink snapshot
│   ├── vdisk1.img_snapshot_20260309074513.fullsnap
│   ├── vdisk2.img                                    # Secondary disk
│   └── ...
├── windows-vm/
│   ├── vdisk1.img
│   ├── vdisk1.img_snapshot_20260310074513.fullsnap
│   └── ...
└── ...
```

## Requirements

### System Requirements

- **OS**: Linux with Bash shell (Unraid)
- **Libvirt**: Must have libvirt-client installed (provides `virsh` command)
- **Compression**: zstd must be installed if using compression
- **Tools**: Standard Unix utilities (tar, rsync, find, awk, sed, etc.)

### Filesystem Requirements

- **VM Mount Point** (`VM_MOUNTPOINT`): Must be btrfs or XFS with reflink support
  - btrfs: Fully supported
  - XFS: Must have `reflink=1` enabled
- **Backup Mount Point** (`VM_BACKUP_LOCATION`): Can be any filesystem (btrfs/XFS recommended)

### Permissions

- Script must run as **root** or with sudo privileges to:
  - Access libvirt configurations
  - Create snapshots and backups
  - Access VM disk images
  - Create directories and manage files

### Disk Space

- Sufficient space for:
  - Snapshot storage (approximately disk image size × (SNAPSHOTS / 2))
  - Backup storage (approximately disk image size × BACKUPS)
  - Log files (typically small, auto-rotated)

## Usage

### Basic Execution

```bash
./script
```

The script will:
1. Read configuration from `parameters.ini`
2. Validate all parameters
3. Perform all configured operations (snapshots, backups, libvirt backup)
4. Generate logs in `{VM_BACKUP_LOCATION}/logs/`

### Scheduling with Cron

To run backups automatically (e.g., daily at 2 AM):

```bash
0 2 * * * /path/to/script >> /var/log/vm-backup-cron.log 2>&1
```

Or for root crontab:

```bash
0 2 * * * root /path/to/script
```

### Dry Run / Debug Mode

To test the script without making changes, set in `parameters.ini`:

```ini
DEBUG_MODE="Y"
```

Then run the script. It will validate all parameters and show what would be done.

## Logging

### Log Location

All logs are stored in: `{VM_BACKUP_LOCATION}/logs/`

Filename format: `backup-YYYY-MM-DD_HHMMSS.log`

### Log Examples

```
2025-02-10 14:30:22 - INFO: Configuration parameters appear valid.
2025-02-10 14:30:23 - INFO: Determining VM snapshot targets...
2025-02-10 14:30:24 - INFO: Configuration set to snapshot ALL VMs.
2025-02-10 14:30:25 - INFO: Final list of VMs to be processed for snapshot:
2025-02-10 14:30:25 - INFO:  - ubuntu-vm
2025-02-10 14:30:25 - INFO:  - windows-vm
2025-02-10 14:30:26 - INFO: Starting VM disk snapshot process...
2025-02-10 14:30:27 - INFO: Creating reflink snapshot for '/mnt/nvme_vm_cache/domains/ubuntu-vm/vdisk1.img' -> '/mnt/nvme_vm_cache/domains/ubuntu-vm/vdisk1.img_snapshot_20250210143027.fullsnap'
2025-02-10 14:30:28 - SUCCESS: VM disk snapshot process completed.
```

### Reading Logs

View the most recent log:

```bash
tail -f /mnt/thegate/backup-vm/logs/backup-*.log | sort -r | head -1 | xargs tail -f
```

Or list all logs:

```bash
ls -lh /mnt/thegate/backup-vm/logs/
```

View a specific log file:

```bash
cat /mnt/thegate/backup-vm/logs/backup-2026-03-10_074513.log
```

## Configuring Unraid Shares for Backups

If you prefer to use an Unraid user share for backups instead of a direct cache pool path:

### Step 1: Create or Configure the Share in Unraid UI

1. Go to **Shares** → **backup-vm** (or create a new share)
2. Click **Edit** to open the share settings
3. Under **Disk Share Assignment**, assign the share to a specific disk or cache pool:
   - Select the target from the dropdown (e.g., "disk1", cache pool name, etc.)
   - This populates the `shareInclude` field in the share config file
4. Click **Save**

### Step 2: Update parameters.ini

```ini
VM_BACKUP_LOCATION="/mnt/user/backup-vm"
VM_BACKUP_MOUNTPOINT="/mnt/user"
```

### Step 3: Run the Script

The script will now:
1. Detect that the location is a user share
2. Read the share config to find the physical disk
3. Bypass the FUSE layer by using the direct disk path
4. Store backups on the physical disk for maximum performance

### Fallback Behavior

If the share config lacks a `shareInclude` value (empty disk assignment):
- The script logs a **WARNING** message
- Continues with the backup using the share path directly
- No manual intervention needed, but performance may be slightly reduced

**To fix this**: Assign a disk to the share in Unraid UI (see Step 1 above)

## Troubleshooting

### Script Fails at Startup

**Error**: "Configuration file not found"
- **Solution**: Ensure `parameters.ini` exists in the same directory as the script

**Error**: "virsh command not found"
- **Solution**: Install libvirt-client: `apt-get install libvirt-client` or your distro equivalent

**Error**: "zstd command not found"
- **Solution**: Install zstd: `apt-get install zstd` or your distro equivalent

### Mount Point Errors

**Error**: "Path is not a valid mount point"
- **Solution**: Verify the path in `parameters.ini` is a mounted filesystem
- Run: `mount | grep {path}` to verify

**Error**: "Filesystem type is not supported"
- **Solution**: Ensure VM_MOUNTPOINT uses btrfs or XFS with reflink support
- Check: `findmnt -o FSTYPE {path}`
- For XFS, verify: `xfs_info {path} | grep reflink`

### Backup Failures

**Error**: "Filesystem usage check failed"
- **Solution**: Free up disk space or increase `FILESYSTEM_MAX_PCT` threshold
- Check usage: `df -h {backup_location}`

**Error**: "VM not found in virsh list"
- **Solution**: Verify VM name is spelled correctly in `VM_BACKUP_LIST` or `VM_SNAPSHOT_LIST`
- List available VMs: `virsh list --all`

**Error**: "Failed to create snapshot"
- **Solution**: Ensure filesystem supports reflink (btrfs or XFS with reflink=1)
- Test: `cp --reflink=always {source} {test_dest}`

**Warning**: "shareInclude is empty in config file. Falling back to share path."
- **Status**: This is now handled gracefully (v1.1+)
- **What's happening**: Your backup location is a user share, but it doesn't have a physical disk assigned
- **Solution (Optional but Recommended)**: Assign a disk to the share in Unraid UI for better performance (see "Configuring Unraid Shares for Backups" section)
- **Backup Status**: Backups will still work using the share path directly, but may be slightly slower due to FUSE layer
- **Verification**: Check logs for `WARNING: 'shareInclude' is empty` message

**Error/Issue**: "Deleting file due to retention policy" immediately after backup creation
- **Status**: Fixed in v1.2
- **What was happening**: When using `cp -p --reflink` to create temporary backup files, the original disk image's modification time (weeks/months old) was preserved. When zstd compressed the file, it retained this old timestamp. The rotation function would see the newly created backup as being weeks old and immediately delete it.
- **Current behavior**: After backup compression, the file's modification time is updated to the current time via `touch` command, ensuring rotation works correctly
- **Previous versions**: If you're using v1.1 or earlier and seeing this issue, upgrade to v1.2 or manually run `touch /mnt/thegate/backup-vm/backups/*/\*.zst` to fix existing backup timestamps

## Performance Considerations

### Snapshot Performance
- **Reflink snapshots are nearly instant** and consume minimal space initially
- Actual disk space grows as modifications are made to either the original or snapshot
- Snapshots provide a quick recovery option with minimal overhead

### Backup Performance
- **Compressed backups** (zstd) reduce storage by 50-80% depending on data
- **Uncompressed backups** are faster but require more disk space
- Backup speed depends on disk I/O and CPU (for compression)

### Filesystem Recommendations
- **btrfs**: Preferred for reflink snapshots; no additional configuration needed
- **XFS**: Supported with `reflink=1` enabled; may have slightly different performance characteristics

## Common Configuration Examples

### Conservative (Minimal Storage)
```ini
SNAPSHOTS="3"
BACKUPS="3"
RETENTION_DAYS="14"
BACKUP_COMPRESSION="Y"
```

### Balanced (Recommended)
```ini
SNAPSHOTS="10"
BACKUPS="7"
RETENTION_DAYS="30"
BACKUP_COMPRESSION="Y"
```

### Aggressive (Maximum Retention)
```ini
SNAPSHOTS="20"
BACKUPS="14"
RETENTION_DAYS="90"
BACKUP_COMPRESSION="Y"
```

### Uncompressed (Maximum Speed)
```ini
BACKUP_COMPRESSION="N"
BACKUPS="3"
RETENTION_DAYS="7"
```

## Functions Reference

### Core Functions

| Function | Purpose |
|----------|---------|
| `read_input_file()` | Reads and parses `parameters.ini` |
| `setup_logging()` | Initializes logging system and creates log file |
| `validate_parameters()` | Validates all configuration parameters |
| `determine_vm_targets()` | Resolves VM names from config (ALL/NONE/list) to actual VMs |
| `mount_check()` | Verifies mount point exists and supports required filesystem |
| `filesystem_usage_check()` | Ensures filesystem usage is below safety threshold |
| `file_rotation()` | Manages file retention by age and count |
| `libvirt_backup()` | Backs up libvirt configuration directory |
| `vm_snapshot()` | Creates reflink snapshots of VM disks |
| `vm_backup()` | Backs up VM disks with optional compression |
| `log_message()` | Logs messages with timestamps |

## Safety Features

1. **Pre-execution Validation**: All parameters checked before any operations
2. **Filesystem Monitoring**: Checks disk usage before backup operations
3. **Reflink Support Verification**: Ensures filesystem supports required features (btrfs or XFS with reflink)
4. **Temporary File Cleanup**: Removes temporary files even on failure
5. **Atomic Operations**: Uses copy-on-write for safe snapshots
6. **Error Logging**: All errors logged with context for debugging
7. **Graceful Fallback**: If backup location is a user share but config is incomplete, falls back to using the share path directly instead of failing
8. **Mount Point Validation**: Verifies backup destination mount point before proceeding with operations

## License & Support

Designed for Unraid VM backup automation. For issues or improvements, review the logging output in `{VM_BACKUP_LOCATION}/logs/`.

## Version History

- **v1.2** (Current):
  - **CRITICAL FIX**: Fixed backup file rotation bug where newly created backups were immediately deleted
  - Root cause: `cp -p` preserved original disk image's old modification time, causing zstd-compressed backups to appear weeks old to the rotation function
  - Solution: Added `touch` command after backup completion to update file modification time to current time
  - Applied fix to both compressed (zstd) and uncompressed (rsync) backup paths

- **v1.1**:
  - Added graceful fallback for empty `shareInclude` values in Unraid share configs
  - Improved error messages and debug logging for share config issues
  - Enhanced documentation for backup location routing and configuration options
  - Features: reflink snapshots, compression, rotation, Unraid share support with fallback

- **v1.0**: Initial release with snapshot, backup, and libvirt backup support
  - Features: reflink snapshots, compression, rotation, basic Unraid share support
