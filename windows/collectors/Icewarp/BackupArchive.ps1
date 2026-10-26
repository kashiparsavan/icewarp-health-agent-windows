#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp backup and archive settings.

.DESCRIPTION
Maps to the backup.* and archive.* sections of the Linux health.json
schema. Produces exactly the same keys the Linux collectors produce,
nothing more and nothing less. The database backup flags and DSNs are
read through the shared IceWarp tool wrapper; the last backup run is
discovered by scanning the backup directory for the newest .zip.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

# --- Database backups ---
$data['backup.db.accounts.enabled'] = (Get-IceWarpSetting -Name 'c_system_tools_backup_db_accountsenabled' -Context $Context)
$data['backup.db.accounts.target_dsn'] = (Get-IceWarpSetting -Name 'c_system_tools_backup_db_accounts' -Context $Context)
$data['backup.db.as.enabled'] = (Get-IceWarpSetting -Name 'c_system_tools_backup_db_asenabled' -Context $Context)
$data['backup.db.as.target_dsn'] = (Get-IceWarpSetting -Name 'c_system_tools_backup_db_as' -Context $Context)
$data['backup.db.cache.enabled'] = (Get-IceWarpSetting -Name 'c_system_tools_backup_db_directorycacheenabled' -Context $Context)
$data['backup.db.cache.target_dsn'] = (Get-IceWarpSetting -Name 'c_system_tools_backup_db_directorycache' -Context $Context)
$data['backup.db.gw.enabled'] = (Get-IceWarpSetting -Name 'c_system_tools_backup_db_gwenabled' -Context $Context)
$data['backup.db.gw.target_dsn'] = (Get-IceWarpSetting -Name 'c_system_tools_backup_db_gw' -Context $Context)
$data['backup.emails.enabled'] = (Get-IceWarpSetting -Name 'c_system_tools_backup_emails' -Context $Context)

# --- Automatic backup policy ---
$data['icewarp.backup.auto_enabled'] = (Get-IceWarpSetting -Name 'c_system_tools_autobackup_enable' -Context $Context)
$data['icewarp.backup.auto_target'] = (Get-IceWarpSetting -Name 'c_system_tools_autobackup_backupto' -Context $Context)
$data['icewarp.backup.auto_delete_after_days'] = (Get-IceWarpSetting -Name 'c_system_tools_autobackup_deleteafter' -Context $Context)
$data['icewarp.backup.default'] = (Join-Path $Context.Config.IceWarpHome 'backup')

# --- Last backup run: scan the backup directory for the newest .zip ---
$lastFile = ''
$lastTime = ''
try {
    $backupDir = Join-Path $Context.Config.IceWarpHome 'backup'
    $latest = (Get-ChildItem -LiteralPath $backupDir -Filter '*.zip' -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1)
    if ($latest) {
        $lastFile = $latest.FullName
        $lastTime = $latest.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    }
} catch {
    # Backup directory missing or inaccessible - leave both empty.
}
$data['icewarp.backup.last_file'] = $lastFile
$data['icewarp.backup.last_time'] = $lastTime

# --- Auto-archive settings ---
$data['archive.active'] = (Get-IceWarpSetting -Name 'C_System_Tools_AutoArchive_Enable' -Context $Context)
$data['archive.backup.active'] = (Get-IceWarpSetting -Name 'C_System_Tools_AutoArchive_Backup_Active' -Context $Context)
$data['archive.backup.delete_older_than_days'] = (Get-IceWarpSetting -Name 'C_System_Tools_AutoArchive_Backup_DeleteOlder' -Context $Context)
$data['archive.backup.file'] = (Get-IceWarpSetting -Name 'C_System_Tools_AutoArchive_Backup_File' -Context $Context)
$data['archive.delete_older_than_days'] = (Get-IceWarpSetting -Name 'C_System_Tools_AutoArchive_DeleteOlder' -Context $Context)
$data['archive.do_not_archive_rss'] = (Get-IceWarpSetting -Name 'C_System_Tools_AutoArchive_RSS' -Context $Context)
$data['archive.do_not_archive_spam'] = (Get-IceWarpSetting -Name 'C_System_Tools_AutoArchive_DoNotSpam' -Context $Context)
$data['archive.imap_folder_name'] = (Get-IceWarpSetting -Name 'C_System_Tools_AutoArchive_IMAPArchiveName' -Context $Context)
$data['archive.integrate_with_imap'] = (Get-IceWarpSetting -Name 'C_System_Tools_AutoArchive_IMAPArchive' -Context $Context)
$data['archive.trailer_path'] = (Get-IceWarpSetting -Name 'C_System_Tools_AutoArchive_TrailerPath' -Context $Context)
$data['icewarp.archive.default'] = (Get-IceWarpSetting -Name 'C_System_Tools_AutoArchive_Path' -Context $Context)

return $data