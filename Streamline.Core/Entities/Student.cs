using System;
using System.Collections.Generic;

namespace Streamline.Core.Entities
{
    public class Student
    {
        public int Id { get; set; }
        public string Name { get; set; } = string.Empty; // e.g., "John Doe"
        public string NormalizedName { get; set; } = string.Empty; // "johndoe" for searching
        
        public List<AttendanceSnapshot> Snapshots { get; set; } = new();
    }
}
