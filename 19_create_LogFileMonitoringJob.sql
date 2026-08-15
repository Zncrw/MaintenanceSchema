USE msdb;
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Maintenance - LogFileMonitor')
    EXEC msdb.dbo.sp_delete_job @job_name = N'Maintenance - LogFileMonitor';
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = N'Maintenance - LogFileMonitor')
    EXEC dbo.sp_delete_schedule @schedule_name = N'Maintenance - LogFileMonitor', @force_delete = 1;
GO

-- 3) Vytvoř job
EXEC dbo.sp_add_job
    @job_name    = N'Maintenance - LogFileMonitor',
    @enabled     = 1,
    @description = N'Monitors all transaction logs size vs MAXSIZE; alerts on state escalation. Calls [DBA].[Maintenance].[usp_LogFileAlert];';
GO

-- 4) Job step: jediný řádek - zavolej proceduru (plně kvalifikovaně)
EXEC dbo.sp_add_jobstep
    @job_name       = N'Maintenance - LogFileMonitor',
    @step_name      = N'Check log files',
    @subsystem      = N'TSQL',
    @database_name  = N'DBA',
    @retry_attempts = 0,
    @command        = N'EXEC [DBA].[Maintenance].[usp_LogFileAlert];';
GO

-- 5) Schedule: denně, každých 15 minut, nonstop
EXEC dbo.sp_add_schedule
    @schedule_name        = N'Maintenance - LogFileMonitor',
    @freq_type            = 4,    -- 4 = daily
    @freq_interval        = 1,
    @freq_subday_type     = 4,    -- 4 = minutes
    @freq_subday_interval = 15,   -- každých 15 minut
    @active_start_time    = 0;    -- od 00:00:00
GO

-- 6) Připoj schedule k jobu
EXEC dbo.sp_attach_schedule
    @job_name      = N'Maintenance - LogFileMonitor',
    @schedule_name = N'Maintenance - LogFileMonitor';
GO

-- 7) Přiřaď job lokálnímu serveru (BEZ tohoto se job nikdy nespustí!)
EXEC dbo.sp_add_jobserver
    @job_name = N'Maintenance - LogFileMonitor';
GO

PRINT 'Job "Maintenance - LogFileMonitor" created and scheduled (every 15 minutes).';
GO