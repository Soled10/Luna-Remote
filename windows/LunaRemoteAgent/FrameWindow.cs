using System.Buffers.Binary;
using System.Diagnostics;

// At most two pictures may be in transit/decoding. Never accumulate a video backlog.
internal sealed class FrameWindow : IDisposable
{
    private readonly SemaphoreSlim slots = new(2, 2);
    private readonly Dictionary<int, long> pending = new();
    private readonly object gate = new();
    private int next;
    private double latency = 50;
    public double LatencyMs { get { lock (gate) return latency; } }
    public async Task<int> Reserve(CancellationToken ct)
    {
        if (!await slots.WaitAsync(TimeSpan.FromSeconds(8), ct)) throw new TimeoutException("Video acknowledgement timed out.");
        lock (gate) { int id = ++next; pending.Add(id, Stopwatch.GetTimestamp()); return id; }
    }
    public void Acknowledge(int id)
    {
        lock (gate)
        {
            if (!pending.Remove(id, out long sent)) return;
            latency = latency * 0.8 + Stopwatch.GetElapsedTime(sent).TotalMilliseconds * 0.2;
            slots.Release();
        }
    }
    public static byte[] Packet(int id, byte[] jpeg)
    {
        var packet = new byte[jpeg.Length + 8];
        "LR03"u8.CopyTo(packet);
        BinaryPrimitives.WriteInt32LittleEndian(packet.AsSpan(4), id);
        jpeg.CopyTo(packet, 8);
        return packet;
    }
    public void Dispose() => slots.Dispose();
}
