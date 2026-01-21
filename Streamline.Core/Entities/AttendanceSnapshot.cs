using System;

namespace Streamline.Core.Entities
{
    public class AttendanceSnapshot
    {
        public int Id { get; set; }
        
        public int StudentId { get; set; }
        public Student Student { get; set; }

        public int ClassSessionId { get; set; }
        public ClassSession ClassSession { get; set; }
        public string Status { get; set; } = "Present";
        public string Progress { get; set; } = "0%";
        public string Notes { get; set; } = ""; // Used for Skill Status in V1
        public string SkillsJson { get; set; } = "{}"; // JSON blob of skill status
    }
}
