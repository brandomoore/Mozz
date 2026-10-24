using System.Text.Json;
using Mozz.Desktop.Core;
using Xunit;

namespace Mozz.Desktop.Tests;

public sealed class NetworkStatusTests
{
    [Fact]
    public void InterfaceSnapshotMatchesTheSharedWireContract()
    {
        var snapshot = new NetworkInterfaceSnapshot("Tailscale", true, false, ["100.100.10.20"]);
        using var json = JsonDocument.Parse(JsonSerializer.Serialize(snapshot));
        Assert.Equal("Tailscale", json.RootElement.GetProperty("name").GetString());
        Assert.True(json.RootElement.GetProperty("isUp").GetBoolean());
        Assert.False(json.RootElement.GetProperty("isLoopback").GetBoolean());
        Assert.Equal("100.100.10.20", json.RootElement.GetProperty("addresses")[0].GetString());
        Assert.True(JsonSerializer.Deserialize<TailscaleNetwork>("""{"detected":true}""")!.Detected);
    }
}
