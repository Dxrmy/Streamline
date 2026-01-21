using Microsoft.EntityFrameworkCore;
using Streamline.Core.Entities;

namespace Streamline.Infrastructure.Database
{
    public class StreamlineDbContext : DbContext
    {
        public DbSet<Student> Students { get; set; }
        public DbSet<ClassSession> ClassSessions { get; set; }
        public DbSet<SessionBatch> SessionBatches { get; set; }
        public DbSet<AttendanceSnapshot> AttendanceSnapshots { get; set; }
        public DbSet<LessonPlan> LessonPlans { get; set; }

        public string DbPath { get; }

        public StreamlineDbContext()
        {
            var folder = Environment.SpecialFolder.LocalApplicationData;
            var path = Environment.GetFolderPath(folder);
            DbPath = System.IO.Path.Join(path, "streamline.db");
        }
        
        // Constructor for DI/Factories that want to specify path
        public StreamlineDbContext(DbContextOptions<StreamlineDbContext> options) : base(options)
        {
        }

        protected override void OnConfiguring(DbContextOptionsBuilder options)
            => options.UseSqlite($"Data Source={DbPath}");

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<SessionBatch>()
                .HasMany(b => b.Sessions)
                .WithOne(s => s.SessionBatch)
                .HasForeignKey(s => s.SessionBatchId)
                .OnDelete(DeleteBehavior.Cascade);

            modelBuilder.Entity<ClassSession>()
                .HasOne(c => c.LessonPlan)
                .WithOne(p => p.ClassSession)
                .HasForeignKey<LessonPlan>(p => p.ClassSessionId);
                
            modelBuilder.Entity<ClassSession>()
                .HasMany(c => c.Snapshots)
                .WithOne(s => s.ClassSession)
                .HasForeignKey(s => s.ClassSessionId);

            modelBuilder.Entity<Student>()
                .HasMany(s => s.Snapshots)
                .WithOne(sn => sn.Student)
                .HasForeignKey(sn => sn.StudentId);
        }
    }
}
