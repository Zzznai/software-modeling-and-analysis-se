/* ============================================================================
   Spotify - music streaming platform            (course work, FN 2401321010)
   01_create_database.sql : creates the SpotifyDB database and all tables.

   Run order:  01_create_database.sql -> 02_programmability.sql -> 03_seed_data.sql
   The script is re-runnable: it drops and recreates the database.
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;      -- needed for the filtered unique indexes (sqlcmd has it OFF by default)
GO
USE master;
GO
IF DB_ID(N'SpotifyDB') IS NOT NULL
BEGIN
    ALTER DATABASE SpotifyDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SpotifyDB;
END
GO
CREATE DATABASE SpotifyDB;
GO
USE SpotifyDB;
GO

/* ---------------------------------------------------------------------------
   Lookup tables
   --------------------------------------------------------------------------- */
CREATE TABLE dbo.Countries (
    CountryID   INT IDENTITY(1,1) NOT NULL,
    Name        NVARCHAR(60)  NOT NULL,
    IsoCode     CHAR(2)       NOT NULL,
    Region      NVARCHAR(50)  NOT NULL,
    CONSTRAINT PK_Countries PRIMARY KEY (CountryID),
    CONSTRAINT UQ_Countries_Name UNIQUE (Name),
    CONSTRAINT UQ_Countries_IsoCode UNIQUE (IsoCode)
);

CREATE TABLE dbo.Devices (
    DeviceID    INT IDENTITY(1,1) NOT NULL,
    DeviceType  NVARCHAR(30) NOT NULL,      -- Mobile, Desktop, Web, Smart speaker, TV ...
    Platform    NVARCHAR(30) NOT NULL,      -- Android, iOS, Windows ...
    CONSTRAINT PK_Devices PRIMARY KEY (DeviceID),
    CONSTRAINT UQ_Devices_Type_Platform UNIQUE (DeviceType, Platform)
);

CREATE TABLE dbo.Genres (
    GenreID     INT IDENTITY(1,1) NOT NULL,
    Name        NVARCHAR(50)  NOT NULL,
    Description NVARCHAR(300) NULL,
    CONSTRAINT PK_Genres PRIMARY KEY (GenreID),
    CONSTRAINT UQ_Genres_Name UNIQUE (Name)
);

CREATE TABLE dbo.SubscriptionPlans (
    PlanID        INT IDENTITY(1,1) NOT NULL,
    Name          NVARCHAR(50) NOT NULL,
    MonthlyPrice  DECIMAL(6,2) NOT NULL,
    MaxAccounts   TINYINT      NOT NULL CONSTRAINT DF_Plans_MaxAccounts DEFAULT (1),
    HasAds        BIT          NOT NULL CONSTRAINT DF_Plans_HasAds DEFAULT (0),
    AllowsOffline BIT          NOT NULL CONSTRAINT DF_Plans_AllowsOffline DEFAULT (1),
    SkipsPerHour  TINYINT      NULL,        -- NULL = unlimited skips
    CONSTRAINT PK_SubscriptionPlans PRIMARY KEY (PlanID),
    CONSTRAINT UQ_SubscriptionPlans_Name UNIQUE (Name),
    CONSTRAINT CK_Plans_Price CHECK (MonthlyPrice >= 0),
    CONSTRAINT CK_Plans_MaxAccounts CHECK (MaxAccounts BETWEEN 1 AND 6)
);

/* ---------------------------------------------------------------------------
   Users, subscriptions, payments
   --------------------------------------------------------------------------- */
CREATE TABLE dbo.Users (
    UserID            INT IDENTITY(1,1) NOT NULL,
    Username          NVARCHAR(50)  NOT NULL,
    Email             NVARCHAR(150) NOT NULL,
    PasswordHash      NVARCHAR(255) NOT NULL,
    DisplayName       NVARCHAR(100) NOT NULL,
    DateOfBirth       DATE          NOT NULL,
    Gender            NVARCHAR(10)  NULL,
    CountryID         INT           NOT NULL,
    Role              NVARCHAR(20)  NOT NULL CONSTRAINT DF_Users_Role DEFAULT (N'Listener'),
    IsStudentVerified BIT           NOT NULL CONSTRAINT DF_Users_IsStudent DEFAULT (0),
    RegistrationDate  DATE          NOT NULL CONSTRAINT DF_Users_RegDate DEFAULT (CAST(GETDATE() AS DATE)),
    CONSTRAINT PK_Users PRIMARY KEY (UserID),
    CONSTRAINT UQ_Users_Username UNIQUE (Username),
    CONSTRAINT UQ_Users_Email UNIQUE (Email),
    CONSTRAINT FK_Users_Countries FOREIGN KEY (CountryID) REFERENCES dbo.Countries (CountryID),
    CONSTRAINT CK_Users_Email CHECK (Email LIKE N'_%@_%._%'),
    CONSTRAINT CK_Users_Gender CHECK (Gender IN (N'Male', N'Female', N'Other')),
    CONSTRAINT CK_Users_Role CHECK (Role IN (N'Listener', N'Artist', N'Admin')),
    -- a user must be at least 13 years old when registering
    CONSTRAINT CK_Users_MinAge CHECK (DateOfBirth <= DATEADD(YEAR, -13, RegistrationDate))
);

CREATE TABLE dbo.Subscriptions (
    SubscriptionID INT IDENTITY(1,1) NOT NULL,
    UserID         INT          NOT NULL,
    PlanID         INT          NOT NULL,
    StartDate      DATE         NOT NULL,
    EndDate        DATE         NULL,       -- NULL while the subscription is running
    Status         NVARCHAR(20) NOT NULL CONSTRAINT DF_Subscriptions_Status DEFAULT (N'Active'),
    AutoRenew      BIT          NOT NULL CONSTRAINT DF_Subscriptions_AutoRenew DEFAULT (1),
    CONSTRAINT PK_Subscriptions PRIMARY KEY (SubscriptionID),
    CONSTRAINT FK_Subscriptions_Users FOREIGN KEY (UserID) REFERENCES dbo.Users (UserID),
    CONSTRAINT FK_Subscriptions_Plans FOREIGN KEY (PlanID) REFERENCES dbo.SubscriptionPlans (PlanID),
    CONSTRAINT CK_Subscriptions_Status CHECK (Status IN (N'Active', N'Cancelled', N'Expired')),
    CONSTRAINT CK_Subscriptions_Dates CHECK (EndDate IS NULL OR EndDate > StartDate),
    CONSTRAINT CK_Subscriptions_ActiveOpen CHECK (Status <> N'Active' OR EndDate IS NULL)
);
-- every user has exactly one active subscription at a time
CREATE UNIQUE INDEX UX_Subscriptions_OneActivePerUser
    ON dbo.Subscriptions (UserID) WHERE Status = N'Active';

CREATE TABLE dbo.Payments (
    PaymentID      INT IDENTITY(1,1) NOT NULL,
    SubscriptionID INT          NOT NULL,
    Amount         DECIMAL(8,2) NOT NULL,
    Currency       CHAR(3)      NOT NULL CONSTRAINT DF_Payments_Currency DEFAULT ('EUR'),
    PaymentMethod  NVARCHAR(20) NOT NULL,
    Status         NVARCHAR(20) NOT NULL,
    PaidAt         DATETIME2(0) NOT NULL CONSTRAINT DF_Payments_PaidAt DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Payments PRIMARY KEY (PaymentID),
    CONSTRAINT FK_Payments_Subscriptions FOREIGN KEY (SubscriptionID) REFERENCES dbo.Subscriptions (SubscriptionID),
    CONSTRAINT CK_Payments_Amount CHECK (Amount > 0),
    CONSTRAINT CK_Payments_Method CHECK (PaymentMethod IN (N'Card', N'PayPal', N'Voucher')),
    CONSTRAINT CK_Payments_Status CHECK (Status IN (N'Successful', N'Failed', N'Refunded'))
);

/* ---------------------------------------------------------------------------
   Music catalogue
   --------------------------------------------------------------------------- */
CREATE TABLE dbo.Artists (
    ArtistID         INT IDENTITY(1,1) NOT NULL,
    Name             NVARCHAR(150)  NOT NULL,
    Bio              NVARCHAR(1000) NULL,
    IsVerified       BIT NOT NULL CONSTRAINT DF_Artists_IsVerified DEFAULT (0),
    MonthlyListeners INT NOT NULL CONSTRAINT DF_Artists_MonthlyListeners DEFAULT (0),   -- derived
    FollowersCount   INT NOT NULL CONSTRAINT DF_Artists_FollowersCount DEFAULT (0),     -- derived
    CONSTRAINT PK_Artists PRIMARY KEY (ArtistID),
    CONSTRAINT CK_Artists_MonthlyListeners CHECK (MonthlyListeners >= 0),
    CONSTRAINT CK_Artists_FollowersCount CHECK (FollowersCount >= 0)
);

CREATE TABLE dbo.Albums (
    AlbumID       INT IDENTITY(1,1) NOT NULL,
    ArtistID      INT           NOT NULL,   -- main artist of the album
    Title         NVARCHAR(200) NOT NULL,
    AlbumType     NVARCHAR(10)  NOT NULL,
    ReleaseDate   DATE          NOT NULL,
    Label         NVARCHAR(100) NULL,
    CoverImageUrl NVARCHAR(300) NULL,
    IsApproved    BIT NOT NULL CONSTRAINT DF_Albums_IsApproved DEFAULT (0),  -- approved by an administrator
    CONSTRAINT PK_Albums PRIMARY KEY (AlbumID),
    CONSTRAINT FK_Albums_Artists FOREIGN KEY (ArtistID) REFERENCES dbo.Artists (ArtistID),
    CONSTRAINT CK_Albums_Type CHECK (AlbumType IN (N'Album', N'Single', N'EP'))
);

CREATE TABLE dbo.Tracks (
    TrackID         INT IDENTITY(1,1) NOT NULL,
    AlbumID         INT           NOT NULL,
    Title           NVARCHAR(200) NOT NULL,
    TrackNumber     TINYINT       NOT NULL,
    DurationSeconds SMALLINT      NOT NULL,
    IsExplicit      BIT NOT NULL CONSTRAINT DF_Tracks_IsExplicit DEFAULT (0),
    AudioUrl        NVARCHAR(300) NULL,
    PlayCount       BIGINT NOT NULL CONSTRAINT DF_Tracks_PlayCount DEFAULT (0),          -- derived
    CONSTRAINT PK_Tracks PRIMARY KEY (TrackID),
    CONSTRAINT FK_Tracks_Albums FOREIGN KEY (AlbumID) REFERENCES dbo.Albums (AlbumID),
    CONSTRAINT UQ_Tracks_Album_Number UNIQUE (AlbumID, TrackNumber),
    CONSTRAINT CK_Tracks_Duration CHECK (DurationSeconds BETWEEN 1 AND 3600),
    CONSTRAINT CK_Tracks_PlayCount CHECK (PlayCount >= 0)
);

-- M:N  Tracks <-> Artists (a track can have featured artists)
CREATE TABLE dbo.TrackArtists (
    TrackID      INT NOT NULL,
    ArtistID     INT NOT NULL,
    IsMainArtist BIT NOT NULL CONSTRAINT DF_TrackArtists_IsMain DEFAULT (0),
    CONSTRAINT PK_TrackArtists PRIMARY KEY (TrackID, ArtistID),
    CONSTRAINT FK_TrackArtists_Tracks FOREIGN KEY (TrackID) REFERENCES dbo.Tracks (TrackID),
    CONSTRAINT FK_TrackArtists_Artists FOREIGN KEY (ArtistID) REFERENCES dbo.Artists (ArtistID)
);
CREATE UNIQUE INDEX UX_TrackArtists_OneMain ON dbo.TrackArtists (TrackID) WHERE IsMainArtist = 1;

-- M:N  Tracks <-> Genres
CREATE TABLE dbo.TrackGenres (
    TrackID   INT NOT NULL,
    GenreID   INT NOT NULL,
    IsPrimary BIT NOT NULL CONSTRAINT DF_TrackGenres_IsPrimary DEFAULT (0),
    CONSTRAINT PK_TrackGenres PRIMARY KEY (TrackID, GenreID),
    CONSTRAINT FK_TrackGenres_Tracks FOREIGN KEY (TrackID) REFERENCES dbo.Tracks (TrackID),
    CONSTRAINT FK_TrackGenres_Genres FOREIGN KEY (GenreID) REFERENCES dbo.Genres (GenreID)
);
CREATE UNIQUE INDEX UX_TrackGenres_OnePrimary ON dbo.TrackGenres (TrackID) WHERE IsPrimary = 1;

/* ---------------------------------------------------------------------------
   Playlists and library
   --------------------------------------------------------------------------- */
CREATE TABLE dbo.Playlists (
    PlaylistID  INT IDENTITY(1,1) NOT NULL,
    UserID      INT           NOT NULL,     -- owner
    Name        NVARCHAR(100) NOT NULL,
    Description NVARCHAR(300) NULL,
    IsPublic    BIT NOT NULL CONSTRAINT DF_Playlists_IsPublic DEFAULT (1),
    CreatedAt   DATETIME2(0) NOT NULL CONSTRAINT DF_Playlists_CreatedAt DEFAULT (SYSDATETIME()),
    UpdatedAt   DATETIME2(0) NULL,
    CONSTRAINT PK_Playlists PRIMARY KEY (PlaylistID),
    -- deleting a user deletes the user's playlists
    CONSTRAINT FK_Playlists_Users FOREIGN KEY (UserID) REFERENCES dbo.Users (UserID) ON DELETE CASCADE
);

-- M:N  Playlists <-> Tracks
CREATE TABLE dbo.PlaylistTracks (
    PlaylistID INT      NOT NULL,
    TrackID    INT      NOT NULL,
    Position   SMALLINT NOT NULL,
    AddedAt    DATETIME2(0) NOT NULL CONSTRAINT DF_PlaylistTracks_AddedAt DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_PlaylistTracks PRIMARY KEY (PlaylistID, TrackID),   -- a track only once per playlist
    CONSTRAINT FK_PlaylistTracks_Playlists FOREIGN KEY (PlaylistID) REFERENCES dbo.Playlists (PlaylistID) ON DELETE CASCADE,
    CONSTRAINT FK_PlaylistTracks_Tracks FOREIGN KEY (TrackID) REFERENCES dbo.Tracks (TrackID),
    CONSTRAINT UQ_PlaylistTracks_Position UNIQUE (PlaylistID, Position),
    CONSTRAINT CK_PlaylistTracks_Position CHECK (Position BETWEEN 1 AND 10000)   -- max 10 000 tracks
);

-- M:N  Users <-> Tracks ("Liked Songs")
CREATE TABLE dbo.LikedTracks (
    UserID  INT NOT NULL,
    TrackID INT NOT NULL,
    LikedAt DATETIME2(0) NOT NULL CONSTRAINT DF_LikedTracks_LikedAt DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_LikedTracks PRIMARY KEY (UserID, TrackID),
    CONSTRAINT FK_LikedTracks_Users FOREIGN KEY (UserID) REFERENCES dbo.Users (UserID),
    CONSTRAINT FK_LikedTracks_Tracks FOREIGN KEY (TrackID) REFERENCES dbo.Tracks (TrackID)
);

-- M:N  Users <-> Artists
CREATE TABLE dbo.ArtistFollowers (
    UserID     INT NOT NULL,
    ArtistID   INT NOT NULL,
    FollowedAt DATETIME2(0) NOT NULL CONSTRAINT DF_ArtistFollowers_FollowedAt DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_ArtistFollowers PRIMARY KEY (UserID, ArtistID),
    CONSTRAINT FK_ArtistFollowers_Users FOREIGN KEY (UserID) REFERENCES dbo.Users (UserID),
    CONSTRAINT FK_ArtistFollowers_Artists FOREIGN KEY (ArtistID) REFERENCES dbo.Artists (ArtistID)
);

-- M:N  Users <-> Users
CREATE TABLE dbo.UserFollowers (
    FollowerID     INT NOT NULL,
    FollowedUserID INT NOT NULL,
    FollowedAt     DATETIME2(0) NOT NULL CONSTRAINT DF_UserFollowers_FollowedAt DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_UserFollowers PRIMARY KEY (FollowerID, FollowedUserID),
    CONSTRAINT FK_UserFollowers_Follower FOREIGN KEY (FollowerID) REFERENCES dbo.Users (UserID),
    CONSTRAINT FK_UserFollowers_Followed FOREIGN KEY (FollowedUserID) REFERENCES dbo.Users (UserID),
    CONSTRAINT CK_UserFollowers_NotSelf CHECK (FollowerID <> FollowedUserID)   -- nobody follows themselves
);

/* ---------------------------------------------------------------------------
   Listening history
   --------------------------------------------------------------------------- */
CREATE TABLE dbo.Streams (
    StreamID      BIGINT IDENTITY(1,1) NOT NULL,
    UserID        INT NOT NULL,
    TrackID       INT NOT NULL,
    CountryID     INT NOT NULL,             -- where the track was played
    DeviceID      INT NOT NULL,
    StartedAt     DATETIME2(0) NOT NULL CONSTRAINT DF_Streams_StartedAt DEFAULT (SYSDATETIME()),
    SecondsPlayed SMALLINT NOT NULL,
    IsSkipped     BIT NOT NULL CONSTRAINT DF_Streams_IsSkipped DEFAULT (0),
    CONSTRAINT PK_Streams PRIMARY KEY (StreamID),
    CONSTRAINT FK_Streams_Users FOREIGN KEY (UserID) REFERENCES dbo.Users (UserID),
    CONSTRAINT FK_Streams_Tracks FOREIGN KEY (TrackID) REFERENCES dbo.Tracks (TrackID),
    CONSTRAINT FK_Streams_Countries FOREIGN KEY (CountryID) REFERENCES dbo.Countries (CountryID),
    CONSTRAINT FK_Streams_Devices FOREIGN KEY (DeviceID) REFERENCES dbo.Devices (DeviceID),
    CONSTRAINT CK_Streams_Seconds CHECK (SecondsPlayed >= 0)
);

/* ---------------------------------------------------------------------------
   Indexes on foreign keys and the most common search columns
   --------------------------------------------------------------------------- */
CREATE INDEX IX_Users_CountryID          ON dbo.Users (CountryID);
CREATE INDEX IX_Subscriptions_UserID     ON dbo.Subscriptions (UserID);
CREATE INDEX IX_Subscriptions_PlanID     ON dbo.Subscriptions (PlanID);
CREATE INDEX IX_Payments_SubscriptionID  ON dbo.Payments (SubscriptionID);
CREATE INDEX IX_Albums_ArtistID          ON dbo.Albums (ArtistID);
CREATE INDEX IX_Tracks_Title             ON dbo.Tracks (Title);
CREATE INDEX IX_TrackArtists_ArtistID    ON dbo.TrackArtists (ArtistID);
CREATE INDEX IX_TrackGenres_GenreID      ON dbo.TrackGenres (GenreID);
CREATE INDEX IX_Playlists_UserID         ON dbo.Playlists (UserID);
CREATE INDEX IX_PlaylistTracks_TrackID   ON dbo.PlaylistTracks (TrackID);
CREATE INDEX IX_Streams_UserID_StartedAt ON dbo.Streams (UserID, StartedAt);
CREATE INDEX IX_Streams_TrackID          ON dbo.Streams (TrackID);
CREATE INDEX IX_Streams_StartedAt        ON dbo.Streams (StartedAt);
GO

PRINT 'SpotifyDB created: 18 tables.';
GO
