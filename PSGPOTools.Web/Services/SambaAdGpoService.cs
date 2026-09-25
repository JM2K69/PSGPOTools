using System.DirectoryServices.Protocols;
using System.Globalization;
using System.Net;
using Microsoft.Extensions.Options;
using PSGPOTools.Web.Configuration;
using PSGPOTools.Web.Models;

namespace PSGPOTools.Web.Services;

public sealed class SambaAdGpoService(IOptions<SambaAdOptions> options)
{
    private const int PageSize = 500;
    private readonly SambaAdOptions _options = options.Value;

    public bool IsConfigured => !string.IsNullOrWhiteSpace(_options.Server);

    public string Server => _options.Server;

    public Task<IReadOnlyList<DomainGpoInfo>> GetGroupPoliciesAsync(CancellationToken cancellationToken = default)
    {
        if (!IsConfigured)
        {
            throw new InvalidOperationException(
                $"Configurez '{SambaAdOptions.SectionName}:Server' dans appsettings.json avant de charger les GPO du domaine.");
        }

        return Task.Run(() => GetGroupPolicies(cancellationToken), cancellationToken);
    }

    private IReadOnlyList<DomainGpoInfo> GetGroupPolicies(CancellationToken cancellationToken)
    {
        using var connection = CreateConnection();
        connection.Bind();

        var baseDn = string.IsNullOrWhiteSpace(_options.BaseDn)
            ? GetDefaultNamingContext(connection)
            : _options.BaseDn.Trim();
        var policiesDn = $"CN=Policies,CN=System,{baseDn}";
        var policies = new List<DomainGpoInfo>();
        var pageControl = new PageResultRequestControl(PageSize);

        do
        {
            cancellationToken.ThrowIfCancellationRequested();

            var request = new SearchRequest(
                policiesDn,
                "(objectClass=groupPolicyContainer)",
                SearchScope.OneLevel,
                "objectGUID",
                "name",
                "displayName",
                "distinguishedName",
                "gPCFileSysPath",
                "versionNumber",
                "flags",
                "whenCreated",
                "whenChanged");
            request.Controls.Add(pageControl);

            var response = (SearchResponse)connection.SendRequest(request);
            policies.AddRange(response.Entries.Cast<SearchResultEntry>().Select(MapGroupPolicy));

            pageControl.Cookie = response.Controls
                .OfType<PageResultResponseControl>()
                .FirstOrDefault()?.Cookie ?? [];
        }
        while (pageControl.Cookie.Length > 0);

        return policies
            .OrderBy(policy => policy.DisplayName, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
    }

    private LdapConnection CreateConnection()
    {
        var identifier = new LdapDirectoryIdentifier(_options.Server.Trim(), _options.Port, false, false);
        var connection = new LdapConnection(identifier, CredentialCache.DefaultNetworkCredentials, AuthType.Negotiate)
        {
            Timeout = TimeSpan.FromSeconds(30)
        };
        connection.SessionOptions.ProtocolVersion = 3;
        connection.SessionOptions.SecureSocketLayer = true;
        return connection;
    }

    private static string GetDefaultNamingContext(LdapConnection connection)
    {
        var request = new SearchRequest(
            string.Empty,
            "(objectClass=*)",
            SearchScope.Base,
            "defaultNamingContext");
        var response = (SearchResponse)connection.SendRequest(request);
        var baseDn = response.Entries.Count == 0
            ? null
            : GetString(response.Entries[0], "defaultNamingContext");

        if (string.IsNullOrWhiteSpace(baseDn))
        {
            throw new InvalidOperationException("Le serveur LDAP n'a pas retourné de contexte de nommage par défaut.");
        }

        return baseDn;
    }

    private static DomainGpoInfo MapGroupPolicy(SearchResultEntry entry)
    {
        var flags = GetInt32(entry, "flags");

        return new DomainGpoInfo(
            GetGuid(entry),
            GetString(entry, "displayName") ?? GetString(entry, "name") ?? "GPO sans nom",
            GetString(entry, "distinguishedName") ?? entry.DistinguishedName,
            GetString(entry, "gPCFileSysPath") ?? string.Empty,
            GetInt32(entry, "versionNumber"),
            flags,
            ComputerEnabled: (flags & 2) == 0,
            UserEnabled: (flags & 1) == 0,
            ParseGeneralizedTime(GetString(entry, "whenCreated")),
            ParseGeneralizedTime(GetString(entry, "whenChanged")));
    }

    private static Guid GetGuid(SearchResultEntry entry)
    {
        if (entry.Attributes["objectGUID"]?[0] is byte[] bytes && bytes.Length == 16)
        {
            return new Guid(bytes);
        }

        var name = GetString(entry, "name")?.Trim('{', '}');
        return Guid.TryParse(name, out var id) ? id : Guid.Empty;
    }

    private static int GetInt32(SearchResultEntry entry, string attributeName)
    {
        return int.TryParse(GetString(entry, attributeName), NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
            ? value
            : 0;
    }

    private static string? GetString(SearchResultEntry entry, string attributeName)
    {
        var attribute = entry.Attributes[attributeName];
        if (attribute is null || attribute.Count == 0)
        {
            return null;
        }

        return attribute[0] switch
        {
            byte[] bytes => System.Text.Encoding.UTF8.GetString(bytes),
            var value => Convert.ToString(value, CultureInfo.InvariantCulture)
        };
    }

    private static DateTimeOffset? ParseGeneralizedTime(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        string[] formats =
        [
            "yyyyMMddHHmmss'Z'",
            "yyyyMMddHHmmss.f'Z'",
            "yyyyMMddHHmmss.ff'Z'",
            "yyyyMMddHHmmss.fff'Z'",
            "yyyyMMddHHmmss.ffff'Z'",
            "yyyyMMddHHmmss.fffff'Z'",
            "yyyyMMddHHmmss.ffffff'Z'",
            "yyyyMMddHHmmss.fffffff'Z'"
        ];

        return DateTimeOffset.TryParseExact(
            value,
            formats,
            CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
            out var parsed)
            ? parsed
            : null;
    }
}
