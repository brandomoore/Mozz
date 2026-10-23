using System.Text.Json;
using Mozz.Desktop.Core;
using Xunit;

namespace Mozz.Desktop.Tests;

public sealed class StreamSourceTests
{
    [Fact]
    public void PreservesBackendAuthenticationHeaders()
    {
        var source = JsonSerializer.Deserialize<StreamSource>(
            """{"url":"https://example.test/audio","headers":{"Authorization":"MediaBrowser Token=\"test-only\""}}""");
        Assert.Equal("MediaBrowser Token=\"test-only\"", source!.Headers!["Authorization"]);
    }

    [Fact]
    public void AcceptsOlderBackendsWithoutHeaders()
    {
        var source = JsonSerializer.Deserialize<StreamSource>("""{"url":"https://example.test/audio"}""");
        Assert.Null(source!.Headers);
    }
}
