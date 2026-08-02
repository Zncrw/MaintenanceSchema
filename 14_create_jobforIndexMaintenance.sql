USE msdb;
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Maintenance - IndexMaintenance')
    EXEC msdb.dbo.sp_delete_job @job_name = N'Maintenance - IndexMaintenance';


EXEC dbo.sp_add_job @job_name = N'Maintenance - IndexMaintenance';

EXEC dbo.sp_add_jobstep
    @job_name = N'Maintenance - IndexMaintenance',
    @step_name = N'Run index maintenance',
    @subsystem = N'TSQL',
    @database_name = N'DBA',
    @command = N'EXEC [Maintenance].[usp_IndexMaintenance];';

EXEC dbo.sp_add_jobschedule
    @job_name               = N'Maintenance - IndexMaintenance',
    @name                   = N'Index_Weekly_Sunday_0200',
    @freq_type              = 8,      -- týdně
    @freq_interval          = 1,      -- neděle (bitmaska: ne=1, po=2, út=4, st=8, čt=16, pá=32, so=64)
    @freq_recurrence_factor = 1,
    @freq_subday_type       = 1,
    @active_start_time      = 020000; -- 02:00

EXEC dbo.sp_add_jobserver
    @job_name = N'Maintenance - IndexMaintenance';
GO