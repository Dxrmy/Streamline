using System;
using System.IO;
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;
using Streamline.Core.Interfaces;
using Streamline.Core.Entities;

namespace Streamline.Infrastructure.Services
{
    public class BeautifierService : IBeautifierService
    {
        public string CreateDocx(LessonPlan plan, string folderPath)
        {
            var fileName = $"LessonPlan_{plan.ClassSession.Name.Replace(":", "").Replace(" ", "_")}_{DateTime.Now:yyyyMMdd}.docx";
            var fullPath = Path.Combine(folderPath, fileName);

            using (var doc = WordprocessingDocument.Create(fullPath, WordprocessingDocumentType.Document))
            {
                var mainPart = doc.AddMainDocumentPart();
                mainPart.Document = new Document();
                var body = mainPart.Document.AppendChild(new Body());

                // Title
                var title = body.AppendChild(new Paragraph());
                var run = title.AppendChild(new Run());
                run.AppendChild(new Text($"Lesson Plan: {plan.ClassSession.Name}"));
                run.PrependChild(new RunProperties(new Bold(), new FontSize { Val = "32" })); // 16pt

                // Content Parser (Markdown-ish to OpenXML)
                // For simplicity in this v1, we split by lines. 
                // A robust parser would handle **bold** inside lines.
                
                var lines = plan.GeneratedContent.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None);
                foreach (var line in lines)
                {
                    var para = body.AppendChild(new Paragraph());
                    var runText = para.AppendChild(new Run());
                    
                    if (line.StartsWith("# "))
                    {
                        // Heading 1
                        runText.AppendChild(new Text(line.Substring(2)));
                        runText.PrependChild(new RunProperties(new Bold(), new FontSize { Val = "28" }, new Color { Val = "2E74B5" }));
                    }
                    else if (line.StartsWith("## "))
                    {
                        // Heading 2
                        runText.AppendChild(new Text(line.Substring(3)));
                        runText.PrependChild(new RunProperties(new Bold(), new FontSize { Val = "24" }, new Color { Val = "1F4D78" }));
                    }
                    else if (line.StartsWith("* ") || line.StartsWith("- "))
                    {
                        // Bullet
                        // OpenXML bullets are complex (NumberingDefinitionsPart), 
                        // simulating with manual indent/char for robustness/speed
                        runText.AppendChild(new Text("• " + line.Substring(2)));
                        para.ParagraphProperties = new ParagraphProperties(new Indentation { Left = "720" }); // 0.5 inch
                    }
                    else
                    {
                        // Normal text
                        // Basic bold check for **text**
                        var parts = line.Split("**");
                        bool bold = false;
                        foreach (var part in parts)
                        {
                            var subRun = para.AppendChild(new Run());
                            subRun.AppendChild(new Text(part));
                            if (bold) subRun.PrependChild(new RunProperties(new Bold()));
                            bold = !bold; // Toggle
                        }
                        // Remove the initial generic run since we did split handling
                        para.RemoveChild(runText); 
                    }
                }
            }

            return fullPath;
        }
    }
}
