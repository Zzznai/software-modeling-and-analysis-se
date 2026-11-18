/* ============================================================================
   Spotify - music streaming platform            (course work, FN 2401321010)
   04_demo_queries.sql : shows the functions, views, triggers and procedures
   at work. Everything the script creates is removed again at the end, so it
   can be run as many times as you like.
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO
USE SpotifyDB;
GO

-- helper: removes the demo users and everything that belongs to them
CREATE OR ALTER PROCEDURE #RemoveDemoData
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Demo TABLE (UserID INT PRIMARY KEY);
    DECLARE @Touched TABLE (TrackID INT PRIMARY KEY);

    INSERT INTO @Demo SELECT UserID FROM dbo.Users WHERE Username IN (N'demo.student', N'demo.teen');
    INSERT INTO @Touched SELECT DISTINCT TrackID FROM dbo.Streams WHERE UserID IN (SELECT UserID FROM @Demo);

    DELETE FROM dbo.Streams         WHERE UserID IN (SELECT UserID FROM @Demo);
    DELETE FROM dbo.ArtistFollowers WHERE UserID IN (SELECT UserID FROM @Demo);
    DELETE FROM dbo.Payments        WHERE SubscriptionID IN
           (SELECT SubscriptionID FROM dbo.Subscriptions WHERE UserID IN (SELECT UserID FROM @Demo));
    DELETE FROM dbo.Subscriptions   WHERE UserID IN (SELECT UserID FROM @Demo);
    DELETE FROM dbo.Users           WHERE UserID IN (SELECT UserID FROM @Demo);   -- playlists go by cascade

    UPDATE t SET t.PlayCount = (SELECT COUNT(*) FROM dbo.Streams s WHERE s.TrackID = t.TrackID AND s.SecondsPlayed >= 30)
    FROM dbo.Tracks t WHERE t.TrackID IN (SELECT TrackID FROM @Touched);
END;
GO
EXEC #RemoveDemoData;
GO

PRINT '=== 1. FUNCTIONS AND VIEWS =========================================';
SELECT dbo.fn_UserAge('2005-03-14', '2026-11-16') AS AgeInYears;

SELECT * FROM dbo.fn_TopTracks('2026-01-01', '2026-10-31', 5);

SELECT TOP (5) TrackTitle, ArtistName, AlbumTitle, PrimaryGenre, PlayCount
FROM dbo.vw_TrackCatalog ORDER BY PlayCount DESC;

SELECT TOP (5) [Year], [Month], PlanName, SuccessfulPayments, Revenue
FROM dbo.vw_MonthlyRevenue ORDER BY [Year] DESC, [Month] DESC, Revenue DESC;
GO

PRINT '=== 2. REGISTRATION: trigger gives the Free plan ====================';
DECLARE @UserID INT;
EXEC dbo.usp_RegisterUser @Username = N'demo.student', @Email = N'demo.student@example.com',
     @PasswordHash = N'0000', @DisplayName = N'Demo Student', @DateOfBirth = '2004-05-20',
     @CountryIso = 'BG', @Gender = N'Male', @UserID = @UserID OUTPUT;

SELECT UserID, Username, Country, PlanName, StartDate FROM dbo.vw_UserCurrentPlan WHERE UserID = @UserID;

BEGIN TRY
    EXEC dbo.usp_RegisterUser @Username = N'demo.kid', @Email = N'demo.kid@example.com', @PasswordHash = N'0000',
         @DisplayName = N'Demo Kid', @DateOfBirth = '2020-01-01', @CountryIso = 'BG';
END TRY
BEGIN CATCH
    PRINT 'Expected error (too young): ' + ERROR_MESSAGE();
END CATCH
GO

PRINT '=== 3. SUBSCRIPTIONS AND PAYMENTS ===================================';
DECLARE @UserID INT = (SELECT UserID FROM dbo.Users WHERE Username = N'demo.student');
DECLARE @SubID INT, @NextMonth DATE = DATEADD(MONTH, 1, CAST(GETDATE() AS DATE)),
        @InTwoMonths DATE = DATEADD(MONTH, 2, CAST(GETDATE() AS DATE));

BEGIN TRY
    EXEC dbo.usp_ChangeSubscriptionPlan @UserID = @UserID, @PlanName = N'Premium Student', @PaymentMethod = N'Card';
END TRY
BEGIN CATCH
    PRINT 'Expected error (not a verified student): ' + ERROR_MESSAGE();
END CATCH

EXEC dbo.usp_ChangeSubscriptionPlan @UserID = @UserID, @PlanName = N'Premium Individual', @PaymentMethod = N'Card';
SELECT @SubID = SubscriptionID FROM dbo.Subscriptions WHERE UserID = @UserID AND Status = N'Active';

EXEC dbo.usp_ProcessRenewal @SubscriptionID = @SubID, @PaymentSucceeded = 1, @AsOf = @NextMonth;  -- renewed
EXEC dbo.usp_CancelSubscription @UserID = @UserID;                                              -- stays active
EXEC dbo.usp_ProcessRenewal @SubscriptionID = @SubID, @AsOf = @InTwoMonths;                      -- ends, back to Free

SELECT s.SubscriptionID, p.Name AS PlanName, s.StartDate, s.EndDate, s.Status, s.AutoRenew
FROM dbo.Subscriptions s JOIN dbo.SubscriptionPlans p ON p.PlanID = s.PlanID
WHERE s.UserID = @UserID ORDER BY s.SubscriptionID;

SELECT pay.PaymentID, pay.Amount, pay.PaymentMethod, pay.Status, pay.PaidAt
FROM dbo.Payments pay JOIN dbo.Subscriptions s ON s.SubscriptionID = pay.SubscriptionID
WHERE s.UserID = @UserID ORDER BY pay.PaymentID;
GO

PRINT '=== 4. PLAYLISTS ====================================================';
DECLARE @UserID INT = (SELECT UserID FROM dbo.Users WHERE Username = N'demo.student');
DECLARE @PlaylistID INT, @Supernova INT = (SELECT TrackID FROM dbo.Tracks WHERE Title = N'Supernova'),
        @Katinara INT = (SELECT TrackID FROM dbo.Tracks WHERE Title = N'Katinara');

INSERT INTO dbo.Playlists (UserID, Name) VALUES (@UserID, N'Demo playlist');
SET @PlaylistID = SCOPE_IDENTITY();

EXEC dbo.usp_AddTrackToPlaylist @PlaylistID = @PlaylistID, @TrackID = @Supernova, @UserID = @UserID;
EXEC dbo.usp_AddTrackToPlaylist @PlaylistID = @PlaylistID, @TrackID = @Katinara, @UserID = @UserID;

BEGIN TRY
    EXEC dbo.usp_AddTrackToPlaylist @PlaylistID = @PlaylistID, @TrackID = @Katinara, @UserID = @UserID;
END TRY
BEGIN CATCH
    PRINT 'Expected error (duplicate): ' + ERROR_MESSAGE();
END CATCH
BEGIN TRY
    EXEC dbo.usp_AddTrackToPlaylist @PlaylistID = @PlaylistID, @TrackID = @Supernova, @UserID = 1;
END TRY
BEGIN CATCH
    PRINT 'Expected error (not the owner): ' + ERROR_MESSAGE();
END CATCH

SELECT pt.Position, t.Title FROM dbo.PlaylistTracks pt JOIN dbo.Tracks t ON t.TrackID = pt.TrackID
WHERE pt.PlaylistID = @PlaylistID ORDER BY pt.Position;
GO

PRINT '=== 5. STREAMS: trigger keeps PlayCount and checks the rules ========';
DECLARE @UserID INT = (SELECT UserID FROM dbo.Users WHERE Username = N'demo.student');
DECLARE @Track INT = (SELECT TrackID FROM dbo.Tracks WHERE Title = N'Supernova');
DECLARE @Before BIGINT = (SELECT PlayCount FROM dbo.Tracks WHERE TrackID = @Track), @i INT = 1;

EXEC dbo.usp_RecordStream @UserID = @UserID, @TrackID = @Track, @DeviceID = 1, @SecondsPlayed = 179;   -- counts
EXEC dbo.usp_RecordStream @UserID = @UserID, @TrackID = @Track, @DeviceID = 1, @SecondsPlayed = 12;    -- too short
SELECT @Before AS PlayCountBefore, PlayCount AS PlayCountAfter FROM dbo.Tracks WHERE TrackID = @Track;

BEGIN TRY
    EXEC dbo.usp_RecordStream @UserID = @UserID, @TrackID = @Track, @DeviceID = 1, @SecondsPlayed = 5000;
END TRY
BEGIN CATCH
    PRINT 'Expected error (longer than the track): ' + ERROR_MESSAGE();
END CATCH

-- the demo user is on Premium today, so move the skips two months ahead, when the plan is Free again
DECLARE @When DATETIME2(0) = DATEADD(DAY, 70, SYSDATETIME());
BEGIN TRY
    WHILE @i <= 7
    BEGIN
        EXEC dbo.usp_RecordStream @UserID = @UserID, @TrackID = @Track, @DeviceID = 1, @SecondsPlayed = 5,
             @IsSkipped = 1, @StartedAt = @When;
        SET @i += 1;
    END
END TRY
BEGIN CATCH
    PRINT 'Expected error (skip number ' + CAST(@i AS VARCHAR(2)) + ' on Free): ' + ERROR_MESSAGE();
END CATCH
GO

DECLARE @TeenID INT, @Explicit INT = (SELECT TOP (1) TrackID FROM dbo.Tracks WHERE Title = N'HUMBLE.');
DECLARE @Dob DATE = DATEADD(YEAR, -15, CAST(GETDATE() AS DATE));
EXEC dbo.usp_RegisterUser @Username = N'demo.teen', @Email = N'demo.teen@example.com', @PasswordHash = N'0000',
     @DisplayName = N'Demo Teen', @DateOfBirth = @Dob, @CountryIso = 'BG', @UserID = @TeenID OUTPUT;
BEGIN TRY
    EXEC dbo.usp_RecordStream @UserID = @TeenID, @TrackID = @Explicit, @DeviceID = 1, @SecondsPlayed = 60;
END TRY
BEGIN CATCH
    PRINT 'Expected error (explicit track, user is 15): ' + ERROR_MESSAGE();
END CATCH
GO

PRINT '=== 6. FOLLOWERS: trigger keeps Artists.FollowersCount ==============';
DECLARE @UserID INT = (SELECT UserID FROM dbo.Users WHERE Username = N'demo.student');
DECLARE @Artist INT = (SELECT ArtistID FROM dbo.Artists WHERE Name = N'aespa');
DECLARE @Before INT = (SELECT FollowersCount FROM dbo.Artists WHERE ArtistID = @Artist), @AfterFollow INT;

INSERT INTO dbo.ArtistFollowers (UserID, ArtistID) VALUES (@UserID, @Artist);
SELECT @AfterFollow = FollowersCount FROM dbo.Artists WHERE ArtistID = @Artist;
DELETE FROM dbo.ArtistFollowers WHERE UserID = @UserID AND ArtistID = @Artist;

SELECT @Before AS FollowersBefore, @AfterFollow AS AfterFollow, FollowersCount AS AfterUnfollow
FROM dbo.Artists WHERE ArtistID = @Artist;
GO

EXEC #RemoveDemoData;
DROP PROCEDURE #RemoveDemoData;
PRINT '=== Demo finished, demo data removed ================================';
GO
