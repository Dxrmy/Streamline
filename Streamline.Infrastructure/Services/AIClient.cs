using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Streamline.Core.Interfaces;

namespace Streamline.Infrastructure.Services
{
    public class AIClient : IAIClient
    {
        private readonly HttpClient _httpClient;
        private readonly ILogger<AIClient> _logger;
        private readonly string _apiKey;
        private readonly string _analyzerModel;
        private readonly string _plannerModel;

        public AIClient(HttpClient httpClient, IConfiguration config, ILogger<AIClient> logger)
        {
            _httpClient = httpClient;
            _logger = logger;
            _apiKey = config["AI:ApiKey"];
            _analyzerModel = config["AI:AnalyzerModel"] ?? "gemini-2.0-flash-lite";
            _plannerModel = config["AI:PlannerModel"] ?? "gemini-2.0-flash-lite";
        }

        public async Task<string> AnalyzeAsync(string prompt, List<string> filePaths)
        {
            return await GenerateContentAsync(_analyzerModel, prompt, filePaths);
        }

        public async Task<string> PlanAsync(string prompt, List<string> filePaths)
        {
            return await GenerateContentAsync(_plannerModel, prompt, filePaths);
        }

        private async Task<string> GenerateContentAsync(string model, string prompt, List<string> filePaths)
        {
            var url = $"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={_apiKey}";

            var parts = new JArray();
            parts.Add(new JObject { ["text"] = prompt });

            foreach (var item in filePaths)
            {
                // Check if it's a valid file path AND the file exists
                bool isFile = false;
                try 
                {
                    if (item.Length < 255 && System.IO.File.Exists(item)) isFile = true;
                }
                catch { } // Not a file path

                if (isFile)
                {
                    var content = await System.IO.File.ReadAllTextAsync(item);
                    parts.Add(new JObject { ["text"] = $"\n--- FILE: {System.IO.Path.GetFileName(item)} ---\n{content}" });
                }
                else
                {
                    // Treat as raw context string
                    parts.Add(new JObject { ["text"] = $"\n--- CONTEXT ---\n{item}" });
                }
            }

            var payload = new JObject
            {
                ["contents"] = new JArray
                {
                    new JObject { ["parts"] = parts }
                }
            };

            var json = payload.ToString();
            var contentHttp = new StringContent(json, Encoding.UTF8, "application/json");

            try
            {
                var response = await _httpClient.PostAsync(url, contentHttp);
                response.EnsureSuccessStatusCode();

                var responseJson = await response.Content.ReadAsStringAsync();
                var resultObj = JObject.Parse(responseJson);

                return resultObj["candidates"]?[0]?["content"]?["parts"]?[0]?["text"]?.ToString() ?? "No content generated.";
            }
            catch (Exception ex)
            {
                _logger.LogError($"AI Generation Error: {ex.Message}");
                return $"Error generating content: {ex.Message}";
            }
        }
    }
}
