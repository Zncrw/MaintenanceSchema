USE msdb;
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Maintenance - Weekly Report')
    EXEC msdb.dbo.sp_delete_job @job_name = N'Maintenance - Weekly Report';

EXEC dbo.sp_add_job
    @job_name = N'Maintenance - Weekly Report';

EXEC dbo.sp_add_jobstep
    @job_name      = N'Maintenance - Weekly Report',
    @step_name     = N'Weekly report Maintenance',
    @subsystem     = N'TSQL',
    @database_name = N'DBA',
    @command       = N'EXEC [Maintenance].[usp_WeeklyMaintenanceReport];';

EXEC dbo.sp_add_jobschedule
    @job_name               = N'Maintenance - Weekly Report',
    @name                   = N'Maintenance_Weekly_Monday_0800',
    @freq_type              = 8,      -- týdně
    @freq_interval          = 2,      -- pondělí (bitmaska dní)
    @freq_recurrence_factor = 1,
    @freq_subday_type       = 1,      -- jednou, v daný čas (nezapomeň)
    @active_start_time      = 080000; -- 08:00:00

EXEC dbo.sp_add_jobserver
    @job_name = N'Maintenance - Weekly Report';
GO