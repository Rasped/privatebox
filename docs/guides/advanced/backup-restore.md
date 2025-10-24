# How-to: Backup and restore your configuration

This guide explains how to create and restore a backup of your PrivateBox's critical service configurations.

## 1. Understanding backups

Regular backups are essential for peace of mind. The PrivateBox backup process saves the configuration files for all core services, including:

*   OPNsense (firewall rules, VLANs, etc.)
*   AdGuard Home (blocklists and settings)
*   Semaphore (automation tasks)
*   And all other supporting services.

**What is not backed up:** This process does not back up the underlying operating system (Proxmox) or the full virtual machine images. It only backs up the service *configurations*.

---

## 2. Creating a backup

### Step 1: Run the backup task

1.  Access your Semaphore dashboard at `https://semaphore.lan`.
2.  Navigate to **Task Templates** in the left-hand menu.
3.  Find the template named **`System: Create Backup`** and click the blue **Run (`>`)** button.

This will create a single, compressed backup file containing all your service configurations.

### Step 2: Download your backup file

Backups are stored on the PrivateBox itself. For a backup to be useful in a hardware failure scenario, you must download it and store it somewhere safe, like your personal computer or a secure cloud storage provider.

1.  *(Instructions on how to access the local backup directory via SFTP or a file browser will be added here.)*
2.  Download the backup file (e.g., `privatebox-backup-2025-10-18.tar.gz`).
3.  Store it in at least one other safe location.

---

## 3. Restoring from a backup

This process is used to recover your settings on a new or freshly reset PrivateBox.

### Prerequisite

To restore from a backup, you must be starting from a **freshly installed PrivateBox**. The restore task is designed to apply a saved configuration to a clean system; it is not designed to "roll back" an existing system.

### Step 1: Upload your backup file

Before you can restore, you must upload a previously saved backup file to your new PrivateBox.

1.  *(Instructions on how to upload the backup file to the correct directory will be added here.)*

### Step 2: Run the restore task

1.  Access your Semaphore dashboard at `https://semaphore.lan`.
2.  Navigate to **Task Templates**.
3.  Find and run the template named **`System: Restore from Backup`**.

**Warning:** This process will overwrite any current configurations on the device with the data from your backup file.

Once the task is complete, your PrivateBox will be configured exactly as it was when the backup was created.
