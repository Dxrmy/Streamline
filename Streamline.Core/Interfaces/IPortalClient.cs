using System;
using System.Threading.Tasks;
using Streamline.Core.Entities;

namespace Streamline.Core.Interfaces
{
    public interface IPortalClient
    {
        Task<bool> LoginAsync(string username, string password);
        Task<SessionBatch> ScrapeDayAsync(DateTime date);
        Task CloseAsync();
    }
}
