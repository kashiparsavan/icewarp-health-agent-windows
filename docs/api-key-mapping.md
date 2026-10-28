# IceWarp Health Agent - 411-Key API Mapping

**Status:** Source of truth for the Windows implementation  
**Schema source:** `C:\Users\mrkashi\Desktop\iceauto\health.json` (411 keys, IceWarp Health Check v1.14)  
**Windows repository:** `C:\Projects\icewarp-health-agent-windows`  
**Last updated:** 2026-10-27

## 1. Purpose

This document is the permanent, authoritative mapping between the Linux
`health.json` 411-key schema and the Windows IceWarp `tool.exe` settings.
It exists so the mapping is never again reconstructed from memory or a
throw-away text file. The earlier ad-hoc `1. ALL smtp. KEYS.txt` was not
present in the repository; this document reconstructs and supersedes it from
the schema, the Windows collector source, and the Linux reference collectors.

Rules for this mapping:

1. The **Schema key** column is copied verbatim from the 411-key Linux
   `health.json`. It is the contract; do not rename keys in the Windows agent.
2. The **Windows source** column names the `tool.exe` setting, OS API, or
   computed expression used by the Windows collector.
3. A key marked `Implemented` is emitted by a collector today. A key marked
   `Planned` has a Linux reference collector but no Windows collector yet.
4. Dynamic keys (`domain.<name>.*`, `storage.<label>.*`,
   `dns.resolver.external_test_ok_<host>`, `security.rbl_self_check.zones.<zone>`)
   are shown using the concrete names from the sample `health.json`. The
   Windows agent generates the same pattern for every host/domain it sees.
5. `tool.exe` setting names are case-insensitive on Windows. This document
   preserves the spelling used in the collector source.

> **The Linux repository is read-only for this project.** This mapping is
> implemented independently in PowerShell 5.1 and must not call `tool.sh`,
> `bash`, or any Linux path.

## 2. Status legend

| Status | Meaning |
|---|---|
| **Implemented** | A Windows collector emits this key today. |
| **Implemented (dynamic)** | Emitted per domain, drive, RBL zone, or test host. |
| **Planned** | The Linux reference collector exists; the Windows collector is not written yet. |
| **Derived** | Computed from other collected keys (health evaluation, watchdog summary); not a raw setting. |
| **Unmapped** | No Linux collector or Windows source has been identified yet. |

## 3. Coverage summary

- **Schema keys:** 411
- **Implemented by the current Windows codebase (9 collectors + context):** 248
- **Remaining (planned/derived):** 163
- Implemented sections: agent/general/service/domain, IceWarp environment/version/license, SMTP, security, DNS, backup/archive, OS/system/storage.
- The largest remaining block is the 72-key `health.*` evaluation layer, which is a report engine rather than a set of `tool.exe` reads.

### Remaining keys by area

| Area | Keys remaining |
|---|---:|
| `admin.*` | 4 |
| `antispam.*` | 4 |
| `database.*` | 4 |
| `directory_cache.*` | 4 |
| `fulltext.*` | 2 |
| `health.*` | 72 |
| `http.*` | 2 |
| `icewarp.*` | 35 |
| `logging.*` | 4 |
| `monitor.*` | 8 |
| `mysql.*` | 1 |
| `queue.*` | 3 |
| `watchdog.*` | 22 |

## 4. Implemented mappings

These are the exact settings and computed sources used by the current
Windows collectors. The collector path is shown in the section heading.

### 4.1 Agent, General, Services & Domains

| Schema key | Type | Windows source | Status |
|---|---|---|---|
| `agent.hostname` | string | Agent framework: $env:COMPUTERNAME | Implemented |
| `agent.time` | string | Agent framework: Get-Date (yyyy-MM-dd HH:mm:ss) | Implemented |
| `agent.version` | string | Agent framework: VERSION file | Implemented |
| `domain.checked` | boolean | tool.exe list domain (success flag) | Implemented (dynamic) |
| `domain.count` | number | Computed: count of list domain entries | Implemented (dynamic) |
| `domain.designhost.ir.daily_send_messages_limit` | number | tool.exe display domain <domain> D_NumberLimit | Implemented (dynamic) |
| `domain.designhost.ir.disk_quota_kb` | number | tool.exe display domain <domain> D_DiskQuota | Implemented (dynamic) |
| `domain.designhost.ir.user_send_data_limit_mb_per_day` | number | tool.exe display domain <domain> D_UserMB | Implemented (dynamic) |
| `domain.list` | string | Computed: list domain entries joined with ';' | Implemented (dynamic) |
| `domain.primary.daily_send_messages_limit` | number | tool.exe display domain <primary> D_NumberLimit | Implemented (dynamic) |
| `domain.primary.name` | string | Computed: first list domain entry | Implemented (dynamic) |
| `general.company` | string | Config: CompanyName | Implemented |
| `general.date` | string | Computed: Get-Date (yyyy-MM-dd HH:mm:ss) | Implemented |
| `general.icewarp.version` | string | tool.exe display system C_Version | Implemented |
| `general.os.name` | string | CIM: Win32_OperatingSystem.Caption | Implemented |
| `general.os.pretty` | string | CIM: Win32_OperatingSystem.Caption | Implemented |
| `general.os.version` | number | CIM: Win32_OperatingSystem.Version | Implemented |
| `general.technician` | string | Config: Technician / -Technician | Implemented |
| `service.imap.active` | number | tool.exe display system C_Mail_IMAP_Active | Implemented |
| `service.pop3.active` | number | tool.exe display system C_Mail_POP_Active | Implemented |

### 4.2 IceWarp Environment, Version & License

| Schema key | Type | Windows source | Status |
|---|---|---|---|
| `icewarp.installed` | boolean | Computed: Test-Path IceWarpHome (container) | Implemented |
| `icewarp.license.file_present` | boolean | Computed: Test-Path <IceWarpHome>\license.xml + registry License value | Implemented |
| `icewarp.license.status` | string | Computed: status from status_code / file_present | Implemented |
| `icewarp.license.status_code` | number | tool.exe display system C_LicenseStatus | Implemented |
| `icewarp.license.trial_expiration` | string or null | tool.exe display system C_License_TrialExpire (+ C_License_XML fallback) | Implemented |
| `icewarp.license.type` | string | tool.exe display system C_License_Type | Implemented |
| `icewarp.tool` | string | Config: ToolPath | Implemented |
| `icewarp.tool.exists` | boolean | Computed: Test-Path ToolPath | Implemented |
| `icewarp.version` | string | tool.exe display system C_Version | Implemented |

### 4.3 SMTP

| Schema key | Type | Windows source | Status |
|---|---|---|---|
| `c_mail_smtp_other_bouncebackmode` | number | tool.exe display system c_mail_smtp_other_bouncebackmode | Implemented |
| `smtp.add_return_path` | number | tool.exe display system C_Mail_SMTP_Delivery_ReturnPath | Implemented |
| `smtp.dedupe` | number | tool.exe display system C_Mail_SMTP_Other_Dedupe | Implemented |
| `smtp.delivery_reports_enabled` | number | Computed: inverse of c_mail_smtp_other_disable_dsn | Implemented |
| `smtp.deny_vrfy` | number | tool.exe display system c_mail_security_protocols_denyvrfy | Implemented |
| `smtp.enforce_tls_secondary_port` | number | tool.exe display system C_Mail_SMTP_Delivery_EnforceTlsOnSecondarySmtpPort | Implemented |
| `smtp.global_pop_before_smtp` | number | tool.exe display system C_Mail_Security_Relay_POPSMTPGlobal | Implemented |
| `smtp.greeting_delay_seconds` | number | tool.exe display system C_Mail_Security_Protection_SMTPWait | Implemented |
| `smtp.header_footer_active` | number | tool.exe display system C_Mail_SMTP_HeaderFooter_Enable | Implemented |
| `smtp.hide_ip` | number | tool.exe display system C_Mail_SMTP_Delivery_HideIP | Implemented |
| `smtp.hide_server_version` | number | tool.exe display system C_Mail_SMTP_Delivery_HideServerVersion | Implemented |
| `smtp.incoming_queue_threads` | number | tool.exe display system C_Mail_SMTP_Delivery_IncomingQueueSize | Implemented |
| `smtp.max_client_recipients` | number | tool.exe display system C_Mail_SMTP_Other_MaxMTARecipients | Implemented |
| `smtp.max_hop_count` | number | tool.exe display system C_Mail_SMTP_Other_MaxHopCount | Implemented |
| `smtp.max_incoming_connections` | number | tool.exe display system C_System_Services_SMTP_MaxInConn | Implemented |
| `smtp.max_message_size.bytes` | number | tool.exe display system C_Mail_SMTP_Delivery_MaxMsgSize | Implemented |
| `smtp.max_message_size.enabled` | number | tool.exe display system C_Mail_SMTP_Delivery_LimitMsgSize | Implemented |
| `smtp.max_message_size.mb` | number | Computed: max_message_size.bytes / 1 MiB | Implemented |
| `smtp.max_outgoing_connections` | number | tool.exe display system C_System_Services_SMTP_MaxOutConn | Implemented |
| `smtp.max_per_domain_outgoing.enabled` | number | tool.exe display system C_System_Services_SMTP_MaxOutgoingLimitPerDomainEnabled | Implemented |
| `smtp.max_per_domain_outgoing.value` | number | tool.exe display system C_System_Services_SMTP_MaxOutgoingLimitPerDomainValue | Implemented |
| `smtp.max_per_domain_sender.enabled` | number | tool.exe display system C_System_Services_SMTP_MaxSenderLimitPerDomainEnabled | Implemented |
| `smtp.max_per_domain_sender.value` | number | tool.exe display system C_System_Services_SMTP_MaxSenderLimitPerDomainValue | Implemented |
| `smtp.max_server_recipients` | number | tool.exe display system C_Mail_SMTP_Other_MaxRecipients | Implemented |
| `smtp.mda_internal_delivery` | number | tool.exe display system C_Mail_SMTP_Delivery_MDAInternal | Implemented |
| `smtp.parallel_ip_limit` | number | tool.exe display system C_Mail_SMTP_General_ParallelIPConnectionsLimit | Implemented |
| `smtp.rdns_in_received` | number | tool.exe display system C_Mail_SMTP_Delivery_RDNSLookup | Implemented |
| `smtp.reject_auth_sender_mismatch` | number | tool.exe display system C_Mail_Security_Protection_RejectSMTPAuthSender | Implemented |
| `smtp.relay.allowed_ips` | string | tool.exe display system C_Mail_Security_Relay_IPList | Implemented |
| `smtp.relay.local_domain_only` | number | tool.exe display system C_Mail_Security_Protection_LocalDomain | Implemented |
| `smtp.relay.mode` | number | tool.exe display system C_Mail_Security_Relay_RelayMode | Implemented |
| `smtp.relay.server` | string or null | tool.exe display system C_Mail_SMTP_General_RelayMailServer | Implemented |
| `smtp.require_helo_ehlo` | number | tool.exe display system C_Mail_Security_Protection_HELOEHLO | Implemented |
| `smtp.starttls_live_test` | boolean | Computed: live SMTP STARTTLS check on port 25 | Implemented |
| `smtp.thread_cache` | number | tool.exe display system C_System_Services_SMTP_ThreadCache | Implemented |
| `smtp.use_incoming_queue` | number | tool.exe display system C_Mail_SMTP_Delivery_UseIncomingQueue | Implemented |
| `smtp.use_tls_ssl` | number | tool.exe display system C_Mail_SMTP_Delivery_UseTLSSSL | Implemented |

### 4.4 Security

| Schema key | Type | Windows source | Status |
|---|---|---|---|
| `security.antispam_live.enabled` | number | tool.exe display system C_AS_Live_Enable | Implemented |
| `security.auth_schemes.raw` | string or null | tool.exe display system C_Mail_Security_AuthScheme (see REVIEW: should be C_Accounts_Policies_Auth_Schemes) | Implemented |
| `security.cyren_folder.checked` | boolean | Computed: Test-Path <IceWarpHome>\cyren | Implemented |
| `security.cyren_folder.message` | string | Computed: Cyren folder content check | Implemented |
| `security.cyren_folder.status` | string | Computed: Cyren folder content check | Implemented |
| `security.digest_md5.enabled` | boolean or null | Computed: auth_schemes.raw contains DIGEST-MD5 | Implemented |
| `security.dnsbl.close_sessions` | number | tool.exe display system C_Mail_Security_Protection_CloseDNSBLConn | Implemented |
| `security.dnsbl.use` | number | tool.exe display system C_Mail_Security_Protection_DNSBL | Implemented |
| `security.intrusion.block_connections_per_minute.enabled` | number | tool.exe display system C_Mail_Security_Tarpit_BlockIP | Implemented |
| `security.intrusion.block_connections_per_minute.value` | number | tool.exe display system C_Mail_Security_Tarpit_BlockIPValue | Implemented |
| `security.intrusion.block_dnsbl_listed.enabled` | number | tool.exe display system C_Mail_Security_Tarpit_DNSBL | Implemented |
| `security.intrusion.block_duration_minutes` | number | tool.exe display system C_Mail_Security_Tarpit_Period | Implemented |
| `security.intrusion.block_failed_logins.enabled` | number | tool.exe display system C_Mail_Security_Tarpit_Login | Implemented |
| `security.intrusion.block_failed_logins.value` | number | tool.exe display system C_Mail_Security_Tarpit_LoginCount | Implemented |
| `security.intrusion.block_message_size.enabled` | number | tool.exe display system C_Mail_Security_Tarpit_Msg_Enabled | Implemented |
| `security.intrusion.block_message_size.value_mb` | number | tool.exe display system C_Mail_Security_Tarpit_Msg_Value | Implemented |
| `security.intrusion.block_relay_denied_count.enabled` | number | tool.exe display system C_Mail_Security_Tarpit_RelayTarpit | Implemented |
| `security.intrusion.block_relay_denied_count.value` | number | tool.exe display system C_Mail_Security_Tarpit_RelayTarpitCount | Implemented |
| `security.intrusion.block_rset_count.enabled` | number | tool.exe display system C_Mail_Security_Tarpit_RSET | Implemented |
| `security.intrusion.block_rset_count.value` | number | tool.exe display system C_Mail_Security_Tarpit_RSETCount | Implemented |
| `security.intrusion.block_spam_score.enabled` | number | tool.exe display system C_Mail_Security_Tarpit_Spam | Implemented |
| `security.intrusion.block_spam_score.raw` | number | tool.exe display system C_Mail_Security_Tarpit_SpamScore | Implemented |
| `security.intrusion.block_spam_score.value` | number | Computed: raw / 1024 | Implemented |
| `security.intrusion.block_unknown_user_count.enabled` | number | tool.exe display system C_Mail_Security_Tarpit_Recipient | Implemented |
| `security.intrusion.block_unknown_user_count.value` | number | tool.exe display system C_Mail_Security_Tarpit_RecipientCount | Implemented |
| `security.intrusion.close_all_other_connections` | number | tool.exe display system C_Mail_Security_Tarpit_CloseAllConnections | Implemented |
| `security.intrusion.close_blocked_connection` | number | tool.exe display system C_Mail_Security_Tarpit_CloseConnection | Implemented |
| `security.intrusion.cross_session_processing` | number | tool.exe display system C_Mail_Security_Tarpit_CrossSession | Implemented |
| `security.intrusion.process_pop3_imap` | number | tool.exe display system C_Mail_Security_Tarpit_EnableIMAPPOP3 | Implemented |
| `security.intrusion.process_smtp` | number | tool.exe display system C_Mail_Security_Tarpit_EnableSMTP | Implemented |
| `security.intrusion.refuse_blocked_ip` | number | tool.exe display system C_Mail_Security_Tarpit_Enable | Implemented |
| `security.intrusion.refuse_blocked_ip_source` | string | Constant: UNVERIFIED:C_Mail_Security_Tarpit_Enable | Implemented |
| `security.ip_reputation.use` | number | tool.exe display system C_AS_IPreputationUse | Implemented |
| `security.login.2fa_bypass_enabled` | number | tool.exe display system C_Accounts_Policies_Login_Bypass_2f | Implemented |
| `security.login.block_mode` | number | tool.exe display system C_Accounts_Policies_Login_Block | Implemented |
| `security.login.block_period_minutes` | number | tool.exe display system C_Accounts_Policies_Login_BlockPeriod | Implemented |
| `security.login.max_failed_attempts` | number | tool.exe display system C_Accounts_Policies_Login_Attempts | Implemented |
| `security.login.policy_enabled` | number | tool.exe display system C_Accounts_Policies_Login_Enable | Implemented |
| `security.password_policy.active` | number | tool.exe display system C_Accounts_Policies_Pass_Enable | Implemented |
| `security.password_policy.disable_access_when_expired` | number | tool.exe display system C_Accounts_Policies_Pass_DisableAccessToAllIfDisabled | Implemented |
| `security.password_policy.expiration_active` | number | tool.exe display system C_Accounts_Policies_Pass_Expiration | Implemented |
| `security.password_policy.expire_after_days` | number | tool.exe display system C_Accounts_Policies_Pass_ExpireAfter | Implemented |
| `security.password_policy.min_alpha` | number | tool.exe display system C_Accounts_Policies_Pass_Alpha | Implemented |
| `security.password_policy.min_digits` | number | tool.exe display system C_Accounts_Policies_Pass_Digits | Implemented |
| `security.password_policy.min_length` | number | tool.exe display system C_Accounts_Policies_Pass_MinLength | Implemented |
| `security.password_policy.min_non_alphanumeric` | number | tool.exe display system C_Accounts_Policies_Pass_NonAlphaNum | Implemented |
| `security.password_policy.min_uppercase` | number | tool.exe display system C_Accounts_Policies_Pass_UpperAlpha | Implemented |
| `security.password_policy.no_username_in_password` | number | tool.exe display system C_Accounts_Policies_Pass_UserAlias | Implemented |
| `security.password_policy.notify_before_days` | number | tool.exe display system C_Accounts_Policies_Pass_NotifyBefore | Implemented |
| `security.port_9001_egress.blocked` | boolean | Computed: firewall rule for TCP 9001 | Implemented |
| `security.port_9001_egress.checked` | boolean | Computed: Windows Firewall query | Implemented |
| `security.port_9001_egress.method` | string | Computed: firewall detection method | Implemented |
| `security.rbl_self_check.checked` | boolean | Computed: public IP + DNS RBL lookup | Implemented |
| `security.rbl_self_check.ip` | string | Computed: https://api.ipify.org / https://ident.me | Implemented |
| `security.rbl_self_check.listed` | boolean | Computed: any RBL hit | Implemented |
| `security.rbl_self_check.listed_on` | string or null | Computed: comma-joined RBL zones | Implemented |
| `security.rbl_self_check.zones.b_barracudacentral_org` | string | Resolve-DnsName <reversed-ip>.b.barracudacentral.org | Implemented (dynamic) |
| `security.rbl_self_check.zones.bl_spamcop_net` | string | Resolve-DnsName <reversed-ip>.bl.spamcop.net | Implemented (dynamic) |
| `security.rbl_self_check.zones.dnsbl_sorbs_net` | string | Resolve-DnsName <reversed-ip>.dnsbl.sorbs.net | Implemented (dynamic) |
| `security.rbl_self_check.zones.zen_spamhaus_org` | string | Resolve-DnsName <reversed-ip>.zen.spamhaus.org | Implemented (dynamic) |
| `security.reject_domain_no_mx` | number | tool.exe display system C_Mail_Security_Protection_RejectMX | Implemented |
| `security.reject_no_rdns` | number | tool.exe display system C_Mail_Security_Protection_RejectrDNS | Implemented |

### 4.5 DNS & Mail Flow

| Schema key | Type | Windows source | Status |
|---|---|---|---|
| `dns.configured_server` | string | tool.exe display system C_Mail_SMTP_General_DNSServer | Implemented |
| `dns.dkim.checked` | boolean | Computed: TXT lookup attempted | Implemented |
| `dns.dkim.domain` | string | Computed: lookup hostname | Implemented |
| `dns.dkim.found` | boolean | Computed: DKIM TXT record found | Implemented |
| `dns.dkim.record` | string | Resolve-DnsName <selector>._domainkey.<domain> -Type TXT | Implemented |
| `dns.dkim.selector_found` | string | Computed: first matching selector | Implemented |
| `dns.dkim.selectors_tried` | string | Constant: default,dkim,mail,selector1,selector2,k1,s1,google | Implemented |
| `dns.dmarc.checked` | boolean | Computed: TXT lookup attempted | Implemented |
| `dns.dmarc.domain` | string | Computed: lookup hostname | Implemented |
| `dns.dmarc.found` | boolean | Computed: DMARC TXT record found | Implemented |
| `dns.dmarc.policy` | string | Computed: p= value from DMARC record | Implemented |
| `dns.dmarc.policy_note` | string | Computed: p=none warning | Implemented |
| `dns.dmarc.record` | string | Resolve-DnsName _dmarc.<domain> -Type TXT | Implemented |
| `dns.lookup_test.host` | string | Config: MailHostname / MailDomain / COMPUTERNAME | Implemented |
| `dns.lookup_test.ok` | boolean | Resolve-DnsName <lookup-host> -Type A | Implemented |
| `dns.lookup_test.result` | string | Computed: A record address | Implemented |
| `dns.ptr.checked` | boolean | Computed: public IP available | Implemented |
| `dns.ptr.exists` | boolean | Computed: PTR result non-empty | Implemented |
| `dns.ptr.ip` | string | Computed: public IP (ipify/ident.me) | Implemented |
| `dns.ptr.matches_hostname` | boolean | Computed: PTR equals MailHostname | Implemented |
| `dns.ptr.result` | string | Resolve-DnsName <public-ip> -Type PTR | Implemented |
| `dns.resolver.external_test_host` | string | Constant: google.com | Implemented |
| `dns.resolver.external_test_ok` | boolean | Computed: any of google.com / icewarp.com / parsavan.com resolves | Implemented |
| `dns.resolver.external_test_ok_google_com` | boolean | Resolve-DnsName google.com -Type A | Implemented |
| `dns.resolver.external_test_ok_icewarp_com` | boolean | Resolve-DnsName icewarp.com -Type A | Implemented |
| `dns.resolver.external_test_ok_parsavan_com` | boolean | Resolve-DnsName parsavan.com -Type A | Implemented |
| `dns.spf.checked` | boolean | Computed: public IP available + TXT lookup | Implemented |
| `dns.spf.checked_ip` | string | Computed: public IP (ipify/ident.me) | Implemented |
| `dns.spf.domain` | string | Computed: lookup hostname | Implemented |
| `dns.spf.found` | boolean | Computed: SPF TXT record found | Implemented |
| `dns.spf.includes_server_ip` | boolean | Computed: SPF mechanisms vs checked IP | Implemented |
| `dns.spf.ip_coverage_via` | string | Computed: ip4/ip6/a/mx/include mechanism | Implemented |
| `dns.spf.record` | string | Resolve-DnsName <domain> -Type TXT (SPF) | Implemented |

### 4.6 Backup & Archive

| Schema key | Type | Windows source | Status |
|---|---|---|---|
| `archive.active` | number | tool.exe display system C_System_Tools_AutoArchive_Enable | Implemented |
| `archive.backup.active` | number | tool.exe display system C_System_Tools_AutoArchive_Backup_Active | Implemented |
| `archive.backup.delete_older_than_days` | number | tool.exe display system C_System_Tools_AutoArchive_Backup_DeleteOlder | Implemented |
| `archive.backup.file` | string or null | tool.exe display system C_System_Tools_AutoArchive_Backup_File | Implemented |
| `archive.delete_older_than_days` | number | tool.exe display system C_System_Tools_AutoArchive_DeleteOlder | Implemented |
| `archive.do_not_archive_rss` | number | tool.exe display system C_System_Tools_AutoArchive_RSS | Implemented |
| `archive.do_not_archive_spam` | number | tool.exe display system C_System_Tools_AutoArchive_DoNotSpam | Implemented |
| `archive.imap_folder_name` | string | tool.exe display system C_System_Tools_AutoArchive_IMAPArchiveName | Implemented |
| `archive.integrate_with_imap` | number | tool.exe display system C_System_Tools_AutoArchive_IMAPArchive | Implemented |
| `archive.trailer_path` | string | tool.exe display system C_System_Tools_AutoArchive_TrailerPath | Implemented |
| `backup.db.accounts.enabled` | number | tool.exe display system c_system_tools_backup_db_accountsenabled | Implemented |
| `backup.db.accounts.target_dsn` | string | tool.exe display system c_system_tools_backup_db_accounts | Implemented |
| `backup.db.as.enabled` | number | tool.exe display system c_system_tools_backup_db_asenabled | Implemented |
| `backup.db.as.target_dsn` | string | tool.exe display system c_system_tools_backup_db_as | Implemented |
| `backup.db.cache.enabled` | number | tool.exe display system c_system_tools_backup_db_directorycacheenabled | Implemented |
| `backup.db.cache.target_dsn` | string | tool.exe display system c_system_tools_backup_db_directorycache | Implemented |
| `backup.db.gw.enabled` | number | tool.exe display system c_system_tools_backup_db_gwenabled | Implemented |
| `backup.db.gw.target_dsn` | string | tool.exe display system c_system_tools_backup_db_gw | Implemented |
| `backup.emails.enabled` | number | tool.exe display system c_system_tools_backup_emails | Implemented |
| `icewarp.archive.default` | string | tool.exe display system C_System_Tools_AutoArchive_Path | Implemented |
| `icewarp.backup.auto_delete_after_days` | number | tool.exe display system c_system_tools_autobackup_deleteafter | Implemented |
| `icewarp.backup.auto_enabled` | number | tool.exe display system c_system_tools_autobackup_enable | Implemented |
| `icewarp.backup.auto_target` | string | tool.exe display system c_system_tools_autobackup_backupto | Implemented |
| `icewarp.backup.default` | string | Computed: <IceWarpHome>\backup | Implemented |
| `icewarp.backup.last_file` | string | Computed: newest *.zip in <IceWarpHome>\backup | Implemented |
| `icewarp.backup.last_time` | string | Computed: LastWriteTime of newest *.zip | Implemented |

### 4.7 OS, System & Storage

| Schema key | Type | Windows source | Status |
|---|---|---|---|
| `os.cpu.count` | number | CIM: Win32_Processor.NumberOfLogicalProcessors | Implemented |
| `os.cpu.load1` | number | CIM: Win32_Processor.LoadPercentage (approximation) | Implemented |
| `os.cpu.load15` | number | CIM: Win32_Processor.LoadPercentage (approximation) | Implemented |
| `os.cpu.load5` | number | CIM: Win32_Processor.LoadPercentage (approximation) | Implemented |
| `os.last_update_date` | string | CIM: Win32_QuickFixEngineering.InstalledOn | Implemented |
| `os.memory.available_kb` | number | CIM: Win32_OperatingSystem.FreePhysicalMemory (KB) | Implemented |
| `os.memory.total_kb` | number | CIM: Win32_OperatingSystem.TotalVisibleMemorySize (KB) | Implemented |
| `os.package_manager` | string | Constant: unknown | Implemented |
| `os.repository_access` | number | Constant: 0 | Implemented |
| `os.swap.free_kb` | number | CIM: (AllocatedBaseSize - CurrentUsage) * 1024 | Implemented |
| `os.swap.total_kb` | number | CIM: Win32_PageFileUsage.AllocatedBaseSize * 1024 | Implemented |
| `os.time_sync.method` | string | w32tm /query /status | Implemented |
| `os.time_sync.synced` | number | w32tm /query /status | Implemented |
| `storage.archive.device` | string | Get-PSDrive <drive>.Root | Implemented (dynamic) |
| `storage.archive.free_gb` | number | Get-PSDrive Free (bytes) / 1 GB | Implemented (dynamic) |
| `storage.archive.mount` | string | Get-PSDrive <drive>.Root | Implemented (dynamic) |
| `storage.archive.path` | string | <IceWarpHome>\archive | Implemented (dynamic) |
| `storage.archive.status` | string | Computed: OK when used_percent < 90, else WARNING | Implemented (dynamic) |
| `storage.archive.total_gb` | number | Get-PSDrive Used + Free (bytes) / 1 GB | Implemented (dynamic) |
| `storage.archive.used_gb` | number | Get-PSDrive Used (bytes) / 1 GB | Implemented (dynamic) |
| `storage.archive.used_percent` | number | Computed: used / total * 100 | Implemented (dynamic) |
| `storage.install.device` | string | Get-PSDrive <drive>.Root | Implemented (dynamic) |
| `storage.install.free_gb` | number | Get-PSDrive Free (bytes) / 1 GB | Implemented (dynamic) |
| `storage.install.mount` | string | Get-PSDrive <drive>.Root | Implemented (dynamic) |
| `storage.install.path` | string | <IceWarpHome> | Implemented (dynamic) |
| `storage.install.status` | string | Computed: OK when used_percent < 90, else WARNING | Implemented (dynamic) |
| `storage.install.total_gb` | number | Get-PSDrive Used + Free (bytes) / 1 GB | Implemented (dynamic) |
| `storage.install.used_gb` | number | Get-PSDrive Used (bytes) / 1 GB | Implemented (dynamic) |
| `storage.install.used_percent` | number | Computed: used / total * 100 | Implemented (dynamic) |
| `storage.mail.device` | string | Get-PSDrive <drive>.Root | Implemented (dynamic) |
| `storage.mail.free_gb` | number | Get-PSDrive Free (bytes) / 1 GB | Implemented (dynamic) |
| `storage.mail.mount` | string | Get-PSDrive <drive>.Root | Implemented (dynamic) |
| `storage.mail.path` | string | <IceWarpHome>\mail | Implemented (dynamic) |
| `storage.mail.status` | string | Computed: OK when used_percent < 90, else WARNING | Implemented (dynamic) |
| `storage.mail.total_gb` | number | Get-PSDrive Used + Free (bytes) / 1 GB | Implemented (dynamic) |
| `storage.mail.used_gb` | number | Get-PSDrive Used (bytes) / 1 GB | Implemented (dynamic) |
| `storage.mail.used_percent` | number | Computed: used / total * 100 | Implemented (dynamic) |
| `storage.root_fs.device` | string | Get-PSDrive <drive>.Root | Implemented (dynamic) |
| `storage.root_fs.free_gb` | number | Get-PSDrive Free (bytes) / 1 GB | Implemented (dynamic) |
| `storage.root_fs.mount` | string | Get-PSDrive <drive>.Root | Implemented (dynamic) |
| `storage.root_fs.path` | string | SystemDrive (for example C:\) | Implemented (dynamic) |
| `storage.root_fs.status` | string | Computed: OK when used_percent < 90, else WARNING | Implemented (dynamic) |
| `storage.root_fs.total_gb` | number | Get-PSDrive Used + Free (bytes) / 1 GB | Implemented (dynamic) |
| `storage.root_fs.used_gb` | number | Get-PSDrive Used (bytes) / 1 GB | Implemented (dynamic) |
| `storage.root_fs.used_percent` | number | Computed: used / total * 100 | Implemented (dynamic) |
| `storage.root_home.device` | string | Get-PSDrive <drive>.Root | Implemented (dynamic) |
| `storage.root_home.free_gb` | number | Get-PSDrive Free (bytes) / 1 GB | Implemented (dynamic) |
| `storage.root_home.mount` | string | Get-PSDrive <drive>.Root | Implemented (dynamic) |
| `storage.root_home.path` | string | <SystemDrive>\Users | Implemented (dynamic) |
| `storage.root_home.status` | string | Computed: OK when used_percent < 90, else WARNING | Implemented (dynamic) |
| `storage.root_home.total_gb` | number | Get-PSDrive Used + Free (bytes) / 1 GB | Implemented (dynamic) |
| `storage.root_home.used_gb` | number | Get-PSDrive Used (bytes) / 1 GB | Implemented (dynamic) |
| `storage.root_home.used_percent` | number | Computed: used / total * 100 | Implemented (dynamic) |
| `system.swap.history` | string or null | Constant: null | Implemented |
| `system.swap.message` | string | Computed: pagefile usage message | Implemented |
| `system.swap.status` | string | Computed: CRITICAL when pagefile used > 3%, else PASS | Implemented |
| `system.swap.total_kb` | number | Computed: pagefile allocated KB | Implemented |
| `system.swap.used_kb` | number | Computed: pagefile used KB | Implemented |
| `system.swap.used_percent` | number | Computed: used / total * 100 | Implemented |

## 5. Remaining and planned mappings

These keys are in the 411-key schema but are not yet emitted by the
Windows agent. The Linux reference is shown so the future collector has a
starting point. Setting names in this section are extracted from the Linux
collectors and **must be verified on Windows** before use. Hints are shown
only where the Linux collector reads the setting inline; they are candidates,
not verified Windows mappings.

### 5.1 IceWarp Environment, License, SSL, Migration & Updates

| Schema key | Type | Planned Windows source / Linux reference | Status |
|---|---|---|---|
| `icewarp.antispam.ever_updated` | boolean | Linux: `collectors\icewarp\antispam.sh` | Planned |
| `icewarp.antispam.last_update` | string | Linux: `collectors\icewarp\antispam.sh` | Planned |
| `icewarp.antispam.last_update_size_bytes` | number | Linux: `collectors\icewarp\antispam.sh` | Planned |
| `icewarp.antispam.last_update_source` | string | Linux: `collectors\icewarp\antispam.sh` | Planned |
| `icewarp.antispam.update_version` | number | Linux: `collectors\icewarp\antispam.sh` | Planned |
| `icewarp.antivirus.db_version` | string | Linux: `collectors\icewarp\antivirus.sh` | Planned |
| `icewarp.antivirus.last_update` | string | Linux: `collectors\icewarp\antivirus.sh` | Planned |
| `icewarp.antivirus.last_update_size_bytes` | number | Linux: `collectors\icewarp\antivirus.sh` | Planned |
| `icewarp.antivirus.last_update_source` | string | Linux: `collectors\icewarp\antivirus.sh` | Planned |
| `icewarp.cloud_api.autoconfigure` | number | Linux: `collectors\icewarp\cloud_features.sh`; setting hint `C_CloudAPI_AutoConfigure` | Planned |
| `icewarp.config` | string | Linux: `collectors\icewarp\env.sh` | Planned |
| `icewarp.dkim.active_flag` | boolean | Linux: `collectors\dns\dkim.sh` | Planned |
| `icewarp.home` | string | Linux: `collectors\icewarp\env.sh` | Planned |
| `icewarp.license.seats_info_available` | boolean | Linux: `collectors\icewarp\license_seats.sh` | Implemented |
| `icewarp.license.used_seats_note` | string | Linux: `collectors\icewarp\license_seats.sh` | Implemented |
| `icewarp.logs.default` | string | Linux: `collectors\icewarp\env.sh` | Planned |
| `icewarp.mail.default` | string | Linux: `collectors\icewarp\env.sh` | Planned |
| `icewarp.migration.active` | number | Linux: `collectors\icewarp\migration.sh`; setting hint `C_System_Tools_Migration_Active` | Planned |
| `icewarp.migration.has_errors` | boolean | Linux: `collectors\icewarp\migration.sh` | Planned |
| `icewarp.migration.server` | string or null | Linux: `collectors\icewarp\migration.sh`; setting hint `C_System_Tools_Migration_Server` | Planned |
| `icewarp.migration.stat_errors` | number | Linux: `collectors\icewarp\migration.sh` | Planned |
| `icewarp.migration.stat_start_raw` | number | Linux: `collectors\icewarp\migration.sh` | Planned |
| `icewarp.migration.stat_started` | boolean | Linux: `collectors\icewarp\migration.sh` | Planned |
| `icewarp.path.archive` | string | Linux: `collectors\icewarp\storage_paths.sh` | Planned |
| `icewarp.path.logs` | string | Linux: `collectors\icewarp\storage_paths.sh` | Planned |
| `icewarp.path.mail` | string | Linux: `collectors\icewarp\storage_paths.sh` | Planned |
| `icewarp.path.source` | string | Linux: `collectors\icewarp\storage_paths.sh` | Planned |
| `icewarp.path.temp` | string | Linux: `collectors\icewarp\storage_paths.sh` | Planned |
| `icewarp.session_timeout_minutes` | number | Linux: `collectors\icewarp\session_timeout.sh`; setting hint `C_System_Adv_Protocols_SessionTimeOut` | Planned |
| `icewarp.ssl.cert_path` | string | Linux: `collectors\icewarp\certificate.sh` | Planned |
| `icewarp.ssl.days_left` | number | Linux: `collectors\icewarp\certificate.sh` | Planned |
| `icewarp.ssl.expiration` | string | Linux: `collectors\icewarp\certificate.sh` | Planned |
| `icewarp.ssl.live_check_host` | string | Linux: `collectors\icewarp\certificate.sh` | Planned |
| `icewarp.ssl.source` | string | Linux: `collectors\icewarp\certificate.sh` | Planned |
| `icewarp.temp.default` | string | Linux: `collectors\icewarp\env.sh` | Planned |

### 5.2 Admin, HTTP, Queue, Logging, Monitor & Watchdog

| Schema key | Type | Planned Windows source / Linux reference | Status |
|---|---|---|---|
| `admin.port_changed_from_default` | boolean | Linux: `collectors\icewarp\admin_access.sh` | Planned |
| `admin.port_raw` | number | Linux: `collectors\icewarp\admin_access.sh` | Planned |
| `admin.url` | string | Linux: `collectors\icewarp\admin_access.sh` | Planned |
| `admin.url_changed_from_default` | boolean | Linux: `collectors\icewarp\admin_access.sh` | Planned |
| `http.max_connections` | string | Linux: `collectors\http\max_connections.sh` | Planned |
| `http.port` | number | Linux: `collectors\http\port.sh` | Planned |
| `logging.auth_log_level` | number | Linux: `collectors\logging\sql_auth_log.sh`; setting hint `C_Accounts_Global_Accounts_AuthLog` | Planned |
| `logging.mailqueue.level` | number | Linux: `collectors\logging\mailqueue.sh` | Planned |
| `logging.maintenance_log_level` | number | Linux: `collectors\logging\sql_auth_log.sh`; setting hint `C_Accounts_Global_Accounts_MaintenanceLog` | Planned |
| `logging.sql_log_type` | number | Linux: `collectors\logging\sql_auth_log.sh`; setting hint `C_System_SQLLogType` | Planned |
| `monitor.alert_email` | string or null | Linux: `collectors\icewarp\system_monitor.sh`; setting hint `C_System_Tools_Monitor_ReportAddress` | Planned |
| `monitor.cpu.threshold_minutes` | number | Linux: `collectors\icewarp\system_monitor.sh`; setting hint `C_System_Tools_Monitor_CPUUsagePeriod` | Planned |
| `monitor.cpu.threshold_percent` | number | Linux: `collectors\icewarp\system_monitor.sh` | Planned |
| `monitor.disk.alert_below_mb` | number | Linux: `collectors\icewarp\system_monitor.sh`; setting hint `C_System_Tools_Monitor_DiskSize` | Planned |
| `monitor.enabled` | number | Linux: `collectors\icewarp\system_monitor.sh`; setting hint `C_System_Tools_Monitor_Enable` | Planned |
| `monitor.memory.alert_below_gb` | number | Linux: `collectors\icewarp\system_monitor.sh` | Planned |
| `monitor.memory.alert_below_kb` | number | Linux: `collectors\icewarp\system_monitor.sh` | Planned |
| `monitor.web_threadpool.alert_seconds` | number | Linux: `collectors\icewarp\system_monitor.sh`; setting hint `C_System_Tools_Monitor_WebThreadPoolThreshold` | Planned |
| `queue.smtp.incoming.enabled` | number | Linux: `collectors\queue\incoming_queue_enabled.sh` | Planned |
| `queue.smtp.incoming.size` | number | Linux: `collectors\queue\incoming_queue.sh` | Planned |
| `queue.smtp.no_retry` | number | Linux: `collectors\queue\no_retry.sh` | Planned |
| `watchdog.check_iplist` | number or null | Linux: `collectors\icewarp\watchdog_extra.sh`; setting hint `C_System_Tools_Watchdog_Check_IPList` | Planned |
| `watchdog.check_protocols` | number | Linux: `collectors\icewarp\watchdog.sh`; setting hint `C_System_Tools_Watchdog_Check_Protocols` | Planned |
| `watchdog.control` | number | Linux: `collectors\icewarp\watchdog_extra.sh`; setting hint `C_System_Tools_Watchdog_Control` | Planned |
| `watchdog.cpu.message` | string | Derived: `collectors/watchdog/watchdog_percentage.sh` - not ported | Derived |
| `watchdog.cpu.status` | string | Derived: `collectors/watchdog/watchdog_percentage.sh` - not ported | Derived |
| `watchdog.disk.message` | string | Derived: `collectors/watchdog/watchdog_percentage.sh` - not ported | Derived |
| `watchdog.disk.status` | string | Derived: `collectors/watchdog/watchdog_percentage.sh` - not ported | Derived |
| `watchdog.gw` | number | Linux: `collectors\icewarp\watchdog_extra.sh`; setting hint `C_System_Tools_Watchdog_GW` | Planned |
| `watchdog.im` | number | Linux: `collectors\icewarp\watchdog_extra.sh`; setting hint `C_System_Tools_WatchDog_IM` | Planned |
| `watchdog.interval_minutes` | number | Linux: `collectors\icewarp\watchdog_extra.sh`; setting hint `C_System_Tools_Watchdog_Int` | Planned |
| `watchdog.memory.message` | string | Derived: `collectors/watchdog/watchdog_percentage.sh` - not ported | Derived |
| `watchdog.memory.status` | string | Derived: `collectors/watchdog/watchdog_percentage.sh` - not ported | Derived |
| `watchdog.os_update.message` | string | Derived: `collectors/watchdog/watchdog_percentage.sh` - not ported | Derived |
| `watchdog.os_update.status` | string | Derived: `collectors/watchdog/watchdog_percentage.sh` - not ported | Derived |
| `watchdog.pop3` | number | Linux: `collectors\icewarp\watchdog.sh`; setting hint `C_System_Tools_WatchDog_POP3` | Planned |
| `watchdog.remoteserver.down_after_minutes` | number | Linux: `collectors\icewarp\watchdog_extra.sh`; setting hint `C_System_Tools_RemoteServer_MoreThan` | Planned |
| `watchdog.remoteserver.enable` | number | Linux: `collectors\icewarp\watchdog_extra.sh`; setting hint `C_System_Tools_RemoteServer_Enable` | Planned |
| `watchdog.remoteserver.notify_when_back` | number | Linux: `collectors\icewarp\watchdog_extra.sh`; setting hint `C_System_Tools_RemoteServer_NotifyAgain` | Planned |
| `watchdog.remoteserver.report_email` | string or null | Linux: `collectors\icewarp\watchdog_extra.sh`; setting hint `C_System_Tools_RemoteServer_Email` | Planned |
| `watchdog.smtp` | number | Linux: `collectors\icewarp\watchdog.sh`; setting hint `C_System_Tools_WatchDog_SMTP` | Planned |
| `watchdog.summary.overall` | string | Derived: `collectors/watchdog/watchdog_percentage.sh` - not ported | Derived |
| `watchdog.summary.warnings` | number | Derived: `collectors/watchdog/watchdog_percentage.sh` - not ported | Derived |

### 5.3 Data Stores & Indexing

| Schema key | Type | Planned Windows source / Linux reference | Status |
|---|---|---|---|
| `antispam.bypass_local_domains` | number | Linux: `collectors\security\antispam_policy.sh`; setting hint `C_AS_BypassLocalDomains` | Planned |
| `antispam.bypass_local_ips` | number | Linux: `collectors\security\antispam_policy.sh`; setting hint `C_AS_BypassLocalIPs` | Planned |
| `antispam.max_threads` | number | Linux: `collectors\security\antispam_policy.sh`; setting hint `C_AS_SpamMaxThreads` | Planned |
| `antispam.mode` | number | Linux: `collectors\security\antispam_policy.sh`; setting hint `C_AS_General_AntispamMode` | Planned |
| `database.connection_string_raw` | string | Linux: `collectors\icewarp\database_type.sh` | Planned |
| `database.mysql_server_section_applicable` | string | Linux: `collectors\icewarp\database_type.sh` | Planned |
| `database.scope` | string | Linux: `collectors\icewarp\database_type.sh` | Planned |
| `database.type` | string | Linux: `collectors\icewarp\database_type.sh` | Planned |
| `directory_cache.connection_string` | string | Linux: `collectors\icewarp\directory_cache.sh` | Planned |
| `directory_cache.next_run` | string | Linux: `collectors\icewarp\directory_cache.sh` | Planned |
| `directory_cache.schedule_raw` | string | Linux: `collectors\icewarp\directory_cache.sh` | Planned |
| `directory_cache.scheduled` | boolean | Linux: `collectors\icewarp\directory_cache.sh` | Planned |
| `fulltext.enabled` | number | Linux: `collectors\fulltext\enabled.sh` | Planned |
| `fulltext.scanner.queues` | string or null | Linux: `collectors\fulltext\scanner_queue.sh` | Planned |
| `mysql.applicable` | boolean | Linux: `collectors\icewarp\mysql_server.sh` | Planned |

### 5.4 Health Evaluation

| Schema key | Type | Planned Windows source / Linux reference | Status |
|---|---|---|---|
| `health.access.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.access.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.auto.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.auto.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.db.accounts.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.db.accounts.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.db.as.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.db.as.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.db.cache.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.db.cache.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.db.gw.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.db.gw.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.db.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.db.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.last_time.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.last_time.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.backup.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.cpu.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.cpu.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.database.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.database.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.digest_md5.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.digest_md5.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.directory_cache.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.directory_cache.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.disk.archive.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.disk.install.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.disk.mail.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.disk.overall.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.disk.overall.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.disk.root_fs.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.disk.root_fs.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.disk.root_home.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.login_blocking.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.login_blocking.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.mail_flow.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.mail_flow.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.memory.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.memory.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.monitor.enabled.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.monitor.enabled.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.monitoring.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.monitoring.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.os_update.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.os_update.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.password_policy.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.password_policy.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.resources.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.resources.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.summary.failed` | number | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.summary.overall` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.summary.total_checks` | number | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.summary.warnings` | number | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.threat.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.threat.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.tls.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.tls.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.tls_delivery.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.tls_delivery.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.watchdog.control.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.watchdog.control.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.watchdog.gw.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.watchdog.gw.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.watchdog.im.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.watchdog.im.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.watchdog.interval.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.watchdog.interval.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.watchdog.pop3.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.watchdog.pop3.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.watchdog.smtp.message` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |
| `health.watchdog.smtp.result` | string | Derived: `lib/health.sh` `evaluate_health()` - not ported | Derived |

## 6. Dynamic key templates

The schema sample contains concrete values, but four families are dynamic.
The Windows agent must emit one block per discovered value, using the same
sanitization rules as the Linux collectors.

| Schema family | Template | Sanitization |
|---|---|---|
| Domains | `domain.<domain>.<field>` | Strip spaces and tabs only (Linux behavior). Fields: `daily_send_messages_limit`, `disk_quota_kb`, `user_send_data_limit_mb_per_day`. |
| Storage | `storage.<label>.<field>` | Fixed labels: `root_fs`, `root_home`, `install`, `mail`, `archive`. Fields: `device`, `mount`, `path`, `status`, `total_gb`, `used_gb`, `free_gb`, `used_percent`. |
| RBL zones | `security.rbl_self_check.zones.<zone>` | Dots become underscores (`zen.spamhaus.org` -> `zen_spamhaus_org`). |
| Resolver hosts | `dns.resolver.external_test_ok_<host>` | Dots become underscores (`google.com` -> `google_com`). |

## 7. Corrections applied in the Windows implementation

The Windows implementation now follows the Linux writer and the 411-key
contract:

- **Types:** `windows/lib/Json.ps1` sorts keys, turns empty strings into
  `null`, emits digit-only strings as JSON numbers (preserving the original
  numeric text), turns the exact strings `true`/`false` into JSON booleans,
  and writes atomically. Boolean settings whose schema type is number are
  normalized to `1`/`0` by `ConvertTo-AgentNumericFlag`.
- **`domain.list`:** joined with `;` after every domain, including the last
  one (`designhost.ir;`).
- **License:** all 7 schema keys are emitted, including
  `seats_info_available` and `used_seats_note`. The non-schema `file_path`
  and `trial_expiration_source` keys are gone.
- **Non-schema keys:** the context emits only `agent.version`,
  `agent.hostname`, `agent.time`, `general.technician` and `general.company`.
  The `security.rbl_self_check.reason` key is gone.
- **OS/storage math:** `os.memory.available_kb` is not divided by 1024;
  `os.memory.total_kb` uses `TotalVisibleMemorySize` (KB), with
  `Win32_ComputerSystem.TotalPhysicalMemory` only as a fallback;
  `storage.*_gb` converts `Get-PSDrive` bytes directly to GB; drive matching
  normalizes `C:` and `C:\`; a missing drive is reported as `UNKNOWN`.
- **CPU:** `os.cpu.count` is the sum of `NumberOfLogicalProcessors`, not the
  socket count.
- **DNS:** DKIM queries `<selector>._domainkey.<domain>`, DMARC queries
  `_dmarc.<domain>`, PTR reads `NameHost`, multi-chunk TXT records are
  joined, and SPF/DMARC are selected by record type. SPF matching parses
  `ip4`/`ip6` CIDR, `+a` and `+mx` mechanisms.
- **SMTP STARTTLS:** the collector issues `EHLO`, verifies that the server
  advertises `STARTTLS`, issues `STARTTLS`, then performs the bounded TLS
  handshake. Connect, read and handshake timeouts are enforced.
- **Security:** RBL queries use `<reversed-ip>.<zone>`; the firewall check
  uses `Get-NetFirewallRule` + `Get-NetFirewallPortFilter` for enabled
  outbound `Block` rules; auth schemes read
  `C_Accounts_Policies_Auth_Schemes`.
- **`general.os.version`:** Windows emits the numeric major.minor pair
  (`10.0`); the full build stays in `general.os.name`/`pretty`.
- **`smtp.max_message_size.mb`:** integral MB values are emitted without a
  trailing `.0`.

Remaining work is the 163 schema keys listed as planned/derived in the
mapping above.
## 8. Verification

To verify this document against the schema:

```powershell
$schema = (Get-Content -Raw C:\Users\mrkashi\Desktop\iceauto\health.json | ConvertFrom-Json)
$keys = $schema.PSObject.Properties.Name
$keys.Count  # must be 411
```

To verify a collector run:

```powershell
cd C:\Projects\icewarp-health-agent-windows\windows
.\agent.ps1 -Report
```

The generated `output\health.json` must contain the same keys as the schema.
Dynamic keys are compared by template, not by the sample host name.

