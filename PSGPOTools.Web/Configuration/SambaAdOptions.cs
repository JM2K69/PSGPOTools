namespace PSGPOTools.Web.Configuration;

public sealed class SambaAdOptions
{
    public const string SectionName = "SambaAd";

    public string Server { get; set; } = string.Empty;

    public int Port { get; set; } = 636;

    public string? BaseDn { get; set; }
}
