using Avalonia;
using Avalonia.Media;
using Avalonia.Media.Immutable;
using CommunityToolkit.Mvvm.ComponentModel;
using Mozz.Desktop.Core;

namespace Mozz.Desktop.ViewModels;

/// <summary>
/// One backend in the sign-in picker: its mark, its colour and its name.
///
/// This exists so the picker is written once and drawn twice — on the first-run
/// connect panel and in Settings — rather than three rows of markup copied into
/// two places and then allowed to drift apart.
///
/// It mirrors iOS's <c>BrandStyle</c> and Android's <c>Brand</c>, down to the
/// tints. The products are recognised by their colours, and three identical grey
/// glyphs make the choice harder than it needs to be — which is what the
/// desktop's three plain radio buttons were doing.
/// </summary>
public sealed partial class BackendOption : ObservableObject
{
    /// <summary>The two-letter fallback, for the (impossible) case of a missing
    /// resource — better a letter than an empty circle.</summary>
    private static readonly Geometry Missing = StreamGeometry.Parse("M0,0");

    public BackendOption(BackendKind kind, string label, string iconKey, Color tint)
    {
        Kind = kind;
        Label = label;
        IconKey = iconKey;
        Tint = new ImmutableSolidColorBrush(tint);
        // The chip's fill is the same colour, heavily translucent, so every chip
        // carries equal weight in both themes without either one glowing.
        ChipBackground = new ImmutableSolidColorBrush(tint, 0.18);
    }

    public BackendKind Kind { get; }
    public string Label { get; }
    public string IconKey { get; }
    public IBrush Tint { get; }
    public IBrush ChipBackground { get; }

    /// <summary>
    /// Plex's chevron occupies about half of its 24×24 canvas where the other
    /// two nearly fill theirs, so at an equal inset it renders visibly smaller.
    /// iOS and Android make the same correction.
    /// </summary>
    public double GlyphSize => Kind == BackendKind.Plex ? 24 : 20;

    /// <summary>
    /// The mark, resolved from the app's merged <c>BrandIcons.axaml</c>.
    ///
    /// Looked up rather than injected because these options are built by a view
    /// model, which has no resource scope of its own, and the alternative —
    /// binding a resource key through a converter — puts the same lookup behind
    /// one more layer.
    /// </summary>
    public Geometry Icon
    {
        get
        {
            if (_icon is not null) return _icon;
            if (Application.Current is { } app
                && app.TryGetResource(IconKey, app.ActualThemeVariant, out var value)
                && value is Geometry geometry)
            {
                _icon = geometry;
            }
            return _icon ?? Missing;
        }
    }

    private Geometry? _icon;

    /// <summary>Whether this is the backend currently being signed in to.</summary>
    [ObservableProperty] private bool _isSelected;

    /// <summary>The mark and colour for one backend, for anywhere a saved server
    /// is listed rather than chosen.</summary>
    public static BackendOption For(BackendKind kind) => All().First(o => o.Kind == kind);

    /// <summary>The three Mozz can talk to, in the order iOS lists them.</summary>
    public static IReadOnlyList<BackendOption> All() =>
    [
        new(BackendKind.Jellyfin, "Jellyfin", "IconBrandJellyfin", Color.FromRgb(0x87, 0x61, 0xF2)),
        new(BackendKind.Plex, "Plex", "IconBrandPlex", Color.FromRgb(0xE5, 0xA0, 0x0D)),
        // Navidrome's mark on a Subsonic row: the protocol has no mark of its
        // own and Navidrome is what nearly everyone speaking it is running. The
        // label carries the accuracy the logo cannot.
        new(BackendKind.Subsonic, "Navidrome (Subsonic)", "IconBrandNavidrome", Color.FromRgb(0x2E, 0x86, 0xD6)),
    ];
}

/// <summary>
/// One saved server in the Servers list: which backend it is, where it is, and
/// whether it is the one being browsed.
///
/// <see cref="ServerAccount"/> is the record the core hands back and is bound
/// straight to XAML elsewhere; this wraps it with the two things only the list
/// knows — the brand mark and which row has the tick. Both phones show the
/// same two, so this is what keeps the three screens the same screen.
/// </summary>
public sealed record ServerRow(ServerAccount Account, bool IsActive)
{
    public string ServerName => Account.ServerName;

    /// <summary>
    /// The address without its scheme. The chip already says which product this
    /// is, and with two Jellyfins on one account the address is the only thing
    /// telling them apart — so it earns the line, and "https://" does not.
    /// </summary>
    public string Address
    {
        get
        {
            var url = Account.BaseUrl ?? string.Empty;
            var scheme = url.IndexOf("://", StringComparison.Ordinal);
            return (scheme >= 0 ? url[(scheme + 3)..] : url).TrimEnd('/');
        }
    }

    public BackendOption Brand => _brand ??= BackendOption.For(Account.Kind);
    private BackendOption? _brand;
}
