/* ============================================================================
   Spotify - Data Warehouse                      (course work, FN 2401321010)
   02_load_dw.sql : ETL. Creates the procedure dbo.usp_LoadWarehouse, which
   empties SpotifyDW and reloads it from SpotifyDB, and then runs it.
   Run it again whenever the data in SpotifyDB changes.
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE SpotifyDW;
GO

CREATE OR ALTER PROCEDURE dbo.usp_LoadWarehouse
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LANGUAGE us_english;      -- English day and month names

    BEGIN TRY
        BEGIN TRANSACTION;

        /* ---- 1. empty the warehouse (facts first, then dimensions) ------- */
        DELETE FROM dbo.FactStreams;
        DELETE FROM dbo.FactPayments;
        DELETE FROM dbo.FactSubscriptions;
        DELETE FROM dbo.DimDate;          DELETE FROM dbo.DimTime;
        DELETE FROM dbo.DimUser;          DELETE FROM dbo.DimLocation;
        DELETE FROM dbo.DimTrack;         DELETE FROM dbo.DimArtist;
        DELETE FROM dbo.DimGenre;         DELETE FROM dbo.DimDevice;
        DELETE FROM dbo.DimPlan;          DELETE FROM dbo.DimPaymentMethod;

        -- surrogate keys start from 1 again (tables that never had rows already start from 1)
        DECLARE @t SYSNAME;
        DECLARE reseed CURSOR LOCAL FAST_FORWARD FOR
            SELECT OBJECT_NAME(object_id) FROM sys.identity_columns
            WHERE OBJECTPROPERTY(object_id, 'IsUserTable') = 1 AND last_value IS NOT NULL;
        OPEN reseed;
        FETCH NEXT FROM reseed INTO @t;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            DBCC CHECKIDENT (@t, RESEED, 0) WITH NO_INFOMSGS;
            FETCH NEXT FROM reseed INTO @t;
        END
        CLOSE reseed; DEALLOCATE reseed;

        /* ---- 2. the period covered by the data -------------------------- */
        DECLARE @AsOf DATE = (SELECT CAST(MAX(StartedAt) AS DATE) FROM SpotifyDB.dbo.Streams);
        DECLARE @From DATE = (SELECT DATEFROMPARTS(YEAR(MIN(StartDate)), 1, 1) FROM SpotifyDB.dbo.Subscriptions);
        DECLARE @To   DATE = (SELECT DATEFROMPARTS(YEAR(MAX(d)), 12, 31)
                              FROM (SELECT @AsOf AS d
                                    UNION ALL SELECT MAX(ISNULL(EndDate, StartDate)) FROM SpotifyDB.dbo.Subscriptions
                                    UNION ALL SELECT CAST(MAX(PaidAt) AS DATE) FROM SpotifyDB.dbo.Payments) x);

        /* ---- 3. dimensions ---------------------------------------------- */
        ;WITH n AS (SELECT TOP (DATEDIFF(DAY, @From, @To) + 1)
                           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
                    FROM sys.all_objects a CROSS JOIN sys.all_objects b),
              d AS (SELECT DATEADD(DAY, i, @From) AS dt FROM n)
        INSERT INTO dbo.DimDate (DateKey, FullDate, DayOfMonth, DayOfWeek, DayName, IsWeekend, WeekOfYear,
                                 MonthNumber, MonthName, YearMonth, Quarter, [Year])
        SELECT CAST(CONVERT(CHAR(8), dt, 112) AS INT), dt, DAY(dt),
               DATEDIFF(DAY, '19000101', dt) % 7 + 1,                       -- 1900-01-01 was a Monday
               DATENAME(WEEKDAY, dt),
               CASE WHEN DATEDIFF(DAY, '19000101', dt) % 7 >= 5 THEN 1 ELSE 0 END,
               DATEPART(ISO_WEEK, dt), MONTH(dt), DATENAME(MONTH, dt),
               CONVERT(CHAR(7), dt, 126), DATEPART(QUARTER, dt), YEAR(dt)
        FROM d;

        INSERT INTO dbo.DimTime (TimeKey, HourLabel, PartOfDay)
        SELECT h, RIGHT('0' + CAST(h AS VARCHAR(2)), 2) + ':00',
               CASE WHEN h < 6 THEN N'Night' WHEN h < 12 THEN N'Morning'
                    WHEN h < 18 THEN N'Afternoon' ELSE N'Evening' END
        FROM (SELECT TOP (24) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS h FROM sys.all_objects) x;

        INSERT INTO dbo.DimLocation (CountryID, CountryName, IsoCode, Region)
        SELECT CountryID, Name, IsoCode, Region FROM SpotifyDB.dbo.Countries ORDER BY CountryID;

        INSERT INTO dbo.DimPlan (PlanID, PlanName, PlanType, MonthlyPrice, MaxAccounts, HasAds)
        SELECT PlanID, Name, CASE WHEN MonthlyPrice > 0 THEN N'Premium' ELSE N'Free' END,
               MonthlyPrice, MaxAccounts, HasAds
        FROM SpotifyDB.dbo.SubscriptionPlans ORDER BY PlanID;

        INSERT INTO dbo.DimPaymentMethod (MethodName, MethodType)
        SELECT m.MethodName,
               CASE m.MethodName WHEN N'Card' THEN N'Bank card' WHEN N'PayPal' THEN N'E-wallet' ELSE N'Prepaid' END
        FROM (SELECT DISTINCT PaymentMethod AS MethodName FROM SpotifyDB.dbo.Payments) m
        ORDER BY m.MethodName;

        INSERT INTO dbo.DimDevice (DeviceID, DeviceType, Platform)
        SELECT DeviceID, DeviceType, Platform FROM SpotifyDB.dbo.Devices ORDER BY DeviceID;

        INSERT INTO dbo.DimGenre (GenreID, GenreName)
        SELECT GenreID, Name FROM SpotifyDB.dbo.Genres ORDER BY GenreID;

        INSERT INTO dbo.DimArtist (ArtistID, ArtistName, IsVerified, MonthlyListeners, FollowersCount)
        SELECT ArtistID, Name, IsVerified, MonthlyListeners, FollowersCount
        FROM SpotifyDB.dbo.Artists ORDER BY ArtistID;

        INSERT INTO dbo.DimTrack (TrackID, Title, AlbumTitle, AlbumType, Label, ReleaseDate, ReleaseYear,
                                  DurationSeconds, IsExplicit)
        SELECT t.TrackID, t.Title, al.Title, al.AlbumType, ISNULL(al.Label, N'Unknown'), al.ReleaseDate,
               YEAR(al.ReleaseDate), t.DurationSeconds, t.IsExplicit
        FROM SpotifyDB.dbo.Tracks t
        JOIN SpotifyDB.dbo.Albums al ON al.AlbumID = t.AlbumID
        ORDER BY t.TrackID;

        INSERT INTO dbo.DimUser (UserID, Username, DisplayName, Gender, AgeGroup, Role, SubscriptionType,
                                 IsStudentVerified, RegistrationDate)
        SELECT u.UserID, u.Username, u.DisplayName, ISNULL(u.Gender, N'Unknown'),
               CASE WHEN a.Age < 18 THEN N'13-17' WHEN a.Age < 25 THEN N'18-24' WHEN a.Age < 35 THEN N'25-34'
                    WHEN a.Age < 45 THEN N'35-44' ELSE N'45+' END,
               u.Role,
               CASE WHEN p.MonthlyPrice > 0 THEN N'Premium' ELSE N'Free' END,
               u.IsStudentVerified, u.RegistrationDate
        FROM SpotifyDB.dbo.Users u
        CROSS APPLY (SELECT SpotifyDB.dbo.fn_UserAge(u.DateOfBirth, @AsOf) AS Age) a
        JOIN SpotifyDB.dbo.Subscriptions s      ON s.UserID = u.UserID AND s.Status = N'Active'
        JOIN SpotifyDB.dbo.SubscriptionPlans p  ON p.PlanID = s.PlanID
        ORDER BY u.UserID;

        /* ---- 4. facts ---------------------------------------------------- */
        INSERT INTO dbo.FactStreams (StreamID, DateKey, TimeKey, UserKey, LocationKey, TrackKey, ArtistKey, GenreKey,
                                     DeviceKey, SecondsPlayed, MinutesPlayed, StreamCount, IsCounted, IsSkipped)
        SELECT s.StreamID,
               CAST(CONVERT(CHAR(8), s.StartedAt, 112) AS INT),
               DATEPART(HOUR, s.StartedAt),
               du.UserKey, dl.LocationKey, dt.TrackKey, da.ArtistKey, dg.GenreKey, dd.DeviceKey,
               s.SecondsPlayed, CAST(s.SecondsPlayed / 60.0 AS DECIMAL(6,2)), 1,
               CASE WHEN s.SecondsPlayed >= 30 THEN 1 ELSE 0 END, s.IsSkipped
        FROM SpotifyDB.dbo.Streams s
        JOIN SpotifyDB.dbo.TrackArtists ta ON ta.TrackID = s.TrackID AND ta.IsMainArtist = 1
        JOIN SpotifyDB.dbo.TrackGenres tg  ON tg.TrackID = s.TrackID AND tg.IsPrimary = 1
        JOIN dbo.DimUser du     ON du.UserID = s.UserID
        JOIN dbo.DimLocation dl ON dl.CountryID = s.CountryID
        JOIN dbo.DimTrack dt    ON dt.TrackID = s.TrackID
        JOIN dbo.DimArtist da   ON da.ArtistID = ta.ArtistID
        JOIN dbo.DimGenre dg    ON dg.GenreID = tg.GenreID
        JOIN dbo.DimDevice dd   ON dd.DeviceID = s.DeviceID
        ORDER BY s.StreamID;

        INSERT INTO dbo.FactPayments (PaymentID, SubscriptionID, DateKey, UserKey, LocationKey, PlanKey,
                                      PaymentMethodKey, Amount, RefundedAmount, Currency, PaymentCount,
                                      IsSuccessful, IsFailed, IsRefunded)
        SELECT pay.PaymentID, pay.SubscriptionID,
               CAST(CONVERT(CHAR(8), pay.PaidAt, 112) AS INT),
               du.UserKey, dl.LocationKey, dp.PlanKey, dm.PaymentMethodKey,
               pay.Amount,
               CASE WHEN pay.Status = N'Refunded' THEN pay.Amount ELSE 0 END,
               pay.Currency, 1,
               CASE WHEN pay.Status = N'Successful' THEN 1 ELSE 0 END,
               CASE WHEN pay.Status = N'Failed' THEN 1 ELSE 0 END,
               CASE WHEN pay.Status = N'Refunded' THEN 1 ELSE 0 END
        FROM SpotifyDB.dbo.Payments pay
        JOIN SpotifyDB.dbo.Subscriptions s ON s.SubscriptionID = pay.SubscriptionID
        JOIN SpotifyDB.dbo.Users u         ON u.UserID = s.UserID
        JOIN dbo.DimUser du          ON du.UserID = s.UserID
        JOIN dbo.DimLocation dl      ON dl.CountryID = u.CountryID
        JOIN dbo.DimPlan dp          ON dp.PlanID = s.PlanID
        JOIN dbo.DimPaymentMethod dm ON dm.MethodName = pay.PaymentMethod
        ORDER BY pay.PaymentID;

        ;WITH s AS (
            SELECT sub.*, p.MonthlyPrice,
                   LAG(p.MonthlyPrice) OVER (PARTITION BY sub.UserID
                                             ORDER BY sub.StartDate, sub.SubscriptionID) AS PreviousPrice
            FROM SpotifyDB.dbo.Subscriptions sub
            JOIN SpotifyDB.dbo.SubscriptionPlans p ON p.PlanID = sub.PlanID)
        INSERT INTO dbo.FactSubscriptions (SubscriptionID, StartDateKey, EndDateKey, UserKey, LocationKey, PlanKey,
                                           DurationDays, MonthlyPrice, SubscriptionCount, IsPremium, IsActive,
                                           IsCancelled, IsUpgradeFromFree, AutoRenew)
        SELECT s.SubscriptionID,
               CAST(CONVERT(CHAR(8), s.StartDate, 112) AS INT),
               CAST(CONVERT(CHAR(8), s.EndDate, 112) AS INT),
               du.UserKey, dl.LocationKey, dp.PlanKey,
               CASE WHEN ISNULL(s.EndDate, @AsOf) > s.StartDate
                    THEN DATEDIFF(DAY, s.StartDate, ISNULL(s.EndDate, @AsOf)) ELSE 0 END,
               s.MonthlyPrice, 1,
               CASE WHEN s.MonthlyPrice > 0 THEN 1 ELSE 0 END,
               CASE WHEN s.Status = N'Active' THEN 1 ELSE 0 END,
               CASE WHEN s.Status = N'Cancelled' THEN 1 ELSE 0 END,
               CASE WHEN s.MonthlyPrice > 0 AND s.PreviousPrice = 0 THEN 1 ELSE 0 END,
               s.AutoRenew
        FROM s
        JOIN SpotifyDB.dbo.Users u ON u.UserID = s.UserID
        JOIN dbo.DimUser du     ON du.UserID = s.UserID
        JOIN dbo.DimLocation dl ON dl.CountryID = u.CountryID
        JOIN dbo.DimPlan dp     ON dp.PlanID = s.PlanID
        ORDER BY s.SubscriptionID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT t.name AS TableName, SUM(p.rows) AS [Rows]
    FROM sys.tables t
    JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
    GROUP BY t.name
    ORDER BY CASE WHEN t.name LIKE 'Fact%' THEN 0 ELSE 1 END, t.name;
END;
GO

EXEC dbo.usp_LoadWarehouse;
GO
PRINT 'SpotifyDW loaded from SpotifyDB.';
GO
