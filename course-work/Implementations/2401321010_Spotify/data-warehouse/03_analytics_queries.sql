/* ============================================================================
   Spotify - Data Warehouse                      (course work, FN 2401321010)
   03_analytics_queries.sql : the reports from the business requirements,
   written against the warehouse. The Power BI report shows the same numbers.
   ============================================================================ */
USE SpotifyDW;
GO

-- 1. Plays and listening time per month
SELECT d.YearMonth,
       SUM(CAST(f.IsCounted AS INT))        AS CountedStreams,
       CAST(SUM(f.MinutesPlayed) AS INT)    AS MinutesPlayed,
       COUNT(DISTINCT f.UserKey)            AS ActiveUsers,
       CAST(100.0 * SUM(CAST(f.IsSkipped AS INT)) / COUNT(*) AS DECIMAL(5,1)) AS SkipRatePct
FROM dbo.FactStreams f
JOIN dbo.DimDate d ON d.DateKey = f.DateKey
GROUP BY d.YearMonth
ORDER BY d.YearMonth;

-- 2. Top 10 artists by counted plays
SELECT TOP (10) a.ArtistName, SUM(CAST(f.IsCounted AS INT)) AS CountedStreams, COUNT(DISTINCT f.UserKey) AS Listeners
FROM dbo.FactStreams f
JOIN dbo.DimArtist a ON a.ArtistKey = f.ArtistKey
GROUP BY a.ArtistName
ORDER BY CountedStreams DESC;

-- 3. The most played genre in every country
WITH g AS (
    SELECT l.CountryName, ge.GenreName, SUM(CAST(f.IsCounted AS INT)) AS CountedStreams,
           ROW_NUMBER() OVER (PARTITION BY l.CountryName ORDER BY SUM(CAST(f.IsCounted AS INT)) DESC) AS rn
    FROM dbo.FactStreams f
    JOIN dbo.DimLocation l ON l.LocationKey = f.LocationKey
    JOIN dbo.DimGenre ge   ON ge.GenreKey = f.GenreKey
    GROUP BY l.CountryName, ge.GenreName)
SELECT CountryName, GenreName AS TopGenre, CountedStreams
FROM g WHERE rn = 1
ORDER BY CountedStreams DESC;

-- 4. Revenue per plan and month (successful payments only)
SELECT d.YearMonth, p.PlanName, SUM(f.Amount) AS Revenue, COUNT(*) AS Payments
FROM dbo.FactPayments f
JOIN dbo.DimDate d ON d.DateKey = f.DateKey
JOIN dbo.DimPlan p ON p.PlanKey = f.PlanKey
WHERE f.IsSuccessful = 1
GROUP BY d.YearMonth, p.PlanName
ORDER BY d.YearMonth, p.PlanName;

-- 5. Revenue and paying users per country
SELECT l.CountryName, l.Region, SUM(f.Amount) AS Revenue, COUNT(DISTINCT f.UserKey) AS PayingUsers
FROM dbo.FactPayments f
JOIN dbo.DimLocation l ON l.LocationKey = f.LocationKey
WHERE f.IsSuccessful = 1
GROUP BY l.CountryName, l.Region
ORDER BY Revenue DESC;

-- 6. Plays per device type and part of the day
SELECT dv.DeviceType, t.PartOfDay, COUNT(*) AS Streams
FROM dbo.FactStreams f
JOIN dbo.DimDevice dv ON dv.DeviceKey = f.DeviceKey
JOIN dbo.DimTime t    ON t.TimeKey = f.TimeKey
GROUP BY dv.DeviceType, t.PartOfDay
ORDER BY dv.DeviceType, MIN(t.TimeKey);

-- 7. Upgrades from Free and cancellations (churn) per plan and month
SELECT d.YearMonth, p.PlanName,
       SUM(CAST(f.IsUpgradeFromFree AS INT)) AS UpgradesFromFree
FROM dbo.FactSubscriptions f
JOIN dbo.DimDate d ON d.DateKey = f.StartDateKey
JOIN dbo.DimPlan p ON p.PlanKey = f.PlanKey
WHERE f.IsPremium = 1
GROUP BY d.YearMonth, p.PlanName
ORDER BY d.YearMonth, p.PlanName;

SELECT d.YearMonth, p.PlanName, COUNT(*) AS Cancelled
FROM dbo.FactSubscriptions f
JOIN dbo.DimDate d ON d.DateKey = f.EndDateKey          -- DimDate in its second role: end date
JOIN dbo.DimPlan p ON p.PlanKey = f.PlanKey
WHERE f.IsCancelled = 1
GROUP BY d.YearMonth, p.PlanName
ORDER BY d.YearMonth, p.PlanName;
GO
