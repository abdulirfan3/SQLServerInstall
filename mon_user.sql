USE [master]
GO
CREATE LOGIN [Monitoruser] WITH PASSWORD=N'XXXXXXXX', DEFAULT_DATABASE=[master], DEFAULT_LANGUAGE=[us_english], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF
GO

 
USE [msdb]
GO
CREATE USER [Monitoruser] FOR LOGIN [Monitoruser]
GO

USE [msdb]
GO
EXEC sp_addrolemember N'db_datareader', N'Monitoruser'
GO