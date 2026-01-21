using System;
using System.IO;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Spectre.Console;
using Streamline.Infrastructure.Security;

namespace Streamline.App.Configuration
{
    public class ConfigMenu
    {
        private readonly SecurityService _security;
        private readonly string _settingsPath;

        public ConfigMenu(SecurityService security)
        {
            _security = security;
            _settingsPath = Path.Combine(AppContext.BaseDirectory, "appsettings.json");
        }

        public void Show()
        {
            while (true)
            {
                AnsiConsole.Clear();
                AnsiConsole.Write(new FigletText("Settings").LeftJustified().Color(Color.Cyan1));

                var currentConfig = LoadConfig();
                
                var botToken = currentConfig["Bot"]?["Token"]?.ToString() ?? "";
                var geminiKey = currentConfig["AI"]?["ApiKey"]?.ToString() ?? "";
                var portalUser = currentConfig["Portal"]?["Username"]?.ToString() ?? "";

                var table = new Table();
                table.AddColumn("Setting");
                table.AddColumn("Status");
                
                table.AddRow("Telegram Bot Token", string.IsNullOrEmpty(botToken) || botToken.Contains("YOUR") ? "[red]Missing[/]" : "[green]Set[/]");
                table.AddRow("Gemini API Key", string.IsNullOrEmpty(geminiKey) || geminiKey.Contains("YOUR") ? "[red]Missing[/]" : "[green]Set[/]");
                table.AddRow("Portal Username", string.IsNullOrEmpty(portalUser) ? "[red]Missing[/]" : $"[green]{portalUser}[/]");
                table.AddRow("Portal Password", "[grey]Encrypted[/]");

                AnsiConsole.Write(table);

                var choice = AnsiConsole.Prompt(
                    new SelectionPrompt<string>()
                        .Title("Select an option:")
                        .AddChoices(new[] {
                            "Setup Telegram Bot",
                            "Setup Gemini AI",
                            "Setup Portal Credentials",
                            "Export Config",
                            "Import Config",
                            "Save & Return to Main Menu"
                        }));

                if (choice == "Save & Return to Main Menu") break;

                switch (choice)
                {
                    case "Setup Telegram Bot":
                        var token = AnsiConsole.Ask<string>("Enter [green]Telegram Bot Token[/]:");
                        UpdateSetting("Bot", "Token", token);
                        break;
                    case "Setup Gemini AI":
                        var key = AnsiConsole.Ask<string>("Enter [green]Gemini API Key[/]:");
                        UpdateSetting("AI", "ApiKey", key);
                        break;
                    case "Setup Portal Credentials":
                        var user = AnsiConsole.Ask<string>("Enter [green]Portal Username[/]:");
                        var pass = AnsiConsole.Prompt(
                            new TextPrompt<string>("Enter [green]Portal Password[/]:")
                                .Secret());
                        
                        UpdateSetting("Portal", "Username", user);
                        // Save to "Password" key as encrypted string (PortalClient now handles decryption)
                        UpdateSetting("Portal", "Password", _security.Encrypt(pass));
                        AnsiConsole.MarkupLine("[green]Password encrypted and saved![/]");
                        System.Threading.Thread.Sleep(1000);
                        break;
                    case "Export Config":
                        var exportPath = AnsiConsole.Ask<string>("Enter export path (e.g. ./config.json):");
                        try 
                        {
                            File.Copy(_settingsPath, exportPath, true);
                            AnsiConsole.MarkupLine($"[green]Config exported to {exportPath}[/]");
                        }
                        catch (Exception ex)
                        {
                            AnsiConsole.MarkupLine($"[red]Export failed: {ex.Message}[/]");
                        }
                        AnsiConsole.Ask<string>("Press Enter to continue...");
                        break;
                    case "Import Config":
                         var importPath = AnsiConsole.Ask<string>("Enter import path (e.g. ./config.json):");
                         if (File.Exists(importPath))
                         {
                             try 
                             {
                                 var json = File.ReadAllText(importPath);
                                 // Basic validation
                                 JObject.Parse(json); 
                                 File.WriteAllText(_settingsPath, json);
                                 AnsiConsole.MarkupLine("[green]Config imported successfully![/]");
                             }
                             catch (Exception ex)
                             {
                                 AnsiConsole.MarkupLine($"[red]Import failed: {ex.Message}[/]");
                             }
                         }
                         else
                         {
                             AnsiConsole.MarkupLine("[red]File not found.[/]");
                         }
                         AnsiConsole.Ask<string>("Press Enter to continue...");
                         break;
                }
            }
        }

        private JObject LoadConfig()
        {
            if (!File.Exists(_settingsPath)) return new JObject();
            return JObject.Parse(File.ReadAllText(_settingsPath));
        }

        private void UpdateSetting(string section, string key, string value)
        {
            var json = LoadConfig();
            if (json[section] == null) json[section] = new JObject();
            json[section]![key] = value;
            File.WriteAllText(_settingsPath, json.ToString(Formatting.Indented));
        }
    }
}
