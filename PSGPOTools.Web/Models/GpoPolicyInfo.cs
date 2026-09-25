namespace PSGPOTools.Web.Models;

public sealed record GpoPolicyInfo(
    string Id,
    string Name,
    string DisplayName,
    string Description,
    string Scope,
    string Path,
    string FileName,
    GpoRegistryInfo Registry);
