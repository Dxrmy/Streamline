using System;
using System.Collections.Generic;

namespace Streamline.Core.Entities
{
    public class SessionBatch
    {
        public int Id { get; set; }
        public DateTime RunDate { get; set; }
        public string TeachingDay { get; set; } = string.Empty; // "mon", "tue"
        
        public List<ClassSession> Sessions { get; set; } = new();
    }
}
