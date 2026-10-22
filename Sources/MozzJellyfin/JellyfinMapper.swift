import Foundation
import MozzCore

/// Pure DTO -> domain mapping. No I/O, so it is exhaustively unit-testable
/// against recorded fixtures.
enum JellyfinMapper {
    static let ticksPerSecond: Double = 10_000_000

    static func artist(_ item: JFBaseItem) -> Artist {
        Artist(
            id: item.Id,
            name: item.Name ?? "Unknown Artist",
            sortName: item.SortName,
            artwork: primaryArtwork(item),
            genres: item.Genres ?? [],
            isFavorite: item.UserData?.IsFavorite ?? false
        )
    }

    static func album(_ item: JFBaseItem) -> Album {
        Album(
            id: item.Id,
            title: item.Name ?? "Unknown Album",
            sortTitle: item.SortName,
            artistName: item.AlbumArtist ?? item.AlbumArtists?.first?.Name ?? "Unknown Artist",
            artistID: item.AlbumArtists?.first?.Id,
            year: item.ProductionYear,
            artwork: primaryArtwork(item),
            trackCount: item.ChildCount,
            genres: item.Genres ?? [],
            isFavorite: item.UserData?.IsFavorite ?? false,
            addedAt: date(item.DateCreated)
        )
    }

    static func track(_ item: JFBaseItem) -> Track {
        let source = item.MediaSources?.first
        let audio = source?.MediaStreams?.first(where: { $0.streamType == "Audio" })
        let bitrate = (audio?.BitRate ?? source?.Bitrate).map { $0 / 1000 }
        let format = AudioFormat(
            container: source?.Container,
            codec: audio?.Codec,
            bitrateKbps: bitrate,
            sampleRateHz: audio?.SampleRate,
            channels: audio?.Channels,
            bitDepth: audio?.BitDepth
        )
        return Track(
            id: item.Id,
            title: item.Name ?? "Unknown",
            sortTitle: item.SortName,
            albumTitle: item.Album,
            albumID: item.AlbumId,
            artistName: item.ArtistItems?.first?.Name ?? item.Artists?.first ?? item.AlbumArtist ?? "Unknown Artist",
            artistID: item.ArtistItems?.first?.Id,
            albumArtistName: item.AlbumArtist,
            trackNumber: item.IndexNumber,
            discNumber: item.ParentIndexNumber,
            duration: item.RunTimeTicks.map { Double($0) / ticksPerSecond } ?? 0,
            format: format,
            fileSizeBytes: source?.Size,
            mediaKey: item.Id,
            artwork: primaryArtwork(item),
            genres: item.Genres ?? [],
            isFavorite: item.UserData?.IsFavorite ?? false,
            normalizationGainDB: item.NormalizationGain,
            addedAt: date(item.DateCreated),
            mbid: mbid(item.ProviderIds, key: "MusicBrainzTrack"),
            artistMbid: mbid(item.ProviderIds, key: "MusicBrainzArtist")
        )
    }

    static func playlist(_ item: JFBaseItem) -> Playlist {
        Playlist(
            id: item.Id,
            title: item.Name ?? "Playlist",
            trackCount: item.ChildCount,
            durationSeconds: item.RunTimeTicks.map { Double($0) / ticksPerSecond },
            artwork: primaryArtwork(item),
            isSmart: false
        )
    }

    /// Embedded and sidecar covers use the same Primary endpoint. A parent
    /// reference proves an image exists even when its optional cache tag is absent.
    private static func primaryArtwork(_ item: JFBaseItem) -> ArtworkRef? {
        if let tag = item.ImageTags?["Primary"],
           let own = artwork(itemID: item.Id, tag: tag) {
            return own
        }
        if let parent = artwork(itemID: item.ParentPrimaryImageItemId, tag: item.ParentPrimaryImageTag) {
            return parent
        }
        if let tag = item.AlbumPrimaryImageTag {
            return artwork(itemID: item.AlbumId, tag: tag)
        }
        return nil
    }

    private static func artwork(itemID: String?, tag: String?) -> ArtworkRef? {
        guard let itemID = itemID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !itemID.isEmpty else { return nil }
        let tag = tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ArtworkRef(key: tag.flatMap { $0.isEmpty ? nil : "\(itemID)|\($0)" } ?? itemID)
    }

    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoFractional.date(from: string) ?? isoPlain.date(from: string)
    }

    /// Read and validate an MBID from Jellyfin's `ProviderIds`. `MusicBrainzTrack`
    /// is the *recording* MBID (Picard's `MUSICBRAINZ_TRACKID`), which is what
    /// ListenBrainz similarity keys on — not `MusicBrainzReleaseTrack`.
    static func mbid(_ providerIds: [String: String]?, key: String) -> String? {
        MusicBrainzID.extract(fromGUID: providerIds?[key])
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain = ISO8601DateFormatter()
}
