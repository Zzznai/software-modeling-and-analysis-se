/* ============================================================================
   Spotify - music streaming platform            (course work, FN 2401321010)
   02_programmability.sql : functions, views, triggers and stored procedures.

   Functions : fn_UserAge, fn_UserPlanAt, fn_UserSkipsInLastHour, fn_TopTracks
   Views     : vw_TrackCatalog, vw_UserCurrentPlan, vw_MonthlyRevenue
   Triggers  : trg_Users_AssignFreePlan, trg_Subscriptions_StudentPlan,
               trg_Streams_AfterInsert, trg_ArtistFollowers_Count
   Procedures: usp_RegisterUser, usp_ChangeSubscriptionPlan, usp_CancelSubscription,
               usp_ProcessRenewal, usp_AddTrackToPlaylist, usp_RecordStream,
               usp_RefreshArtistStats
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;      -- the tables have filtered indexes (sqlcmd has it OFF by default)
GO
USE SpotifyDB;
GO

/* ===========================================================================
   FUNCTIONS
   =========================================================================== */

-- Scalar: age in full years on a given date.
CREATE OR ALTER FUNCTION dbo.fn_UserAge (@DateOfBirth DATE, @AsOf DATE)
RETURNS INT
AS
BEGIN
    RETURN DATEDIFF(YEAR, @DateOfBirth, @AsOf)
         - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, @DateOfBirth, @AsOf), @DateOfBirth) > @AsOf THEN 1 ELSE 0 END;
END;
GO

-- Scalar: the plan a user was on at a given date (NULL if not registered yet).
CREATE OR ALTER FUNCTION dbo.fn_UserPlanAt (@UserID INT, @AsOf DATE)
RETURNS INT
AS
BEGIN
    DECLARE @PlanID INT;

    SELECT TOP (1) @PlanID = s.PlanID
    FROM dbo.Subscriptions AS s
    WHERE s.UserID = @UserID
      AND s.StartDate <= @AsOf
      AND (s.EndDate IS NULL OR s.EndDate > @AsOf)
    ORDER BY s.StartDate DESC, s.SubscriptionID DESC;

    RETURN @PlanID;
END;
GO

-- Scalar: how many tracks the user skipped in the hour before @AsOf.
CREATE OR ALTER FUNCTION dbo.fn_UserSkipsInLastHour (@UserID INT, @AsOf DATETIME2(0))
RETURNS INT
AS
BEGIN
    RETURN (SELECT COUNT(*)
            FROM dbo.Streams
            WHERE UserID = @UserID
              AND IsSkipped = 1
              AND StartedAt > DATEADD(HOUR, -1, @AsOf)
              AND StartedAt <= @AsOf);
END;
GO

-- Table-valued: the most played tracks in a period.
-- A play only counts when at least 30 seconds were listened to.
CREATE OR ALTER FUNCTION dbo.fn_TopTracks (@FromDate DATE, @ToDate DATE, @Top INT)
RETURNS TABLE
AS
RETURN
    SELECT TOP (@Top)
           t.TrackID,
           t.Title               AS TrackTitle,
           ar.Name               AS ArtistName,
           al.Title              AS AlbumTitle,
           COUNT(*)              AS StreamCount,
           SUM(s.SecondsPlayed) / 60 AS MinutesPlayed
    FROM dbo.Streams AS s
    JOIN dbo.Tracks AS t        ON t.TrackID = s.TrackID
    JOIN dbo.Albums AS al       ON al.AlbumID = t.AlbumID
    JOIN dbo.TrackArtists AS ta ON ta.TrackID = t.TrackID AND ta.IsMainArtist = 1
    JOIN dbo.Artists AS ar      ON ar.ArtistID = ta.ArtistID
    WHERE s.SecondsPlayed >= 30
      AND s.StartedAt >= @FromDate
      AND s.StartedAt < DATEADD(DAY, 1, @ToDate)
    GROUP BY t.TrackID, t.Title, ar.Name, al.Title
    ORDER BY COUNT(*) DESC, t.TrackID;
GO

/* ===========================================================================
   VIEWS
   =========================================================================== */

-- Every track with its album, main artist and primary genre.
CREATE OR ALTER VIEW dbo.vw_TrackCatalog
AS
SELECT t.TrackID, t.Title AS TrackTitle, ar.ArtistID, ar.Name AS ArtistName,
       al.AlbumID, al.Title AS AlbumTitle, al.AlbumType, al.ReleaseDate,
       g.Name AS PrimaryGenre, t.TrackNumber, t.DurationSeconds, t.IsExplicit, t.PlayCount
FROM dbo.Tracks AS t
JOIN dbo.Albums AS al            ON al.AlbumID = t.AlbumID
JOIN dbo.TrackArtists AS ta      ON ta.TrackID = t.TrackID AND ta.IsMainArtist = 1
JOIN dbo.Artists AS ar           ON ar.ArtistID = ta.ArtistID
LEFT JOIN dbo.TrackGenres AS tg  ON tg.TrackID = t.TrackID AND tg.IsPrimary = 1
LEFT JOIN dbo.Genres AS g        ON g.GenreID = tg.GenreID;
GO

-- Every user with the plan they are on right now.
CREATE OR ALTER VIEW dbo.vw_UserCurrentPlan
AS
SELECT u.UserID, u.Username, u.DisplayName, c.Name AS Country,
       p.Name AS PlanName, p.MonthlyPrice, s.StartDate, s.AutoRenew
FROM dbo.Users AS u
JOIN dbo.Countries AS c          ON c.CountryID = u.CountryID
JOIN dbo.Subscriptions AS s      ON s.UserID = u.UserID AND s.Status = N'Active'
JOIN dbo.SubscriptionPlans AS p  ON p.PlanID = s.PlanID;
GO

-- Revenue from successful payments per month and plan.
CREATE OR ALTER VIEW dbo.vw_MonthlyRevenue
AS
SELECT YEAR(pay.PaidAt) AS [Year], MONTH(pay.PaidAt) AS [Month], p.Name AS PlanName,
       COUNT(*) AS SuccessfulPayments, SUM(pay.Amount) AS Revenue
FROM dbo.Payments AS pay
JOIN dbo.Subscriptions AS s      ON s.SubscriptionID = pay.SubscriptionID
JOIN dbo.SubscriptionPlans AS p  ON p.PlanID = s.PlanID
WHERE pay.Status = N'Successful'
GROUP BY YEAR(pay.PaidAt), MONTH(pay.PaidAt), p.Name;
GO

/* ===========================================================================
   TRIGGERS
   =========================================================================== */

-- Rule: on registration every user automatically gets the Free plan.
CREATE OR ALTER TRIGGER dbo.trg_Users_AssignFreePlan
ON dbo.Users
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Subscriptions (UserID, PlanID, StartDate, Status, AutoRenew)
    SELECT i.UserID, p.PlanID, i.RegistrationDate, N'Active', 0
    FROM inserted AS i
    CROSS JOIN dbo.SubscriptionPlans AS p
    WHERE p.Name = N'Free';
END;
GO

-- Rule: Premium Student is only for users with a verified student status.
CREATE OR ALTER TRIGGER dbo.trg_Subscriptions_StudentPlan
ON dbo.Subscriptions
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1
               FROM inserted AS i
               JOIN dbo.SubscriptionPlans AS p ON p.PlanID = i.PlanID
               JOIN dbo.Users AS u             ON u.UserID = i.UserID
               WHERE p.Name = N'Premium Student' AND u.IsStudentVerified = 0)
    BEGIN
        ;THROW 50010, 'Premium Student requires a verified student status.', 1;
    END
END;
GO

-- Rules for every new stream:
--   * it cannot be longer than the track itself
--   * explicit tracks are not played for users under 18
--   * plays of 30+ seconds increase the derived counter Tracks.PlayCount
CREATE OR ALTER TRIGGER dbo.trg_Streams_AfterInsert
ON dbo.Streams
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1
               FROM inserted AS i
               JOIN dbo.Tracks AS t ON t.TrackID = i.TrackID
               WHERE i.SecondsPlayed > t.DurationSeconds)
    BEGIN
        ;THROW 50020, 'SecondsPlayed cannot be longer than the track.', 1;
    END

    IF EXISTS (SELECT 1
               FROM inserted AS i
               JOIN dbo.Tracks AS t ON t.TrackID = i.TrackID
               JOIN dbo.Users AS u  ON u.UserID = i.UserID
               WHERE t.IsExplicit = 1
                 AND dbo.fn_UserAge(u.DateOfBirth, CAST(i.StartedAt AS DATE)) < 18)
    BEGIN
        ;THROW 50021, 'Explicit tracks cannot be played by users under 18.', 1;
    END

    UPDATE t
    SET t.PlayCount = t.PlayCount + x.Plays
    FROM dbo.Tracks AS t
    JOIN (SELECT TrackID, COUNT(*) AS Plays
          FROM inserted
          WHERE SecondsPlayed >= 30
          GROUP BY TrackID) AS x ON x.TrackID = t.TrackID;
END;
GO

-- Keeps the derived counter Artists.FollowersCount in sync.
CREATE OR ALTER TRIGGER dbo.trg_ArtistFollowers_Count
ON dbo.ArtistFollowers
AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE a
    SET a.FollowersCount = a.FollowersCount + d.Delta
    FROM dbo.Artists AS a
    JOIN (SELECT ArtistID, SUM(Delta) AS Delta
          FROM (SELECT ArtistID, 1 AS Delta FROM inserted
                UNION ALL
                SELECT ArtistID, -1 FROM deleted) AS x
          GROUP BY ArtistID) AS d ON d.ArtistID = a.ArtistID;
END;
GO

/* ===========================================================================
   STORED PROCEDURES
   =========================================================================== */

-- Registers a new user. The Free plan is added by trg_Users_AssignFreePlan.
CREATE OR ALTER PROCEDURE dbo.usp_RegisterUser
    @Username     NVARCHAR(50),
    @Email        NVARCHAR(150),
    @PasswordHash NVARCHAR(255),
    @DisplayName  NVARCHAR(100),
    @DateOfBirth  DATE,
    @CountryIso   CHAR(2),
    @Gender       NVARCHAR(10) = NULL,
    @UserID       INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CountryID INT = (SELECT CountryID FROM dbo.Countries WHERE IsoCode = @CountryIso);

    IF @CountryID IS NULL
        THROW 50001, 'Unknown country code.', 1;
    IF dbo.fn_UserAge(@DateOfBirth, CAST(GETDATE() AS DATE)) < 13
        THROW 50002, 'The user must be at least 13 years old.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Users WHERE Email = @Email OR Username = @Username)
        THROW 50003, 'The e-mail or the username is already taken.', 1;

    INSERT INTO dbo.Users (Username, Email, PasswordHash, DisplayName, DateOfBirth, Gender, CountryID)
    VALUES (@Username, @Email, @PasswordHash, @DisplayName, @DateOfBirth, @Gender, @CountryID);

    SET @UserID = SCOPE_IDENTITY();
END;
GO

-- Moves a user to another plan. The old subscription is closed, a new one is
-- opened and, for a paid plan, the first payment (= the plan price) is recorded.
CREATE OR ALTER PROCEDURE dbo.usp_ChangeSubscriptionPlan
    @UserID        INT,
    @PlanName      NVARCHAR(50),
    @PaymentMethod NVARCHAR(20) = NULL,
    @AsOf          DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Today DATE = CAST(GETDATE() AS DATE);
    SET @AsOf = ISNULL(@AsOf, @Today);

    DECLARE @NewPlanID INT, @Price DECIMAL(6,2),
            @CurSubID INT, @CurPlanID INT, @CurStart DATE, @NewSubID INT;

    SELECT @NewPlanID = PlanID, @Price = MonthlyPrice
    FROM dbo.SubscriptionPlans WHERE Name = @PlanName;

    SELECT @CurSubID = SubscriptionID, @CurPlanID = PlanID, @CurStart = StartDate
    FROM dbo.Subscriptions WHERE UserID = @UserID AND Status = N'Active';

    IF @NewPlanID IS NULL
        THROW 50030, 'Unknown subscription plan.', 1;
    IF @CurSubID IS NULL
        THROW 50031, 'The user has no active subscription.', 1;
    IF @CurPlanID = @NewPlanID
        THROW 50032, 'The user is already on this plan.', 1;
    IF @Price > 0 AND @PaymentMethod IS NULL
        THROW 50033, 'A paid plan needs a payment method.', 1;
    IF @AsOf < @CurStart
        THROW 50034, 'The change cannot be dated before the current subscription.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @AsOf = @CurStart
        BEGIN
            -- changed on the day it started: replace the plan instead of keeping a 0-day period
            UPDATE dbo.Subscriptions
            SET PlanID = @NewPlanID, AutoRenew = CASE WHEN @Price > 0 THEN 1 ELSE 0 END
            WHERE SubscriptionID = @CurSubID;

            SET @NewSubID = @CurSubID;
        END
        ELSE
        BEGIN
            UPDATE dbo.Subscriptions
            SET EndDate = @AsOf,
                Status  = CASE WHEN @Price = 0 THEN N'Cancelled' ELSE N'Expired' END
            WHERE SubscriptionID = @CurSubID;

            INSERT INTO dbo.Subscriptions (UserID, PlanID, StartDate, Status, AutoRenew)
            VALUES (@UserID, @NewPlanID, @AsOf, N'Active', CASE WHEN @Price > 0 THEN 1 ELSE 0 END);

            SET @NewSubID = SCOPE_IDENTITY();
        END

        IF @Price > 0
            INSERT INTO dbo.Payments (SubscriptionID, Amount, PaymentMethod, Status, PaidAt)
            VALUES (@NewSubID, @Price, @PaymentMethod, N'Successful',
                    CASE WHEN @AsOf = @Today THEN SYSDATETIME() ELSE CAST(@AsOf AS DATETIME2(0)) END);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- Rule: after a cancellation Premium stays active until the paid period ends.
-- The procedure only switches auto-renewal off; usp_ProcessRenewal ends it later.
CREATE OR ALTER PROCEDURE dbo.usp_CancelSubscription
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE s
    SET s.AutoRenew = 0
    FROM dbo.Subscriptions AS s
    JOIN dbo.SubscriptionPlans AS p ON p.PlanID = s.PlanID
    WHERE s.UserID = @UserID AND s.Status = N'Active' AND p.MonthlyPrice > 0;

    IF @@ROWCOUNT = 0
        THROW 50040, 'The user has no paid subscription to cancel.', 1;
END;
GO

-- Monthly renewal of one paid subscription.
--   * cancelled by the user (AutoRenew = 0) -> it ends, the user goes back to Free
--   * payment succeeded                     -> a successful payment is recorded
--   * payment failed                        -> failed payment, subscription expires, back to Free
CREATE OR ALTER PROCEDURE dbo.usp_ProcessRenewal
    @SubscriptionID   INT,
    @PaymentSucceeded BIT = 1,
    @PaymentMethod    NVARCHAR(20) = N'Card',
    @AsOf             DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Today DATE = CAST(GETDATE() AS DATE);
    SET @AsOf = ISNULL(@AsOf, @Today);

    DECLARE @UserID INT, @Price DECIMAL(6,2), @AutoRenew BIT, @FreePlanID INT,
            @PaidAt DATETIME2(0) = CASE WHEN @AsOf = @Today THEN SYSDATETIME() ELSE CAST(@AsOf AS DATETIME2(0)) END;

    SELECT @UserID = s.UserID, @Price = p.MonthlyPrice, @AutoRenew = s.AutoRenew
    FROM dbo.Subscriptions AS s
    JOIN dbo.SubscriptionPlans AS p ON p.PlanID = s.PlanID
    WHERE s.SubscriptionID = @SubscriptionID AND s.Status = N'Active' AND p.MonthlyPrice > 0;

    IF @UserID IS NULL
        THROW 50041, 'There is no active paid subscription with this ID.', 1;

    SELECT @FreePlanID = PlanID FROM dbo.SubscriptionPlans WHERE Name = N'Free';

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @AutoRenew = 1 AND @PaymentSucceeded = 1
        BEGIN
            INSERT INTO dbo.Payments (SubscriptionID, Amount, PaymentMethod, Status, PaidAt)
            VALUES (@SubscriptionID, @Price, @PaymentMethod, N'Successful', @PaidAt);
        END
        ELSE
        BEGIN
            IF @AutoRenew = 1
                INSERT INTO dbo.Payments (SubscriptionID, Amount, PaymentMethod, Status, PaidAt)
                VALUES (@SubscriptionID, @Price, @PaymentMethod, N'Failed', @PaidAt);

            UPDATE dbo.Subscriptions
            SET EndDate = @AsOf,
                Status  = CASE WHEN @AutoRenew = 0 THEN N'Cancelled' ELSE N'Expired' END
            WHERE SubscriptionID = @SubscriptionID;

            INSERT INTO dbo.Subscriptions (UserID, PlanID, StartDate, Status, AutoRenew)
            VALUES (@UserID, @FreePlanID, @AsOf, N'Active', 0);
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- Adds a track at the end of a playlist. Only the owner may edit a playlist,
-- a track can be in it once and a playlist holds at most 10 000 tracks.
CREATE OR ALTER PROCEDURE dbo.usp_AddTrackToPlaylist
    @PlaylistID INT,
    @TrackID    INT,
    @UserID     INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OwnerID INT = (SELECT UserID FROM dbo.Playlists WHERE PlaylistID = @PlaylistID);
    DECLARE @Tracks INT, @NextPosition INT;

    IF @OwnerID IS NULL
        THROW 50050, 'The playlist does not exist.', 1;
    IF @OwnerID <> @UserID
        THROW 50051, 'Only the owner can edit a playlist.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Tracks WHERE TrackID = @TrackID)
        THROW 50052, 'The track does not exist.', 1;
    IF EXISTS (SELECT 1 FROM dbo.PlaylistTracks WHERE PlaylistID = @PlaylistID AND TrackID = @TrackID)
        THROW 50053, 'The track is already in the playlist.', 1;

    SELECT @Tracks = COUNT(*), @NextPosition = ISNULL(MAX(Position), 0) + 1
    FROM dbo.PlaylistTracks WHERE PlaylistID = @PlaylistID;

    IF @Tracks >= 10000
        THROW 50054, 'A playlist can hold at most 10 000 tracks.', 1;

    INSERT INTO dbo.PlaylistTracks (PlaylistID, TrackID, Position)
    VALUES (@PlaylistID, @TrackID, @NextPosition);

    UPDATE dbo.Playlists SET UpdatedAt = SYSDATETIME() WHERE PlaylistID = @PlaylistID;
END;
GO

-- Records one play. Users on a plan with a skip limit (Free: 6 per hour)
-- cannot skip more tracks than the plan allows.
CREATE OR ALTER PROCEDURE dbo.usp_RecordStream
    @UserID        INT,
    @TrackID       INT,
    @DeviceID      INT,
    @SecondsPlayed SMALLINT,
    @IsSkipped     BIT = 0,
    @CountryID     INT = NULL,
    @StartedAt     DATETIME2(0) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @StartedAt = ISNULL(@StartedAt, SYSDATETIME());

    DECLARE @HomeCountryID INT = (SELECT CountryID FROM dbo.Users WHERE UserID = @UserID);
    IF @HomeCountryID IS NULL
        THROW 50060, 'The user does not exist.', 1;
    SET @CountryID = ISNULL(@CountryID, @HomeCountryID);

    DECLARE @SkipLimit TINYINT =
        (SELECT SkipsPerHour FROM dbo.SubscriptionPlans
         WHERE PlanID = dbo.fn_UserPlanAt(@UserID, CAST(@StartedAt AS DATE)));

    IF @IsSkipped = 1 AND @SkipLimit IS NOT NULL
       AND dbo.fn_UserSkipsInLastHour(@UserID, @StartedAt) >= @SkipLimit
        THROW 50061, 'Skip limit reached for this hour. Upgrade to Premium for unlimited skips.', 1;

    INSERT INTO dbo.Streams (UserID, TrackID, CountryID, DeviceID, StartedAt, SecondsPlayed, IsSkipped)
    VALUES (@UserID, @TrackID, @CountryID, @DeviceID, @StartedAt, @SecondsPlayed, @IsSkipped);
END;
GO

-- Recalculates the derived artist statistics:
--   MonthlyListeners = different users with a counted play in the last 30 days
--   FollowersCount   = rows in ArtistFollowers
CREATE OR ALTER PROCEDURE dbo.usp_RefreshArtistStats
    @AsOf DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @AsOf = ISNULL(@AsOf, CAST(GETDATE() AS DATE));

    UPDATE a
    SET a.MonthlyListeners = ISNULL(l.Listeners, 0),
        a.FollowersCount   = ISNULL(f.Followers, 0)
    FROM dbo.Artists AS a
    LEFT JOIN (SELECT ta.ArtistID, COUNT(DISTINCT s.UserID) AS Listeners
               FROM dbo.Streams AS s
               JOIN dbo.TrackArtists AS ta ON ta.TrackID = s.TrackID
               WHERE s.SecondsPlayed >= 30
                 AND s.StartedAt >= DATEADD(DAY, -29, @AsOf)
                 AND s.StartedAt < DATEADD(DAY, 1, @AsOf)
               GROUP BY ta.ArtistID) AS l ON l.ArtistID = a.ArtistID
    LEFT JOIN (SELECT ArtistID, COUNT(*) AS Followers
               FROM dbo.ArtistFollowers
               GROUP BY ArtistID) AS f ON f.ArtistID = a.ArtistID;
END;
GO

PRINT 'SpotifyDB programmability created: 4 functions, 3 views, 4 triggers, 7 procedures.';
GO
