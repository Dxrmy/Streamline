using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Running;
using Streamline.Infrastructure.Services;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Configuration;
using System.Net.Http;
using System.Threading.Tasks;
using System.Threading;
using System.Collections.Generic;
using System.IO;
using System;

namespace Streamline.Performance
{
    [MemoryDiagnoser]
    public class LargeFileBenchmark
    {
        private string _tempFilePath;
        private AIClient _client;
        private HttpClient _httpClient;

        [GlobalSetup]
        public void Setup()
        {
            _tempFilePath = Path.GetTempFileName();
            // Create a 50MB file
            // Using a repeatable pattern to avoid compression optimizations if any (though unlikely here)
            // but also fast to generate.
            using (var fs = new FileStream(_tempFilePath, FileMode.Create))
            using (var sw = new StreamWriter(fs))
            {
                 // Write 50MB of data
                 var chunk = new string('a', 1024);
                 for (int i = 0; i < 50 * 1024; i++)
                 {
                     sw.Write(chunk);
                 }
            }

            var handler = new FakeMessageHandler();
            _httpClient = new HttpClient(handler);

            var configDict = new Dictionary<string, string>
            {
                {"AI:ApiKey", "fake-key"},
                {"AI:AnalyzerModel", "fake-model"}
            };
            var config = new ConfigurationBuilder().AddInMemoryCollection(configDict).Build();

            _client = new AIClient(_httpClient, config, NullLogger<AIClient>.Instance);
        }

        [GlobalCleanup]
        public void Cleanup()
        {
            if (File.Exists(_tempFilePath))
                File.Delete(_tempFilePath);
        }

        [Benchmark]
        public async Task AnalyzeLargeFile()
        {
            await _client.AnalyzeAsync("Analyze this", new List<string> { _tempFilePath });
        }
    }

    public class FakeMessageHandler : HttpMessageHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            // Force serialization of content
            if (request.Content != null)
            {
                var stream = await request.Content.ReadAsStreamAsync(cancellationToken);
                await stream.CopyToAsync(Stream.Null, cancellationToken);
            }

            var response = new HttpResponseMessage(System.Net.HttpStatusCode.OK);
            response.Content = new StringContent("{ \"candidates\": [ { \"content\": { \"parts\": [ { \"text\": \"result\" } ] } } ] }");
            return response;
        }
    }

    public class Program
    {
        public static void Main(string[] args)
        {
            BenchmarkRunner.Run<LargeFileBenchmark>();
        }
    }
}
