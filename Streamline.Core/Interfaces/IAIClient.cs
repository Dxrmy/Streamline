using System.Collections.Generic;
using System.Threading.Tasks;

namespace Streamline.Core.Interfaces
{
    public interface IAIClient
    {
        Task<string> AnalyzeAsync(string prompt, List<string> filePaths);
        Task<string> PlanAsync(string prompt, List<string> filePaths);
    }
}
