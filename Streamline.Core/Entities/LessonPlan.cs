using System;

namespace Streamline.Core.Entities
{
    public class LessonPlan
    {
        public int Id { get; set; }
        
        public int ClassSessionId { get; set; }
        public ClassSession ClassSession { get; set; }

        public string GeneratedContent { get; set; } = string.Empty; // Markdown from AI
        public bool IsBeautified { get; set; }
        public string? DocxPath { get; set; }
        public DateTime GeneratedAt { get; set; }
    }
}
