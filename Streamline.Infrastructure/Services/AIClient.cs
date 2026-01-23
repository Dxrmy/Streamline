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

            var contentHttp = new JsonStreamContent(prompt, filePaths);

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

        private class JsonStreamContent : HttpContent
        {
            private readonly string _prompt;
            private readonly List<string> _filePaths;

            public JsonStreamContent(string prompt, List<string> filePaths)
            {
                _prompt = prompt;
                _filePaths = filePaths;
                Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json")
                {
                    CharSet = "utf-8"
                };
            }

            protected override async Task SerializeToStreamAsync(System.IO.Stream stream, System.Net.TransportContext? context)
            {
                using var streamWriter = new System.IO.StreamWriter(stream, new UTF8Encoding(false), 1024, leaveOpen: true);
                using var writer = new JsonTextWriter(streamWriter) { Formatting = Formatting.None };

                await writer.WriteStartObjectAsync();
                await writer.WritePropertyNameAsync("contents");
                await writer.WriteStartArrayAsync();

                await writer.WriteStartObjectAsync();
                await writer.WritePropertyNameAsync("parts");
                await writer.WriteStartArrayAsync();

                // Prompt
                await writer.WriteStartObjectAsync();
                await writer.WritePropertyNameAsync("text");
                await writer.WriteValueAsync(_prompt);
                await writer.WriteEndObjectAsync();

                foreach (var item in _filePaths)
                {
                    bool isFile = false;
                    try
                    {
                        if (item.Length < 255 && System.IO.File.Exists(item)) isFile = true;
                    }
                    catch { }

                    await writer.WriteStartObjectAsync();
                    await writer.WritePropertyNameAsync("text");

                    if (isFile)
                    {
                        // Header part
                        await writer.WriteValueAsync($"\n--- FILE: {System.IO.Path.GetFileName(item)} ---\n");
                        await writer.WriteEndObjectAsync();

                        // Content part
                        var content = await System.IO.File.ReadAllTextAsync(item);
                        await writer.WriteStartObjectAsync();
                        await writer.WritePropertyNameAsync("text");
                        await writer.WriteValueAsync(content);
                    }
                    else
                    {
                        await writer.WriteValueAsync($"\n--- CONTEXT ---\n{item}");
                    }

                    await writer.WriteEndObjectAsync();
                }

                await writer.WriteEndArrayAsync();
                await writer.WriteEndObjectAsync();
                await writer.WriteEndArrayAsync();
                await writer.WriteEndObjectAsync();

                await writer.FlushAsync();
            }

            protected override bool TryComputeLength(out long length)
            {
                length = -1;
                return false;
            }
        }
    }
}
