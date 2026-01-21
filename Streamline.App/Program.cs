using System;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.EntityFrameworkCore;
using Serilog;
using Streamline.Infrastructure.Database;
using Streamline.Infrastructure.Services;
using Streamline.Infrastructure.Security;
using Streamline.Core.Interfaces;
using Streamline.Core.Services;
using Streamline.App.Services;
using Spectre.Console;

namespace Streamline.App
{
    public class Program
    {
        public static async Task Main(string[] args)
        {
            // Spectre Console Header
            AnsiConsole.Write(
                new FigletText("Streamline")
                    .LeftJustified()
                    .Color(Color.Cyan1));

            Log.Logger = new LoggerConfiguration()
                .MinimumLevel.Information()
                .WriteTo.Console()
                .WriteTo.File("logs/streamline.log", rollingInterval: RollingInterval.Day)
                .CreateLogger();

            try
            {
                // Init Security for Config Menu (Standalone usage)
                var security = new SecurityService("Streamline_Master_Key_Hostname_" + Environment.MachineName);

                // Argument Check
                if (args.Length > 0 && args[0] == "config")
                {
                    new Configuration.ConfigMenu(security).Show();
                    return;
                }

                // Interactive Mode Check (if no args)
                if (args.Length == 0)
                {
                    var choice = AnsiConsole.Prompt(
                        new SelectionPrompt<string>()
                            .Title("Welcome to Streamline. What would you like to do?")
                            .AddChoices(new[] { "Run Bot Service", "Configuration", "Exit" }));

                    if (choice == "Configuration")
                    {
                        new Configuration.ConfigMenu(security).Show();
                        // Ask if they want to run after config
                        if (!AnsiConsole.Confirm("Do you want to start the bot now?"))
                            return;
                    }
                    else if (choice == "Exit")
                    {
                        return;
                    }
                }

                Log.Information("Starting Streamline Host...");
                var host = CreateHostBuilder(args).Build();

                // Ensure DB is created
                using (var scope = host.Services.CreateScope())
                {
                    var db = scope.ServiceProvider.GetRequiredService<StreamlineDbContext>();
                    db.Database.EnsureCreated();
                }

                await host.RunAsync();
            }
            catch (Exception ex)
            {
                Log.Fatal(ex, "Host terminated unexpectedly");
            }
            finally
            {
                Log.CloseAndFlush();
            }
        }

        public static IHostBuilder CreateHostBuilder(string[] args) =>
            Host.CreateDefaultBuilder(args)
                .UseSerilog() // Use Serilog for all logging
                .ConfigureServices((hostContext, services) =>
                {
                    services.AddDbContext<StreamlineDbContext>();
                    
                    // Core Services
                    services.AddSingleton<IPortalClient, PortalClient>();
                    services.AddHttpClient<IAIClient, AIClient>();
                    // Infrastructure Services
                    services.AddSingleton<IBeautifierService, BeautifierService>();
                    // Core Business Logic
                    services.AddSingleton<IPlanService, PlanService>();
                    
                    services.AddSingleton<ISecurityService>(sp => 
                    {
                        // Ensure we have a master key. In production, get from ENV.
                        return new SecurityService("Streamline_Master_Key_Hostname_" + Environment.MachineName);
                    });
                    
                    // Hosted Services (Background Workers)
                    services.AddHostedService<TelegramBotService>();
                });
    }
}
