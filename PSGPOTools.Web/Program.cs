using PSGPOTools.Web.Components;
using PSGPOTools.Web.Configuration;
using PSGPOTools.Web.Services;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();
builder.Services.Configure<SambaAdOptions>(
    builder.Configuration.GetSection(SambaAdOptions.SectionName));
builder.Services.AddSingleton<PowerShellGpoService>();
builder.Services.AddSingleton<SambaAdGpoService>();

var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
}

app.UseStaticFiles();
app.UseAntiforgery();

app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.Run();
