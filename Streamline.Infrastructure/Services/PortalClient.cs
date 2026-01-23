using System;
using System.Threading.Tasks;
using Microsoft.Playwright;
using Microsoft.Extensions.Logging;
using Streamline.Core.Interfaces;
using Streamline.Core.Entities;
using System.Collections.Generic;

namespace Streamline.Infrastructure.Services
{
    public class PortalClient : IPortalClient
    {
        private readonly ILogger<PortalClient> _logger;
        private IPlaywright _playwright;
        private IBrowser _browser;
        private IPage _page;

        private readonly Microsoft.Extensions.Configuration.IConfiguration _config;
        private readonly ISecurityService _security;
        private string _baseUrl = "https://swimlessons.app"; // Default, override from config

        public PortalClient(ILogger<PortalClient> logger, Microsoft.Extensions.Configuration.IConfiguration config, ISecurityService security)
        {
            _logger = logger;
            _config = config;
            _security = security;
            var url = _config["Portal:Url"];
            if (!string.IsNullOrEmpty(url)) _baseUrl = url;
        }

        private async Task InitBrowserAsync()
        {
            if (_browser != null) return;

            _playwright = await Playwright.CreateAsync();
            _logger.LogInformation($"Launching Chromium (Headless: {_config["Playwright:Headless"] != "false"})...");
            
            _browser = await _playwright.Chromium.LaunchAsync(new BrowserTypeLaunchOptions
            {
                Headless = _config["Playwright:Headless"] != "false", // Allow config override
                SlowMo = 1000, 
                Args = new[] { "--no-sandbox" }
            });
            _page = await _browser.NewPageAsync();
        }

        public async Task<bool> LoginAsync(string username, string password)
        {
            await InitBrowserAsync();
            _logger.LogInformation($"Navigating to {_baseUrl}...");
            
            await _page.GotoAsync($"{_baseUrl}/login"); 

            // Check if already logged in
            if (await _page.Locator("text=Sign Out").CountAsync() > 0) return true;

            await _page.FillAsync("input[type='email']", username); // Usually email for this portal
            await _page.FillAsync("input[type='password']", password);
            
            // Try different button selectors common in Vuetify apps
            try { await _page.ClickAsync("button:has-text('Login')"); }
            catch { await _page.ClickAsync("button[type='submit']"); }

            try {
                // Wait for dashboard or logout button
                await _page.WaitForLoadStateAsync(LoadState.NetworkIdle);
                return true;
            } catch {
                _logger.LogError("Login timeout or failure.");
                return false;
            }
        }

        private async Task EnsureLoggedInAsync()
        {
             await InitBrowserAsync();
             // Simple check: are we on a login page? or is the url empty?
             if (_page.Url == "about:blank" || _page.Url.Contains("/login"))
             {
                 var user = _config["Portal:Username"];
                 var rawPass = _config["Portal:Password"];
                 
                 // Fallback for legacy config key
                 if (string.IsNullOrEmpty(rawPass))
                 {
                     rawPass = _config["Portal:EncryptedPassword"];
                 }
                 
                 if (string.IsNullOrEmpty(user) || string.IsNullOrEmpty(rawPass))
                 {
                     throw new Exception("Portal credentials missing in Config!");
                 }

                 // Try decrypt, fallback to plain
                 string password = rawPass;
                 try 
                 {
                     password = _security.Decrypt(rawPass);
                 }
                 catch
                 {
                     // Assume it was plain text or decryption failed safely
                 }

                 await LoginAsync(user, password);
             }
        }

        public async Task<SessionBatch> ScrapeDayAsync(DateTime date)
        {
            await EnsureLoggedInAsync();
            
            var batch = new SessionBatch { RunDate = date, TeachingDay = date.DayOfWeek.ToString().ToLower() };

            _logger.LogInformation($"Scraping data for {date.ToShortDateString()}...");
            
            // Correct URL Construction
            var targetUrl = $"{_baseUrl.TrimEnd('/')}/calendar/day/{date:yyyy-MM-dd}";
            _logger.LogInformation($"Navigating to: {targetUrl}");
            
            await _page.GotoAsync(targetUrl);
            await _page.WaitForLoadStateAsync(LoadState.NetworkIdle);

            // Use Locators for stability and speed (lazy evaluation)
            var rowsLocator = _page.Locator("tr.clickable");
            var rowCount = await rowsLocator.CountAsync();
            _logger.LogInformation($"Found {rowCount} classes.");

            for (int i = 0; i < rowCount; i++)
            {
                var row = rowsLocator.Nth(i);

                var cells = row.Locator("td");
                if (await cells.CountAsync() < 2) continue;

                var time = await cells.Nth(0).InnerTextAsync();
                var name = await cells.Nth(1).InnerTextAsync();
                var className = $"{time.Trim()} {name.Trim()}";

                _logger.LogInformation($"Processing Class: {className}");

                var session = new ClassSession 
                { 
                    Name = className, 
                    Time = time.Trim(),
                    SessionBatchId = batch.Id,
                    SessionBatch = batch
                };

                // Click to enter class
                await row.ClickAsync();

                // Optimized Wait: Wait for specific element instead of generic NetworkIdle (which waits 500ms)
                try
                {
                    await _page.WaitForSelectorAsync("a[href*='/assess-by-member/']", new PageWaitForSelectorOptions { Timeout = 3000 });
                }
                catch
                {
                    // Fallback if no students
                    await _page.WaitForLoadStateAsync(LoadState.DOMContentLoaded);
                }

                // --- 1. Parse Register (Student Progress) ---
                var studentLinks = await _page.QuerySelectorAllAsync("a[href*='/assess-by-member/']");
                
                foreach (var link in studentLinks)
                {
                    var titleDiv = await link.QuerySelectorAsync("div.v-list-item__title");
                    if (titleDiv == null) continue;

                    var percentageSpan = await titleDiv.QuerySelectorAsync("span.percentage-complete");
                    var progress = percentageSpan != null ? await percentageSpan.InnerTextAsync() : "0%";
                    
                    var fullText = await titleDiv.InnerTextAsync();
                    var studentName = fullText.Replace(progress, "").Trim();
                    if (studentName.Contains("(")) 
                        studentName = studentName.Split('(')[0].Trim();

                    var student = new Student { Name = studentName };
                    var snapshot = new AttendanceSnapshot
                    {
                        Student = student,
                        ClassSession = session,
                        Progress = progress,
                        Status = "Present"
                    };
                    session.Snapshots.Add(snapshot);
                }

                // --- 2. Parse Skills (Click "Skills" tab) ---
                try 
                {
                    var tabs = await _page.GetByText("Skills").AllAsync();
                    if (tabs.Count > 0)
                    {
                        await tabs.First().ClickAsync();
                        // Optimized Wait: Wait for content to appear instead of hard sleep
                        try {
                            await _page.WaitForSelectorAsync("div.v-list-group", new PageWaitForSelectorOptions { Timeout = 2000 });
                        } catch {
                            // If no groups appear, maybe empty or animation finished differently
                        }

                        var skillGroups = await _page.QuerySelectorAllAsync("div.v-list-group");
                        foreach (var group in skillGroups)
                        {
                            var groupTitleElem = await group.QuerySelectorAsync("div.v-list-item__title");
                            if (groupTitleElem == null) continue;
                            var groupTitle = (await groupTitleElem.InnerTextAsync()).Trim();

                            var studentRows = await group.QuerySelectorAllAsync("div[role='listitem']");
                            foreach (var sRow in studentRows)
                            {
                                var sNameElem = await sRow.QuerySelectorAsync("a");
                                if (sNameElem == null) continue;
                                var sNameRaw = await sNameElem.InnerTextAsync();
                                var sName = sNameRaw.Split('(')[0].Trim();

                                var activeBtn = await sRow.QuerySelectorAsync("button.v-item--active");
                                var status = activeBtn != null ? await activeBtn.InnerTextAsync() : "Not Assessed";

                                var snapshot = session.Snapshots.FirstOrDefault(s => s.Student.Name == sName);
                                if (snapshot != null)
                                {
                                    snapshot.Notes += $"[{groupTitle}: {status}] ";
                                }
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning($"Failed to parse skills for {className}: {ex.Message}");
                }

                batch.Sessions.Add(session);

                // Navigate Back
                await _page.GoBackAsync();
                // Optimized Wait: Wait for list to be ready
                await rowsLocator.First.WaitForAsync();
            }
            
            return batch;
        }

        public async Task CloseAsync()
        {
            if (_browser != null)
            {
                await _browser.CloseAsync();
                await _browser.DisposeAsync();
                _browser = null;
            }
            if (_playwright != null)
            {
                _playwright.Dispose();
                _playwright = null;
            }
        }
    }
}
