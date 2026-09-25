namespace PSGPOTools.Web.Models;

public sealed record DomainGpoInfo(
    Guid Id,
    string DisplayName,
    string DistinguishedName,
    string FileSystemPath,
    int VersionNumber,
    int Flags,
    bool ComputerEnabled,
    bool UserEnabled,
    DateTimeOffset? CreatedAt,
    DateTimeOffset? ModifiedAt);
