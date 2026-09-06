using System.ComponentModel;
using System.Runtime.InteropServices;

internal static class WindowsInput
{
    [StructLayout(LayoutKind.Sequential)]
    internal struct Input { public uint Type; public Union Data; }
    [StructLayout(LayoutKind.Explicit)]
    internal struct Union { [FieldOffset(0)] public Mouse Mouse; [FieldOffset(0)] public Keyboard Key; }
    [StructLayout(LayoutKind.Sequential)]
    internal struct Mouse { public int X, Y; public uint Data, Flags, Time; public nuint Extra; }
    [StructLayout(LayoutKind.Sequential)]
    internal struct Keyboard { public ushort VK, Scan; public uint Flags, Time; public nuint Extra; }
    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint count, Input[] inputs, int size);

    internal static Input[] TextInputs(string text, bool submit)
    {
        var list = new List<Input>();
        foreach (var c in text)
        {
            list.Add(new Input { Type = 1, Data = new Union { Key = new Keyboard { Scan = c, Flags = 4 } } });
            list.Add(new Input { Type = 1, Data = new Union { Key = new Keyboard { Scan = c, Flags = 6 } } });
        }
        if (submit) list.AddRange(KeyInputs(0x0D));
        return list.ToArray();
    }

    private static Input[] KeyInputs(ushort key) => new[] {
        new Input { Type = 1, Data = new Union { Key = new Keyboard { VK = key } } },
        new Input { Type = 1, Data = new Union { Key = new Keyboard { VK = key, Flags = 2 } } }
    };

    private static void Send(Input[] inputs)
    {
        if (inputs.Length == 0) return;
        var sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>());
        if (sent != inputs.Length)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Windows recusou a entrada. Verifique se o destino está elevado ou bloqueado.");
    }
    private static Input MouseInput(int x, int y, uint flags, uint data = 0) =>
        new() { Data = new Union { Mouse = new Mouse { X = x, Y = y, Flags = flags, Data = data } } };

    public static void Apply(InputCommand command)
    {
        switch (command.Type)
        {
            case "text": Send(TextInputs(command.Text, command.Submit)); break;
            case "key":
                Send(KeyInputs(command.Button switch { "enter" => 0x0D, "tab" => 0x09, "backspace" => 0x08, _ => (ushort)0x1B }));
                break;
            case "move": Send(new[] { MouseInput(command.X, command.Y, 1) }); break;
            case "scroll": Send(new[] { MouseInput(0, 0, 0x800, unchecked((uint)command.Y)) }); break;
            case "button":
                Send(new[] { MouseInput(0, 0, command.Button == "right" ? (command.Down ? 8u : 16u) : (command.Down ? 2u : 4u)) });
                break;
            case "click":
                var down = command.Button == "right" ? 8u : 2u;
                var up = command.Button == "right" ? 16u : 4u;
                var pair = new[] { MouseInput(0, 0, down), MouseInput(0, 0, up) };
                Send(command.Button == "double" ? pair.Concat(pair).ToArray() : pair);
                break;
        }
    }
    public static void ReleaseMouse() => Send(new[] { MouseInput(0, 0, 4 | 16) });
}
