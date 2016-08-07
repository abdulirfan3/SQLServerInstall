USE [msdb]
GO
DECLARE @jobId BINARY(16)
EXEC  msdb.dbo.sp_add_job @job_name=N'AutomaticIndexRebuild', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=2, 
		@notify_level_netsend=2, 
		@notify_level_page=2, 
		@delete_level=0, 
		@category_name=N'Database Maintenance', 
		@owner_login_name=N'US\ssadmin', @job_id = @jobId OUTPUT
select @jobId
GO
EXEC msdb.dbo.sp_add_jobserver @job_name=N'AutomaticIndexRebuild'
GO
USE [msdb]
GO
EXEC msdb.dbo.sp_add_jobstep @job_name=N'AutomaticIndexRebuild', @step_name=N'AutomaticIndexRebuild', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_fail_action=2, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'Exec dbo.dba_indexDefrag_sp
              @executeSQL           = 1
            , @printCommands        = 1
            , @debugMode            = 1
            , @printFragmentation   = 1
            , @forceRescan          = 1
            , @maxDopRestriction    = 1
            , @minPageCount         = 8
            , @maxPageCount         = Null
            , @minFragmentation     = 20
            , @rebuildThreshold     = 30
            , @defragDelay          = ''00:00:05''
            , @defragOrderColumn    = ''range_scan_count''
            , @defragSortOrder      = ''DESC''
            , @excludeMaxPartition  = 0
            , @timeLimit            = 60;
', 
		@database_name=N'DBA_Management', 
		@output_file_name=N'AutomaticIndexRebuild.txt', 
		@flags=0
GO
USE [msdb]
GO
EXEC msdb.dbo.sp_update_job @job_name=N'AutomaticIndexRebuild', 
		@enabled=1, 
		@start_step_id=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=2, 
		@notify_level_netsend=2, 
		@notify_level_page=2, 
		@delete_level=0, 
		@description=N'', 
		@category_name=N'Database Maintenance', 
		@owner_login_name=N'US\ssadmin', 
		@notify_email_operator_name=N'', 
		@notify_netsend_operator_name=N'', 
		@notify_page_operator_name=N''
GO
USE [msdb]
GO
DECLARE @schedule_id int
EXEC msdb.dbo.sp_add_jobschedule @job_name=N'AutomaticIndexRebuild', @name=N'WeeklyAutomaticIndexRebuild', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20150901, 
		@active_end_date=99991231, 
		@active_start_time=180000, 
		@active_end_time=235959, @schedule_id = @schedule_id OUTPUT
select @schedule_id
GO
