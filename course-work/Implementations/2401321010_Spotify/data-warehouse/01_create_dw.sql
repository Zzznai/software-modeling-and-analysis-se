/* ============================================================================
   Spotify - Data Warehouse                      (course work, FN 2401321010)
   01_create_dw.sql : creates the SpotifyDW database (fact constellation):
       3 fact tables  : FactStreams, FactPayments, FactSubscriptions
       10 dimensions  : DimDate, DimTime, DimUser, DimLocation, DimTrack, DimArtist,
                        DimGenre, DimDevice, DimPlan, DimPaymentMethod

   Run order:  01_create_dw.sql -> 02_load_dw.sql   (SpotifyDB must exist and be filled)
   The script is re-runnable: it drops and recreates the database.
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE master;
GO
IF DB_ID(N'SpotifyDW') IS NOT NULL
BEGIN
    ALTER DATABASE SpotifyDW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SpotifyDW;
END
GO
CREATE DATABASE SpotifyDW;
GO
USE SpotifyDW;
GO

/* ---------------------------------------------------------------------------
   Dimensions
   --------------------------------------------------------------------------- */
CREATE TABLE dbo.DimDate (
    DateKey     INT          NOT NULL,      -- yyyymmdd
    FullDate    DATE         NOT NULL,
    DayOfMonth  TINYINT      NOT NULL,
    DayOfWeek   TINYINT      NOT NULL,      -- 1 = Monday ... 7 = Sunday
    DayName     NVARCHAR(10) NOT NULL,
    IsWeekend   BIT          NOT NULL,
    WeekOfYear  TINYINT      NOT NULL,
    MonthNumber TINYINT      NOT NULL,
    MonthName   NVARCHAR(10) NOT NULL,
    YearMonth   CHAR(7)      NOT NULL,      -- yyyy-mm
    Quarter     TINYINT      NOT NULL,
    [Year]      SMALLINT     NOT NULL,
    CONSTRAINT PK_DimDate PRIMARY KEY (DateKey)
);

CREATE TABLE dbo.DimTime (
    TimeKey   TINYINT      NOT NULL,        -- hour of the day, 0..23
    HourLabel CHAR(5)      NOT NULL,        -- 00:00 .. 23:00
    PartOfDay NVARCHAR(15) NOT NULL,        -- Night, Morning, Afternoon, Evening
    CONSTRAINT PK_DimTime PRIMARY KEY (TimeKey)
);

CREATE TABLE dbo.DimUser (
    UserKey           INT IDENTITY(1,1) NOT NULL,
    UserID            INT           NOT NULL,   -- key in SpotifyDB
    Username          NVARCHAR(50)  NOT NULL,
    DisplayName       NVARCHAR(100) NOT NULL,
    Gender            NVARCHAR(10)  NOT NULL,
    AgeGroup          NVARCHAR(10)  NOT NULL,   -- 13-17, 18-24, 25-34, 35-44, 45+
    Role              NVARCHAR(20)  NOT NULL,
    SubscriptionType  NVARCHAR(10)  NOT NULL,   -- Free / Premium (current plan)
    IsStudentVerified BIT           NOT NULL,
    RegistrationDate  DATE          NOT NULL,
    CONSTRAINT PK_DimUser PRIMARY KEY (UserKey),
    CONSTRAINT UQ_DimUser_UserID UNIQUE (UserID)
);

CREATE TABLE dbo.DimLocation (
    LocationKey INT IDENTITY(1,1) NOT NULL,
    CountryID   INT          NOT NULL,
    CountryName NVARCHAR(60) NOT NULL,
    IsoCode     CHAR(2)      NOT NULL,
    Region      NVARCHAR(50) NOT NULL,
    CONSTRAINT PK_DimLocation PRIMARY KEY (LocationKey),
    CONSTRAINT UQ_DimLocation_CountryID UNIQUE (CountryID)
);

CREATE TABLE dbo.DimTrack (
    TrackKey        INT IDENTITY(1,1) NOT NULL,
    TrackID         INT           NOT NULL,
    Title           NVARCHAR(200) NOT NULL,
    AlbumTitle      NVARCHAR(200) NOT NULL,
    AlbumType       NVARCHAR(10)  NOT NULL,
    Label           NVARCHAR(100) NOT NULL,
    ReleaseDate     DATE          NOT NULL,
    ReleaseYear     SMALLINT      NOT NULL,
    DurationSeconds SMALLINT      NOT NULL,
    IsExplicit      BIT           NOT NULL,
    CONSTRAINT PK_DimTrack PRIMARY KEY (TrackKey),
    CONSTRAINT UQ_DimTrack_TrackID UNIQUE (TrackID)
);

CREATE TABLE dbo.DimArtist (
    ArtistKey        INT IDENTITY(1,1) NOT NULL,
    ArtistID         INT           NOT NULL,
    ArtistName       NVARCHAR(150) NOT NULL,
    IsVerified       BIT           NOT NULL,
    MonthlyListeners INT           NOT NULL,
    FollowersCount   INT           NOT NULL,
    CONSTRAINT PK_DimArtist PRIMARY KEY (ArtistKey),
    CONSTRAINT UQ_DimArtist_ArtistID UNIQUE (ArtistID)
);

CREATE TABLE dbo.DimGenre (
    GenreKey  INT IDENTITY(1,1) NOT NULL,
    GenreID   INT          NOT NULL,
    GenreName NVARCHAR(50) NOT NULL,
    CONSTRAINT PK_DimGenre PRIMARY KEY (GenreKey),
    CONSTRAINT UQ_DimGenre_GenreID UNIQUE (GenreID)
);

CREATE TABLE dbo.DimDevice (
    DeviceKey  INT IDENTITY(1,1) NOT NULL,
    DeviceID   INT          NOT NULL,
    DeviceType NVARCHAR(30) NOT NULL,
    Platform   NVARCHAR(30) NOT NULL,
    CONSTRAINT PK_DimDevice PRIMARY KEY (DeviceKey),
    CONSTRAINT UQ_DimDevice_DeviceID UNIQUE (DeviceID)
);

CREATE TABLE dbo.DimPlan (
    PlanKey      INT IDENTITY(1,1) NOT NULL,
    PlanID       INT          NOT NULL,
    PlanName     NVARCHAR(50) NOT NULL,
    PlanType     NVARCHAR(10) NOT NULL,     -- Free / Premium
    MonthlyPrice DECIMAL(6,2) NOT NULL,
    MaxAccounts  TINYINT      NOT NULL,
    HasAds       BIT          NOT NULL,
    CONSTRAINT PK_DimPlan PRIMARY KEY (PlanKey),
    CONSTRAINT UQ_DimPlan_PlanID UNIQUE (PlanID)
);

CREATE TABLE dbo.DimPaymentMethod (
    PaymentMethodKey INT IDENTITY(1,1) NOT NULL,
    MethodName       NVARCHAR(20) NOT NULL,     -- Card, PayPal, Voucher
    MethodType       NVARCHAR(20) NOT NULL,     -- Bank card, E-wallet, Prepaid
    CONSTRAINT PK_DimPaymentMethod PRIMARY KEY (PaymentMethodKey),
    CONSTRAINT UQ_DimPaymentMethod_Name UNIQUE (MethodName)
);

/* ---------------------------------------------------------------------------
   Fact tables
   --------------------------------------------------------------------------- */
-- grain: one row per play of a track
CREATE TABLE dbo.FactStreams (
    StreamKey     BIGINT IDENTITY(1,1) NOT NULL,
    StreamID      BIGINT       NOT NULL,
    DateKey       INT          NOT NULL,
    TimeKey       TINYINT      NOT NULL,
    UserKey       INT          NOT NULL,
    LocationKey   INT          NOT NULL,    -- where the track was played
    TrackKey      INT          NOT NULL,
    ArtistKey     INT          NOT NULL,    -- main artist of the track
    GenreKey      INT          NOT NULL,    -- primary genre of the track
    DeviceKey     INT          NOT NULL,
    SecondsPlayed SMALLINT     NOT NULL,
    MinutesPlayed DECIMAL(6,2) NOT NULL,
    StreamCount   TINYINT      NOT NULL,    -- always 1, makes counting easy
    IsCounted     BIT          NOT NULL,    -- 1 when 30 or more seconds were played
    IsSkipped     BIT          NOT NULL,
    CONSTRAINT PK_FactStreams PRIMARY KEY (StreamKey),
    CONSTRAINT FK_FactStreams_Date     FOREIGN KEY (DateKey)     REFERENCES dbo.DimDate (DateKey),
    CONSTRAINT FK_FactStreams_Time     FOREIGN KEY (TimeKey)     REFERENCES dbo.DimTime (TimeKey),
    CONSTRAINT FK_FactStreams_User     FOREIGN KEY (UserKey)     REFERENCES dbo.DimUser (UserKey),
    CONSTRAINT FK_FactStreams_Location FOREIGN KEY (LocationKey) REFERENCES dbo.DimLocation (LocationKey),
    CONSTRAINT FK_FactStreams_Track    FOREIGN KEY (TrackKey)    REFERENCES dbo.DimTrack (TrackKey),
    CONSTRAINT FK_FactStreams_Artist   FOREIGN KEY (ArtistKey)   REFERENCES dbo.DimArtist (ArtistKey),
    CONSTRAINT FK_FactStreams_Genre    FOREIGN KEY (GenreKey)    REFERENCES dbo.DimGenre (GenreKey),
    CONSTRAINT FK_FactStreams_Device   FOREIGN KEY (DeviceKey)   REFERENCES dbo.DimDevice (DeviceKey)
);

-- grain: one row per payment attempt
CREATE TABLE dbo.FactPayments (
    PaymentKey       INT IDENTITY(1,1) NOT NULL,
    PaymentID        INT          NOT NULL,
    SubscriptionID   INT          NOT NULL,
    DateKey          INT          NOT NULL,
    UserKey          INT          NOT NULL,
    LocationKey      INT          NOT NULL,     -- country of the user
    PlanKey          INT          NOT NULL,
    PaymentMethodKey INT          NOT NULL,
    Amount           DECIMAL(8,2) NOT NULL,
    RefundedAmount   DECIMAL(8,2) NOT NULL,
    Currency         CHAR(3)      NOT NULL,
    PaymentCount     TINYINT      NOT NULL,     -- always 1
    IsSuccessful     BIT          NOT NULL,
    IsFailed         BIT          NOT NULL,
    IsRefunded       BIT          NOT NULL,
    CONSTRAINT PK_FactPayments PRIMARY KEY (PaymentKey),
    CONSTRAINT FK_FactPayments_Date     FOREIGN KEY (DateKey)          REFERENCES dbo.DimDate (DateKey),
    CONSTRAINT FK_FactPayments_User     FOREIGN KEY (UserKey)          REFERENCES dbo.DimUser (UserKey),
    CONSTRAINT FK_FactPayments_Location FOREIGN KEY (LocationKey)      REFERENCES dbo.DimLocation (LocationKey),
    CONSTRAINT FK_FactPayments_Plan     FOREIGN KEY (PlanKey)          REFERENCES dbo.DimPlan (PlanKey),
    CONSTRAINT FK_FactPayments_Method   FOREIGN KEY (PaymentMethodKey) REFERENCES dbo.DimPaymentMethod (PaymentMethodKey)
);

-- grain: one row per subscription period of a user
CREATE TABLE dbo.FactSubscriptions (
    SubscriptionKey   INT IDENTITY(1,1) NOT NULL,
    SubscriptionID    INT          NOT NULL,
    StartDateKey      INT          NOT NULL,
    EndDateKey        INT          NULL,        -- NULL while the subscription is running
    UserKey           INT          NOT NULL,
    LocationKey       INT          NOT NULL,
    PlanKey           INT          NOT NULL,
    DurationDays      SMALLINT     NOT NULL,
    MonthlyPrice      DECIMAL(6,2) NOT NULL,
    SubscriptionCount TINYINT      NOT NULL,    -- always 1
    IsPremium         BIT          NOT NULL,
    IsActive          BIT          NOT NULL,
    IsCancelled       BIT          NOT NULL,    -- the user left a paid plan (churn)
    IsUpgradeFromFree BIT          NOT NULL,    -- paid plan that directly follows Free
    AutoRenew         BIT          NOT NULL,
    CONSTRAINT PK_FactSubscriptions PRIMARY KEY (SubscriptionKey),
    CONSTRAINT FK_FactSubscriptions_StartDate FOREIGN KEY (StartDateKey) REFERENCES dbo.DimDate (DateKey),
    CONSTRAINT FK_FactSubscriptions_EndDate   FOREIGN KEY (EndDateKey)   REFERENCES dbo.DimDate (DateKey),
    CONSTRAINT FK_FactSubscriptions_User      FOREIGN KEY (UserKey)      REFERENCES dbo.DimUser (UserKey),
    CONSTRAINT FK_FactSubscriptions_Location  FOREIGN KEY (LocationKey)  REFERENCES dbo.DimLocation (LocationKey),
    CONSTRAINT FK_FactSubscriptions_Plan      FOREIGN KEY (PlanKey)      REFERENCES dbo.DimPlan (PlanKey)
);

CREATE INDEX IX_FactStreams_DateKey        ON dbo.FactStreams (DateKey);
CREATE INDEX IX_FactStreams_TrackKey       ON dbo.FactStreams (TrackKey);
CREATE INDEX IX_FactPayments_DateKey       ON dbo.FactPayments (DateKey);
CREATE INDEX IX_FactSubscriptions_StartKey ON dbo.FactSubscriptions (StartDateKey);
GO

PRINT 'SpotifyDW created: 3 fact tables, 10 dimension tables.';
GO
