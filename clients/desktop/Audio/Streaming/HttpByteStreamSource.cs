using System.IO;
using System.Net.Http;
using System.Threading;

namespace Mozz.Desktop.Audio.Streaming;

/// <summary>
/// Reads a track from a media server over HTTP, carrying the caller's
/// credentials. This is the price of one shared engine instead of a different
/// media framework on every platform, and it buys back the same streaming
/// behaviour everywhere.
///
/// Seeks are served by a fresh ranged request rather than by buffering the
/// whole file. A range the server ignores — some answer <c>200</c> with the
/// whole body instead of <c>206</c> — is detected and treated as a failure
/// rather than silently decoding from the wrong offset, which would sound like
/// a corrupt file rather than a bug. That single rule is the reason this class
/// exists as its own type and is unit-tested in isolation.
/// </summary>
public sealed class HttpByteStreamSource : ByteStreamSource
{
    // One client for the whole app. Per-request timeouts come from a
    // CancellationToken, so the client's own timeout is disabled; leaving it at
    // the 100s default would cut a legitimately slow large-chunk read short.
    private static readonly HttpClient SharedClient =
        new() { Timeout = Timeout.InfiniteTimeSpan };

    private static readonly object PrewarmLock = new();
    private static readonly Dictionary<string, DateTime> LastPrewarm = new();

    /// <summary>
    /// Open a connection to <paramref name="baseUrl"/>'s host in the pool every stream reads
    /// through, before the first stream needs one — so the first chunk of the first song after
    /// launch, or after the app has sat idle, does not also pay for DNS, TCP and TLS. That setup
    /// is most of what a cold first play waits for, and it has to be this client's pool: a warm
    /// connection anywhere else would not be reused.
    /// </summary>
    /// <remarks>
    /// A HEAD with no credentials: the answer does not matter (a 401 warms the connection as well
    /// as a 200), and sending nothing means nothing sensitive goes anywhere. Fire and forget, never
    /// throws, and at most once every 30 seconds per server. The same rule the phones follow.
    /// </remarks>
    public static void Prewarm(string? baseUrl) => _ = Prewarm(baseUrl, SharedClient);

    /// <summary>The same, through <paramref name="client"/>; returns the request in flight, or null when skipped.</summary>
    internal static Task? Prewarm(string? baseUrl, HttpClient client)
    {
        if (!Uri.TryCreate(baseUrl, UriKind.Absolute, out var uri)
            || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
        {
            return null;
        }
        var server = uri.GetLeftPart(UriPartial.Authority);
        lock (PrewarmLock)
        {
            if (LastPrewarm.TryGetValue(server, out var at) && DateTime.UtcNow - at < TimeSpan.FromSeconds(30))
            {
                return null;
            }
            LastPrewarm[server] = DateTime.UtcNow;
        }
        return Task.Run(async () =>
        {
            try
            {
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
                using var request = new HttpRequestMessage(HttpMethod.Head, uri);
                using var _ = await client.SendAsync(
                    request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
            }
            catch
            {
                // Warming is an optimisation; a server that does not answer will be
                // reported by the play that actually needs it.
            }
        });
    }

    private readonly HttpClient _client;
    private readonly string _url;
    private readonly IReadOnlyDictionary<string, string> _headers;
    private readonly int _chunkSize;
    private readonly TimeSpan _timeout;

    /// <summary>Bytes already delivered, which is also the offset the next request needs.</summary>
    private long _position;
    /// <summary>Total length once the server has told us; null until the first response.</summary>
    private long? _totalLength;
    /// <summary>Whatever the last response delivered that has not been read yet.</summary>
    private byte[] _buffered = Array.Empty<byte>();
    /// <summary>Absolute offset the buffer starts at.</summary>
    private long _bufferStart;
    private bool _closed;

    public HttpByteStreamSource(
        string url,
        IReadOnlyDictionary<string, string>? headers = null,
        HttpClient? client = null,
        int chunkSize = 512 * 1024,
        TimeSpan? timeout = null)
    {
        _url = url;
        _headers = headers ?? new Dictionary<string, string>();
        _client = client ?? SharedClient;
        _chunkSize = chunkSize;
        _timeout = timeout ?? TimeSpan.FromSeconds(30);
    }

    public override int Read(Span<byte> buffer)
    {
        if (_closed || buffer.Length == 0) return 0;

        if (_totalLength is { } total && _position >= total) return 0;

        if (!BufferCovers(_position))
        {
            if (!Fetch(_position, null)) return -1;
        }

        int offsetInBuffer = (int)(_position - _bufferStart);
        if (offsetInBuffer < 0 || offsetInBuffer >= _buffered.Length) return 0;

        int take = Math.Min(buffer.Length, _buffered.Length - offsetInBuffer);
        _buffered.AsSpan(offsetInBuffer, take).CopyTo(buffer);
        _position += take;
        return take;
    }

    public override long Seek(long offset, int whence)
    {
        if (_closed) return -1;

        long origin;
        switch (whence)
        {
            case 1:
                origin = _position;
                break;
            case 2:
                // Seeking from the end needs the length, and the length only
                // arrives with a response. Ask for one byte, not the file.
                if (_totalLength is null && !Fetch(0, 1)) return -1;
                origin = _totalLength ?? 0;
                break;
            default:
                origin = 0;
                break;
        }

        long target = origin + offset;
        if (target < 0) target = 0;
        if (_totalLength is { } total && target > total) target = total;
        _position = target;
        return target;
    }

    public override void Close()
    {
        if (_closed) return;
        _closed = true;
        _buffered = Array.Empty<byte>();
    }

    private bool BufferCovers(long offset)
    {
        if (_buffered.Length == 0) return false;
        return offset >= _bufferStart && offset < _bufferStart + _buffered.Length;
    }

    /// <summary>Fetch a range synchronously, replacing the buffer. Returns false on any failure.</summary>
    private bool Fetch(long offset, int? length)
    {
        try
        {
            int want = length ?? _chunkSize;
            long end = offset + want - 1;

            using var request = new HttpRequestMessage(HttpMethod.Get, _url);
            foreach (var header in _headers)
            {
                request.Headers.TryAddWithoutValidation(header.Key, header.Value);
            }
            request.Headers.TryAddWithoutValidation("Range", $"bytes={offset}-{end}");

            // A synchronous send on the decode thread, which is exactly the
            // thread meant to block. The extra five seconds mirrors the Swift
            // semaphore's slack over the request timeout.
            using var cts = new CancellationTokenSource(_timeout + TimeSpan.FromSeconds(5));
            using var response = _client.Send(
                request, HttpCompletionOption.ResponseHeadersRead, cts.Token);

            byte[] payload;
            using (var stream = response.Content.ReadAsStream(cts.Token))
            using (var memory = new MemoryStream())
            {
                stream.CopyTo(memory);
                payload = memory.ToArray();
            }

            switch ((int)response.StatusCode)
            {
                case 206:
                    // A proper partial response. Content-Range carries the true
                    // total, the only reliable place to learn it.
                    if (response.Content.Headers.ContentRange?.Length is { } parsed)
                    {
                        _totalLength = parsed;
                    }
                    _bufferStart = offset;
                    _buffered = payload;
                    return true;

                case 200:
                    // The server ignored the range and sent the whole body.
                    // Honest at offset zero, wrong anywhere else — accepting it
                    // there would decode from the start while claiming to be
                    // elsewhere, which sounds like a corrupt file.
                    if (offset != 0) return false;
                    _totalLength = payload.LongLength;
                    _bufferStart = 0;
                    _buffered = payload;
                    return true;

                case 416:
                    // Asked past the end. Not a failure: it is how a stream ends
                    // when the length was never announced.
                    _totalLength = offset;
                    _buffered = Array.Empty<byte>();
                    return true;

                default:
                    return false;
            }
        }
        catch
        {
            return false;
        }
    }
}
