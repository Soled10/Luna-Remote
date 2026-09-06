using Nefarius.ViGEm.Client;
using Nefarius.ViGEm.Client.Targets;
using Nefarius.ViGEm.Client.Targets.Xbox360;

internal sealed class VirtualGamepad : IDisposable
{
    private ViGEmClient? client;
    private IXbox360Controller? pad;
    public bool Available => pad != null;
    public string Status { get; private set; } = "Controle virtual indisponível";
    public VirtualGamepad()
    {
        try
        {
            client = new ViGEmClient();
            pad = client.CreateXbox360Controller();
            pad.AutoSubmitReport = false;
            pad.Connect();
            Reset();
            Status = "Xbox 360 virtual pronto";
        }
        catch (Exception e)
        {
            pad = null;
            client?.Dispose();
            client = null;
            Status = "ViGEmBus indisponível: " + e.GetType().Name;
        }
    }
    public void Apply(GamepadState state)
    {
        if (pad == null) return;
        pad.SetButtonsFull(state.Buttons);
        pad.SetAxisValue(Xbox360Axis.LeftThumbX, state.LX);
        pad.SetAxisValue(Xbox360Axis.LeftThumbY, state.LY);
        pad.SetAxisValue(Xbox360Axis.RightThumbX, state.RX);
        pad.SetAxisValue(Xbox360Axis.RightThumbY, state.RY);
        pad.SetSliderValue(Xbox360Slider.LeftTrigger, state.LT);
        pad.SetSliderValue(Xbox360Slider.RightTrigger, state.RT);
        pad.SubmitReport();
    }
    public void Reset() => Apply(new GamepadState(0, 0, 0, 0, 0, 0, 0));
    public void Dispose()
    {
        try { if (pad != null) { Reset(); pad.Disconnect(); } }
        finally { client?.Dispose(); client = null; pad = null; }
    }
}
