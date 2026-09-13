using System;
using System.IO;
using System.Linq;
using Mozz.Desktop.Core;
using Xunit;

namespace Mozz.Desktop.Tests;

public sealed class MozzServerSyncTests
{
    private static (
        MozzServer Server,
        FileSecretStore Secrets,
        string AccountsPath
    ) MakeServer()
    {
        var root = Path.Combine(
            Path.GetTempPath(), "mozz-server-sync-" + Guid.NewGuid().ToString("N"));
        var secrets = new FileSecretStore(Path.Combine(root, "secrets"));
        var accounts = Path.Combine(root, "accounts.json");
        return (new MozzServer(new MozzCore(), secrets, accounts), secrets, accounts);
    }

    private static ServerAccount Account(string id = "plex:machine") => new()
    {
        ServerId = id,
        Kind = BackendKind.Plex,
        BaseUrl = "https://plex.example.test",
        ServerName = "Home Plex",
        UserId = "managed-user",
        Username = "Music Room",
        ClientIdentifier = "local-client",
        ServerMachineIdentifier = "machine",
        MusicSectionId = "music",
    };

    [Fact]
    public void ExistingSavedAccountsSeedTheSyncJournal()
    {
        var (server, _, _) = MakeServer();
        server.SaveAccount(
            Account(), secret: "server-token",
            accountToken: "switched-profile-token");

        var record = server.ExportSyncedServers().Single();

        Assert.Equal("server-token", record.Token);
        Assert.Equal("switched-profile-token", record.AccountToken);
        Assert.Equal("managed-user", record.UserId);
        Assert.NotNull(record.MusicSectionIds);
        Assert.Equal(["music"], record.MusicSectionIds);
        var json = System.Text.Json.JsonSerializer.Serialize(record);
        Assert.DoesNotContain("local-client", json);
    }

    [Fact]
    public void ImportedServerUsesThisInstallationsClientIdentifier()
    {
        var (server, secrets, _) = MakeServer();
        secrets.Set("clientIdentifier", "this-device-client");
        var remote = new RelayServerRecordDto
        {
            Id = "jellyfin:user",
            Kind = "jellyfin",
            Name = "Home Music",
            BaseUrl = "https://music.example.test",
            Token = "remote-token",
            UserId = "user",
            Username = "listener",
            UpdatedAtMS = 100,
        };

        var imported = server.ImportSyncedServers([remote]);

        Assert.Single(imported.Added);
        Assert.Single(imported.Changed);
        var account = server.SavedAccounts().Single();
        Assert.Equal("this-device-client", account.ClientIdentifier);
        Assert.Equal("remote-token", secrets.Get("token.jellyfin:user"));
    }

    [Fact]
    public void ImportedServerPreservesEverySelectedMusicLibrary()
    {
        var (server, _, _) = MakeServer();
        var remote = new RelayServerRecordDto
        {
            Id = "plex-machine",
            Kind = "plex",
            Name = "Home Plex",
            BaseUrl = "https://plex.example.test",
            Token = "remote-token",
            UserId = "managed-user",
            ServerMachineIdentifier = "machine",
            MusicSectionIds = ["music-2", "music-1"],
            AllMusicLibraries = true,
            UpdatedAtMS = 100,
        };

        server.ImportSyncedServers([remote]);
        var account = server.SavedAccounts().Single();

        Assert.Equal("music-2", account.MusicSectionId);
        Assert.Equal(
            ["music-1", "music-2"],
            MozzServer.EffectiveMusicSectionIds(account));
        Assert.True(account.AllMusicLibraries);
    }

    [Fact]
    public void RemoteTombstoneRemovesAccountAndCredential()
    {
        var (server, secrets, _) = MakeServer();
        server.SaveAccount(Account(), "server-token");
        var canonicalID = server.ExportSyncedServers().Single().Id;
        var removed = new RelayServerRecordDto
        {
            Id = canonicalID,
            Kind = "plex",
            UpdatedAtMS = long.MaxValue,
            RemovedAtMS = long.MaxValue,
        };

        server.ImportSyncedServers([removed]);

        Assert.Empty(server.SavedAccounts());
        Assert.Null(secrets.Get($"token.{canonicalID}"));
    }

    [Fact]
    public void ImportingTheSameServerTwiceDoesNotReportItNewTwice()
    {
        var (server, _, _) = MakeServer();
        var remote = new RelayServerRecordDto
        {
            Id = "subsonic:user",
            Kind = "subsonic",
            Name = "Navidrome",
            BaseUrl = "https://music.example.test",
            Token = "credential-envelope",
            UserId = "user",
            UpdatedAtMS = 100,
        };

        Assert.Single(server.ImportSyncedServers([remote]).Added);
        var replay = server.ImportSyncedServers([remote]);
        Assert.Empty(replay.Added);
        Assert.Empty(replay.Changed);
    }

    [Fact]
    public void NewerCredentialForExistingServerIsChangedButNotAdded()
    {
        var (server, secrets, _) = MakeServer();
        server.SaveAccount(Account(), "old-token");
        var existing = server.ExportSyncedServers().Single();
        var remote = existing with
        {
            Token = "new-token",
            UpdatedAtMS = existing.UpdatedAtMS + 1,
        };

        var imported = server.ImportSyncedServers([remote]);

        Assert.Empty(imported.Added);
        Assert.Single(imported.Changed);
        Assert.Equal("new-token", secrets.Get($"token.{existing.Id}"));
    }

    /// <summary>
    /// A sync from another device must not move you to a different library.
    ///
    /// The head of the accounts list is which server is being browsed. The
    /// import rebuilds that list from the journal's order, which has nothing to
    /// do with anyone's choice — so without holding the head, signing in to
    /// something on a laptop silently switched the desktop's library.
    /// </summary>
    [Fact]
    public void AnImportDoesNotChangeWhichServerIsBeingBrowsed()
    {
        var (server, secrets, _) = MakeServer();
        secrets.Set("clientIdentifier", "this-device-client");
        server.SaveAccount(Account("plex:machine"), secret: "plex-token", accountToken: null);

        server.ImportSyncedServers([new RelayServerRecordDto
        {
            Id = "jellyfin:user",
            Kind = "jellyfin",
            Name = "Laptop Jellyfin",
            BaseUrl = "https://music.example.test",
            Token = "remote-token",
            UpdatedAtMS = 500,
        }]);

        var accounts = server.SavedAccounts();
        Assert.Equal(2, accounts.Count);
        Assert.Equal("plex-machine", accounts[0].ServerId);
    }

    /// <summary>
    /// Unless the server being browsed is the one signed out elsewhere — then
    /// there is nothing to hold on to and the next one takes over, which is the
    /// same rule as signing out of it locally.
    /// </summary>
    [Fact]
    public void TheBrowsedServerBeingSignedOutElsewherePromotesTheNext()
    {
        var (server, secrets, _) = MakeServer();
        secrets.Set("clientIdentifier", "this-device-client");
        server.SaveAccount(Account("plex:machine"), secret: "plex-token", accountToken: null);
        server.ImportSyncedServers([new RelayServerRecordDto
        {
            Id = "jellyfin:user",
            Kind = "jellyfin",
            Name = "Laptop Jellyfin",
            BaseUrl = "https://music.example.test",
            Token = "remote-token",
            UpdatedAtMS = 500,
        }]);

        server.ImportSyncedServers([new RelayServerRecordDto
        {
            Id = "plex-machine",
            Kind = "plex",
            Name = "Home Plex",
            BaseUrl = "https://plex.example.test",
            // Later than the local record, or the merge rightly keeps ours:
            // saving an account stamps it with the wall clock.
            UpdatedAtMS = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() + 10_000,
            RemovedAtMS = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() + 10_000,
        }]);

        var accounts = server.SavedAccounts();
        Assert.Equal(["jellyfin:user"], accounts.Select(a => a.ServerId));
    }
}
