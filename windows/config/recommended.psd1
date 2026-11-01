# IceWarp recommended configuration (Windows).
# One key=value per line. Lines starting with # are comments.
# Used by lib/Configurator.ps1 for dry-run comparison and -Apply.

# --- Intrusion Prevention: block thresholds ---
security.intrusion.block_connections_per_minute.value = 50
security.intrusion.block_unknown_user_count.value = 5
security.intrusion.block_relay_denied_count.value = 5
security.intrusion.block_rset_count.value = 5
security.intrusion.block_spam_score.value = 9.00
security.intrusion.block_dnsbl_listed.enabled = 1
security.intrusion.block_failed_logins.value = 5
security.intrusion.block_duration_minutes = 360
security.intrusion.refuse_blocked_ip = 1
security.intrusion.close_blocked_connection = 1
security.intrusion.close_all_other_connections = 1
security.intrusion.cross_session_processing = 1
security.intrusion.process_smtp = 1
security.intrusion.process_pop3_imap = 1

# --- Rejection Rules and Access ---
security.dnsbl.use = 1
security.dnsbl.close_sessions = 1
security.ip_reputation.use = 1
security.reject_no_rdns = 1
security.reject_domain_no_mx = 1
smtp.relay.local_domain_only = 1
monitor.alert_email = customers-stat@parsavan.com
admin.port_changed_from_default = 1
security.port_9001_egress.blocked = 1

# --- Archive ---
archive.active = 1

# --- Protocol and Access Hardening ---
smtp.deny_vrfy = 1
security.digest_md5.enabled = 0
icewarp.session_timeout_minutes = 30
smtp.use_tls_ssl = 1
icewarp.cloud_api.autoconfigure = 0
service.imap.active = 0
service.pop3.active = 0
watchdog.smtp = 1
watchdog.pop3 = 1
watchdog.im = 1
watchdog.gw = 1
watchdog.interval_minutes = 5

# --- SMTP Delivery Settings ---
smtp.max_message_size.mb = 50
smtp.delivery_reports_enabled = 1
smtp.use_tls_ssl = 1
smtp.use_incoming_queue = 1
smtp.mda_internal_delivery = 1
smtp.incoming_queue_threads = 10
smtp.hide_ip = 1
smtp.hide_server_version = 1

# --- SMTP Protocol Hardening ---
smtp.require_helo_ehlo = 1
smtp.add_return_path = 1
smtp.dedupe = 1
smtp.relay.local_domain_only = 1
smtp.rdns_in_received = 1
directory_cache.scheduled = 1
admin.url_changed_from_default = 1

# --- Storage, Certificates and Services ---
fulltext.enabled = 0
smtp.reject_auth_sender_mismatch = 1

# --- Backup, Watchdog and Monitoring ---
icewarp.backup.auto_enabled = 1
backup.db.accounts.enabled = 1
backup.db.as.enabled = 1
backup.db.gw.enabled = 1
watchdog.control = 1
watchdog.remoteserver.enable = 1
monitor.enabled = 1

# --- Logging ---
logging.auth_log_level = 1
logging.maintenance_log_level = 1
logging.mailqueue.level = 1
logging.sql_log_type = 1