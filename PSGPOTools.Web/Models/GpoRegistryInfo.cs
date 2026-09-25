namespace PSGPOTools.Web.Models;

public sealed record GpoRegistryInfo(
    string Path,
    string Key,
    IReadOnlyDictionary<string, string> Values);
