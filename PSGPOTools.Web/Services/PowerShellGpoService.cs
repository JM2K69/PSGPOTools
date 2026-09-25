using System.Collections;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using PSGPOTools.Web.Models;

namespace PSGPOTools.Web.Services;

public sealed class PowerShellGpoService : IDisposable
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly string _moduleManifestPath;
    private Runspace? _runspace;
    private bool _moduleImported;
    private IReadOnlyList<GpoPolicyInfo> _policies = [];

    public PowerShellGpoService(IWebHostEnvironment environment)
    {
        _moduleManifestPath = Path.GetFullPath(Path.Combine(
            environment.ContentRootPath,
            "..",
            "PSGPOTools",
            "PSGPOTools.psd1"));
    }

    public bool IsInitialized { get; private set; }

    public string? LoadedPath { get; private set; }

    public string? LoadedCulture { get; private set; }

    public IReadOnlyList<GpoPolicyInfo> Policies => _policies;

    public string DefaultPolicyDefinitionsPath =>
        OperatingSystem.IsWindows()
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "PolicyDefinitions")
            : string.Empty;

    public Task<IReadOnlyList<GpoPolicyInfo>> InitializeAsync(string policyDefinitionsPath, string cultureName, CancellationToken cancellationToken = default)
    {
        return Task.Run(async () =>
        {
            await _gate.WaitAsync(cancellationToken);
            try
            {
                EnsureRunspace();
                ImportModuleIfNeeded();

                var normalizedCulture = string.IsNullOrWhiteSpace(cultureName)
                    ? CultureInfo.CurrentUICulture.Name
                    : cultureName.Trim();

                using var initialize = CreatePowerShell();
                initialize
                    .AddCommand("Initialize-PSGPOAdmx")
                    .AddParameter("Path", policyDefinitionsPath)
                    .AddParameter("UICulture", CultureInfo.GetCultureInfo(normalizedCulture));
                InvokeOrThrow(initialize);

                _policies = LoadPolicies();
                LoadedPath = policyDefinitionsPath;
                LoadedCulture = normalizedCulture;
                IsInitialized = true;

                return _policies;
            }
            finally
            {
                _gate.Release();
            }
        }, cancellationToken);
    }

    private IReadOnlyList<GpoPolicyInfo> LoadPolicies()
    {
        return LoadPolicies("Machine")
            .Concat(LoadPolicies("User"))
            .OrderBy(policy => policy.Path)
            .ThenBy(policy => policy.DisplayName)
            .ToList();
    }

    private IEnumerable<GpoPolicyInfo> LoadPolicies(string scope)
    {
        using var command = CreatePowerShell();
        command.AddCommand("Get-PSGPOPolicy").AddParameter("Scope", scope);
        return InvokeOrThrow(command).Select(MapPolicy);
    }

    private void EnsureRunspace()
    {
        if (_runspace is not null)
        {
            return;
        }

        _runspace = RunspaceFactory.CreateRunspace();
        _runspace.Open();
    }

    private void ImportModuleIfNeeded()
    {
        if (_moduleImported)
        {
            return;
        }

        if (!File.Exists(_moduleManifestPath))
        {
            throw new FileNotFoundException("Le manifeste du module PSGPOTools est introuvable.", _moduleManifestPath);
        }

        using var import = CreatePowerShell();
        import.AddCommand("Import-Module").AddParameter("Name", _moduleManifestPath).AddParameter("Force");
        InvokeOrThrow(import);
        _moduleImported = true;
    }

    private PowerShell CreatePowerShell()
    {
        EnsureRunspace();
        var powerShell = PowerShell.Create();
        powerShell.Runspace = _runspace;
        return powerShell;
    }

    private static ICollection<PSObject> InvokeOrThrow(PowerShell powerShell)
    {
        var results = powerShell.Invoke();

        if (powerShell.HadErrors)
        {
            var errors = powerShell.Streams.Error.Select(error => error.ToString());
            throw new InvalidOperationException(string.Join(Environment.NewLine, errors));
        }

        return results;
    }

    private static GpoPolicyInfo MapPolicy(PSObject policy)
    {
        var registry = policy.Properties["Registry"]?.Value;

        return new GpoPolicyInfo(
            GetString(policy, "ID"),
            GetString(policy, "Name"),
            GetString(policy, "DisplayName"),
            GetString(policy, "Description"),
            GetString(policy, "Scope"),
            GetString(policy, "Path"),
            GetString(policy, "FileName"),
            new GpoRegistryInfo(
                GetObjectPropertyString(registry, "Path"),
                GetObjectPropertyString(registry, "Key"),
                GetRegistryValues(registry)));
    }

    private static string GetString(PSObject value, string propertyName)
    {
        return value.Properties[propertyName]?.Value?.ToString() ?? string.Empty;
    }

    private static string GetObjectPropertyString(object? value, string propertyName)
    {
        if (value is null)
        {
            return string.Empty;
        }

        return PSObject.AsPSObject(value).Properties[propertyName]?.Value?.ToString() ?? string.Empty;
    }

    private static IReadOnlyDictionary<string, string> GetRegistryValues(object? registry)
    {
        if (registry is null)
        {
            return new Dictionary<string, string>();
        }

        var value = PSObject.AsPSObject(registry).Properties["Value"]?.Value;
        if (value is not IDictionary dictionary)
        {
            return new Dictionary<string, string>();
        }

        return dictionary.Keys
            .Cast<object>()
            .ToDictionary(
                key => key.ToString() ?? string.Empty,
                key => dictionary[key]?.ToString() ?? string.Empty);
    }

    public void Dispose()
    {
        _runspace?.Dispose();
        _gate.Dispose();
    }
}
