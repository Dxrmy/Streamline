using Xunit;
using Moq;
using Streamline.Infrastructure.Services;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Configuration;
using System.Net.Http;
using System.Threading.Tasks;
using System.Threading;
using System.Collections.Generic;
using System.IO;
using System;
using Newtonsoft.Json.Linq;

namespace Streamline.Tests
{
    public class AIClientTests
    {
        [Fact]
        public async Task AnalyzeAsync_SendsCorrectJsonStructure()
        {
            // Arrange
            var tempFile = Path.GetTempFileName();
            File.WriteAllText(tempFile, "FileContent");

            string capturedRequest = null;
            var handler = new MockHttpMessageHandler(async (req) => {
                capturedRequest = await req.Content.ReadAsStringAsync();
                return new HttpResponseMessage(System.Net.HttpStatusCode.OK)
                {
                    Content = new StringContent("{ \"candidates\": [ { \"content\": { \"parts\": [ { \"text\": \"Response\" } ] } } ] }")
                };
            });

            var httpClient = new HttpClient(handler);
            var configDict = new Dictionary<string, string>
            {
                {"AI:ApiKey", "test-key"},
                {"AI:AnalyzerModel", "test-model"}
            };
            var config = new ConfigurationBuilder().AddInMemoryCollection(configDict).Build();
            var client = new AIClient(httpClient, config, NullLogger<AIClient>.Instance);

            // Act
            await client.AnalyzeAsync("Prompt", new List<string> { tempFile });

            // Assert
            Assert.NotNull(capturedRequest);
            var json = JObject.Parse(capturedRequest);

            // Check structure
            // { "contents": [ { "parts": [ { "text": "Prompt" }, { "text": "Header" }, { "text": "FileContent" } ] } ] }

            var parts = json["contents"]?[0]?["parts"] as JArray;
            Assert.NotNull(parts);
            Assert.Equal(3, parts.Count); // Prompt, Header, Content

            Assert.Equal("Prompt", parts[0]["text"]?.ToString());
            Assert.Contains(Path.GetFileName(tempFile), parts[1]["text"]?.ToString());
            Assert.Equal("FileContent", parts[2]["text"]?.ToString());

            // Cleanup
            File.Delete(tempFile);
        }
    }

    public class MockHttpMessageHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, Task<HttpResponseMessage>> _handler;

        public MockHttpMessageHandler(Func<HttpRequestMessage, Task<HttpResponseMessage>> handler)
        {
            _handler = handler;
        }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            return _handler(request);
        }
    }
}
