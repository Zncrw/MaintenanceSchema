USE msdb;
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Maintenance - Retention')
    EXEC msdb.dbo.sp_delete_job @job_name = N'Maintenance - Retention';
-- cleanup old retention job
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'PiHole - Retention 30 days')
    EXEC msdb.dbo.sp_delete_job @job_name = N'PiHole - Retention 30 days';

EXEC dbo.sp_add_job @job_name = N'Maintenance - Retention';

EXEC dbo.sp_add_jobstep
    @job_name = N'Maintenance - Retention',
    @step_name = N'Run retention cleanup',
    @subsystem = N'TSQL',
    @database_name = N'DBA', -- Replace with your actual database name
    @command = N'EXEC [Maintenance].[usp_RunRetention];';

EXEC dbo.sp_add_jobschedule
    @job_name = N'Maintenance - Retention',
    @name = N'Daily Midnight',
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 1,        -- jednou, v daný čas (nech tam)
    @active_start_time = 000000;

EXEC dbo.sp_add_jobserver
    @job_name = N'Maintenance - Retention';
GO