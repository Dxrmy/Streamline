using System;
using System.Collections.Generic;

namespace Streamline.Core.Entities
{
    public class ClassSession
    {
        public int Id { get; set; }
        public DateTime ScheduledTime { get; set; } // The actual datetime of the class
        public string Name { get; set; } = string.Empty; // e.g., "16:00 Stage 4"
        public string TimeKey { get; set; } = string.Empty; // "1600"
        public string StageKey { get; set; } = string.Empty; // "4"
        public string Time { get; set; } = "";
        
        public int SessionBatchId { get; set; }
        public SessionBatch SessionBatch { get; set; }

        public List<AttendanceSnapshot> Snapshots { get; set; } = new();
        public LessonPlan? LessonPlan { get; set; }
    }
}
