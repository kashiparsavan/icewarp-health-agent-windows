###############################################################################
#
# Windows IceWarp Health Agent - Example Configuration
#
# Copy this file to agent.local.psd1 and edit the site-specific values.
# agent.local.psd1 is ignored by Git.
#
# Paths may be absolute or relative to the windows/ directory.
#
###############################################################################

@{
    # IceWarp installation and command-line tool.
    IceWarpHome             = 'C:\Program Files\IceWarp'
    ToolPath                = 'C:\Program Files\IceWarp\tool.exe'
    ToolTimeoutSeconds      = 10
    CollectorTimeoutSeconds = 120
    NetworkTimeoutSeconds   = 10

    # Agent output. Both are relative to windows/ by default.
    OutputJson         = 'output\health.json'
    LogDirectory       = 'logs'

    # Monitor health configuration (used by the Health Evaluation Engine).
    MonitorDiskAlertMb               = 5120
    MonitorCpuThresholdPercent       = 50
    MonitorMemoryAlertKb             = 1048576
    MonitorWebThreadpoolAlertSeconds = 300

    # Report identity. The technician can also be overridden with -Technician.
    CompanyName        = ''
    Technician         = 'Parsavan'
    ChecklistVersion   = '1.14'

    # Mail hostname used for SPF/DKIM/DMARC lookups and the live SMTP
    # STARTTLS test. MailDomain is the fallback when MailHostname is empty.
    MailHostname       = ''
    MailDomain         = ''
}
