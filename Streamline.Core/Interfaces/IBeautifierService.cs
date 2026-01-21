using Streamline.Core.Entities;

namespace Streamline.Core.Interfaces
{
    public interface IBeautifierService
    {
        string CreateDocx(LessonPlan plan, string folderPath);
    }
}
