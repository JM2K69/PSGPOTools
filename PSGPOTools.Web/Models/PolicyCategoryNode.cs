namespace PSGPOTools.Web.Models;

public sealed record PolicyCategoryNode(
    string Name,
    string Path,
    int PolicyCount,
    IReadOnlyList<PolicyCategoryNode> Children,
    IReadOnlyList<GpoPolicyInfo> Policies,
    PolicyCategoryNodeKind Kind = PolicyCategoryNodeKind.AdministrativeTemplate,
    bool IsInitiallyExpanded = false);

public enum PolicyCategoryNodeKind
{
    Structural,
    AdministrativeTemplate,
    AllSettings
}

public static class OfficialPolicyTreeBuilder
{
    public static IReadOnlyList<PolicyCategoryNode> Build(IEnumerable<GpoPolicyInfo> policies, string scope)
    {
        var scopedPolicies = policies.ToList();
        var administrativeTemplateCategories = PolicyCategoryTreeBuilder.Build(scopedPolicies, scope);
        var administrativeTemplates = Node(
            "Modèles d’administration",
            $"{scope}\\Policies\\Administrative Templates",
            administrativeTemplateCategories.Append(new PolicyCategoryNode(
                "Tous les paramètres",
                $"{scope}\\Policies\\Administrative Templates\\All Settings",
                scopedPolicies.Count,
                [],
                scopedPolicies.OrderBy(policy => policy.DisplayName, StringComparer.CurrentCultureIgnoreCase).ToList(),
                PolicyCategoryNodeKind.AllSettings)),
            isInitiallyExpanded: true);

        var windowsSettings = string.Equals(scope, "Machine", StringComparison.OrdinalIgnoreCase)
            ? new[]
            {
                Leaf("Stratégie de résolution de noms", scope, "Windows Settings"),
                Leaf("Scripts (Démarrage/Arrêt)", scope, "Windows Settings"),
                Leaf("Paramètres de sécurité", scope, "Windows Settings"),
                Leaf("QoS basée sur une stratégie", scope, "Windows Settings")
            }
            : new[]
            {
                Leaf("Scripts (Ouverture/Fermeture de session)", scope, "Windows Settings"),
                Leaf("Paramètres de sécurité", scope, "Windows Settings"),
                Leaf("Redirection de dossiers", scope, "Windows Settings"),
                Leaf("QoS basée sur une stratégie", scope, "Windows Settings")
            };

        var policiesNode = Node(
            "Stratégies",
            $"{scope}\\Policies",
            [
                Node("Paramètres du logiciel", $"{scope}\\Policies\\Software Settings", [
                    Leaf("Installation de logiciel", scope, "Software Settings")
                ]),
                Node("Paramètres Windows", $"{scope}\\Policies\\Windows Settings", windowsSettings),
                administrativeTemplates
            ],
            isInitiallyExpanded: true);

        return
        [
            policiesNode,
            Node("Préférences", $"{scope}\\Preferences", [])
        ];
    }

    private static PolicyCategoryNode Leaf(string name, string scope, string parent)
    {
        return Node(name, $"{scope}\\Policies\\{parent}\\{name}", []);
    }

    private static PolicyCategoryNode Node(
        string name,
        string path,
        IEnumerable<PolicyCategoryNode> children,
        bool isInitiallyExpanded = false)
    {
        var childList = children.ToList();
        return new PolicyCategoryNode(
            name,
            path,
            childList.Sum(child => child.PolicyCount),
            childList,
            [],
            PolicyCategoryNodeKind.Structural,
            isInitiallyExpanded);
    }
}

public static class PolicyCategoryTreeBuilder
{
    public static IReadOnlyList<PolicyCategoryNode> Build(IEnumerable<GpoPolicyInfo> policies, string scope)
    {
        var roots = new Dictionary<string, CategoryBuilder>(StringComparer.CurrentCultureIgnoreCase);

        foreach (var policy in policies)
        {
            var segments = policy.Path
                .Split(['\\', '/'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .ToArray();

            if (segments.Length > 0 && string.Equals(segments[0], scope, StringComparison.OrdinalIgnoreCase))
            {
                segments = segments[1..];
            }

            if (segments.Length == 0)
            {
                segments = ["Non classées"];
            }

            var categories = roots;
            var pathSegments = new List<string> { scope };
            CategoryBuilder? current = null;

            foreach (var segment in segments)
            {
                pathSegments.Add(segment);
                if (!categories.TryGetValue(segment, out current))
                {
                    current = new CategoryBuilder(segment, string.Join('\\', pathSegments));
                    categories.Add(segment, current);
                }

                categories = current.Children;
            }

            current!.Policies.Add(policy);
        }

        return roots.Values
            .OrderBy(category => category.Name, StringComparer.CurrentCultureIgnoreCase)
            .Select(category => category.Build())
            .ToList();
    }

    private sealed class CategoryBuilder(string name, string path)
    {
        public string Name { get; } = name;

        public string Path { get; } = path;

        public Dictionary<string, CategoryBuilder> Children { get; } =
            new(StringComparer.CurrentCultureIgnoreCase);

        public List<GpoPolicyInfo> Policies { get; } = [];

        public PolicyCategoryNode Build()
        {
            var children = Children.Values
                .OrderBy(category => category.Name, StringComparer.CurrentCultureIgnoreCase)
                .Select(category => category.Build())
                .ToList();
            var policies = Policies
                .OrderBy(policy => policy.DisplayName, StringComparer.CurrentCultureIgnoreCase)
                .ToList();

            return new PolicyCategoryNode(
                Name,
                Path,
                policies.Count + children.Sum(child => child.PolicyCount),
                children,
                policies);
        }
    }
}
