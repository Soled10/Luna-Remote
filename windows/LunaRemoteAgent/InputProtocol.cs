using System.Globalization;
using System.Text;
using System.Text.Json;

internal record InputCommand(string Type, string Text = "", bool Submit = false, string Id = "",
    int X = 0, int Y = 0, string Button = "", bool Down = false, GamepadState? Pad = null);
internal record GamepadState(ushort Buttons, short LX, short LY, short RX, short RY, byte LT, byte RT);

internal static class InputProtocol
{
    public static InputCommand Parse(string message)
    {
        // Compatibility with the previously shipped iOS client.
        if (!message.StartsWith('{'))
        {
            if (message.StartsWith("key:text:"))
                return new("text", Encoding.UTF8.GetString(Convert.FromBase64String(message[9..])));
            var parts = message.Split(':');
            if (parts.Length == 4 && parts[0] == "mouse" && parts[1] == "move")
                return new("move", X: Math.Clamp(int.Parse(parts[2], CultureInfo.InvariantCulture), -2048, 2048),
                    Y: Math.Clamp(int.Parse(parts[3], CultureInfo.InvariantCulture), -2048, 2048));
            return message switch {
                "mouse:left" => new("click", Button: "left"),
                "mouse:right" => new("click", Button: "right"),
                "mouse:double" => new("click", Button: "double"),
                _ => throw new FormatException("Unknown command")
            };
        }
        using var doc = JsonDocument.Parse(message);
        var r = doc.RootElement;
        var type = r.GetProperty("type").GetString() ?? "";
        string Str(string key) => r.TryGetProperty(key, out var p) ? p.GetString() ?? "" : "";
        int Int(string key, int low, int high) => r.TryGetProperty(key, out var p)
            ? Math.Clamp(p.GetInt32(), low, high) : 0;
        bool Bool(string key) => r.TryGetProperty(key, out var p) && p.GetBoolean();
        switch (type)
        {
            case "text":
                var text = Str("text");
                if (text.Length > 4096) throw new FormatException("Text too long");
                return new(type, text, Bool("submit"), Str("id"));
            case "key":
                var key = Str("button");
                if (key is not ("enter" or "escape" or "backspace" or "tab")) throw new FormatException("Unknown key");
                return new(type, Button: key);
            case "move": return new(type, X: Int("x", -2048, 2048), Y: Int("y", -2048, 2048));
            case "scroll": return new(type, Y: Int("y", -1200, 1200));
            case "click":
            case "button":
                var button = Str("button");
                if (button is not ("left" or "right" or "double")) throw new FormatException("Unknown button");
                return new(type, Button: button, Down: Bool("down"));
            case "gamepad": return new(type, Pad: new(
                (ushort)Int("buttons", 0, 65535), (short)Int("lx", -32768, 32767),
                (short)Int("ly", -32768, 32767), (short)Int("rx", -32768, 32767),
                (short)Int("ry", -32768, 32767), (byte)Int("lt", 0, 255), (byte)Int("rt", 0, 255)));
            case "release": return new(type);
            case "frameAck": return new(type, X: Int("x", 1, int.MaxValue));
            case "ping": return new(type, Id: Str("id"));
            default: throw new FormatException("Unknown command");
        }
    }
}
