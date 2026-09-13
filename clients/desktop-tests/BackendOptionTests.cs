using Mozz.Desktop.Core;
using Mozz.Desktop.ViewModels;
using Xunit;

namespace Mozz.Desktop.Tests;

public sealed class BackendOptionTests
{
    /// <summary>
    /// Every backend the core speaks is offered by the picker.
    ///
    /// The gap this guards is not hypothetical: Android reached the `connect`
    /// command, which takes a BackendKind, and still offered one button —
    /// "Connect Plex" — so two of the three were unreachable from the app while
    /// every build and every check stayed green. A fourth backend landing in
    /// BackendKind should break this rather than ship a picker that quietly
    /// omits it.
    /// </summary>
    [Fact]
    public void ThePickerOffersEveryBackendTheCoreSpeaks()
    {
        var offered = BackendOption.All().Select(o => o.Kind).ToHashSet();

        Assert.Equal(Enum.GetValues<BackendKind>().ToHashSet(), offered);
    }

    /// <summary>
    /// Subsonic is a protocol, not a product, and that is the single thing most
    /// likely to make someone running Navidrome think Mozz cannot talk to their
    /// server. The row says both, exactly as iOS's does.
    /// </summary>
    [Fact]
    public void TheSubsonicRowNamesTheProductPeopleActuallyRun()
    {
        var subsonic = BackendOption.All().Single(o => o.Kind == BackendKind.Subsonic);

        Assert.Contains("Navidrome", subsonic.Label);
        Assert.Contains("Subsonic", subsonic.Label);
    }

    /// <summary>Each backend gets its own mark and its own colour; three identical
    /// grey glyphs make the choice harder than it needs to be.</summary>
    [Fact]
    public void EachBackendIsToldApartByItsOwnMarkAndColour()
    {
        var options = BackendOption.All();

        Assert.Equal(options.Count, options.Select(o => o.IconKey).Distinct().Count());
        Assert.Equal(options.Count, options.Select(o => o.Tint.ToString()!).Distinct().Count());
    }
}

public sealed class ServerRowTests
{
    private static ServerAccount Account(string name, string url, BackendKind kind = BackendKind.Jellyfin) =>
        new()
        {
            ServerId = name,
            Kind = kind,
            BaseUrl = url,
            ServerName = name,
            ClientIdentifier = "client",
        };

    /// <summary>
    /// The address earns its line; the scheme does not.
    ///
    /// The chip already says which product a row is, so with two Jellyfins on
    /// one account the address is the only thing telling them apart — and
    /// "https://" is the same on both.
    /// </summary>
    [Fact]
    public void AServerIsToldApartByItsAddress()
    {
        Assert.Equal(
            "192.168.1.10:8096",
            new ServerRow(Account("Jelly", "http://192.168.1.10:8096/"), false).Address);
        Assert.Equal(
            "music.example.com",
            new ServerRow(Account("Navi", "https://music.example.com"), false).Address);
        // A stored address with no scheme at all still reads as one.
        Assert.Equal(
            "nas.local:4533",
            new ServerRow(Account("Navi", "nas.local:4533"), false).Address);
    }

    /// <summary>Each row wears its own backend's mark, not one generic server glyph.</summary>
    [Fact]
    public void AServerWearsItsOwnBackendsMark()
    {
        Assert.Equal(
            "IconBrandPlex",
            new ServerRow(Account("Home", "https://plex.test", BackendKind.Plex), true).Brand.IconKey);
        Assert.Equal(
            "IconBrandNavidrome",
            new ServerRow(Account("VPS", "https://navi.test", BackendKind.Subsonic), false).Brand.IconKey);
    }
}
