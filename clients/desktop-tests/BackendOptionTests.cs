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
