using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Streamline.Core.Interfaces;
using Streamline.Core.Entities;

namespace Streamline.Core.Services
{
    public interface IPlanService
    {
        Task<string> GeneratePlanForDayAsync(DateTime date, string outputFolder);
    }

    public class PlanService : IPlanService
    {
        private readonly IPortalClient _portal;
        private readonly IAIClient _ai;
        private readonly IBeautifierService _beautifier; // Needs to be added to DI!
        // private readonly IRepository<ClassSession> _repo; // Assuming direct DB usage or Repo pattern

        public PlanService(IPortalClient portal, IAIClient ai, IBeautifierService beautifier)
        {
            _portal = portal;
            _ai = ai;
            _beautifier = beautifier;
        }

        public async Task<string> GeneratePlanForDayAsync(DateTime date, string outputFolder)
        {
            if (!System.IO.Directory.Exists(outputFolder))
                System.IO.Directory.CreateDirectory(outputFolder);

            // 1. Scrape Data (Direct DOM extraction)
            var batch = await _portal.ScrapeDayAsync(date);
            
            // 2. Generate Logic
            string finalReport = "";

            foreach (var session in batch.Sessions)
            {
                // Verify students exist
                if (session.Snapshots.Count == 0) continue;

                // Create the prompt context specifically for this session
                var contextData = FormatSessionForAI(session);
                
                // We pass this as a "file" content to the AI helper
                var promptMessages = new List<string> { contextData };

                var prompt = $"Generate a lesson plan for {session.Name} based on the student progress report provided.";
                var content = await _ai.PlanAsync(prompt, promptMessages);

                var plan = new LessonPlan 
                { 
                    ClassSession = session, 
                    GeneratedContent = content,
                    GeneratedAt = DateTime.Now 
                };

                // 4. Beautify
                var docPath = _beautifier.CreateDocx(plan, outputFolder);
                plan.DocxPath = docPath;
                plan.IsBeautified = true;

                finalReport += $"Generated: {docPath}\n";
            }

            return finalReport;
        }

        private string FormatSessionForAI(ClassSession session)
        {
            var sb = new System.Text.StringBuilder();
            sb.AppendLine($"# Class Report: {session.Name}");
            sb.AppendLine("## Student Progress Summary");

            foreach (var snap in session.Snapshots)
            {
                sb.AppendLine($"### {snap.Student.Name}");
                sb.AppendLine($"* **Overall Progress:** {snap.Progress}");
                
                if (!string.IsNullOrEmpty(snap.Notes))
                {
                    sb.AppendLine("* **Skill Status:**");
                    // Notes stored as "[Skill: Status] [Skill: Status]"
                    var skills = snap.Notes.Split(new[] { "] [" }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (var rawSkill in skills)
                    {
                        var clean = rawSkill.Replace("[", "").Replace("]", "");
                        var parts = clean.Split(new[] { ':' }, 2);
                        if (parts.Length == 2)
                        {
                            sb.AppendLine($"    * {parts[0].Trim()}: **{parts[1].Trim()}**");
                        }
                    }
                }
                else
                {
                    sb.AppendLine("* **Skill Status:** No individual skills assessed.");
                }
                sb.AppendLine();
            }
            return sb.ToString();
        }
    }
}
