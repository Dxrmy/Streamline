import google.generativeai as genai
import os
import glob
import logging
from datetime import datetime
from app.config.settings import settings

log = logging.getLogger(__name__)

def run_analyzer(day_tag, week_folder_tag, session_id=None):
    log.info(f"Analyzing {day_tag} (Session: {session_id})...")
    
    # Configure GenAI
    try:
        genai.configure(api_key=settings.GEMINI_API_KEY)
    except Exception as e:
        return False, f"API Key Error: {e}"

    real_day_folder = None
    for item in os.listdir('.'):
        if os.path.isdir(item) and item.lower() == day_tag.lower():
            real_day_folder = item
            break
    if not real_day_folder: return False, f"Folder {day_tag} not found"

    # Find historical files
    report_files = []
    
    # 1. Look for the current session's report FIRST (Critical for flow correctness)
    current_report = None
    if session_id:
        expected_report = os.path.join(real_day_folder, f"full_class_report-{day_tag}_{session_id}.txt")
        if os.path.exists(expected_report):
            current_report = expected_report
            report_files.append(current_report)
        else:
            log.warning(f"Expected report for session {session_id} not found: {expected_report}")

    # 2. Find historical files (excluding the current one we just found)
    # Primary (Day folder)
    processed = set()
    if current_report: processed.add(current_report)
    
    found_historicals = []
    for f in glob.glob(os.path.join(real_day_folder, f"full_class_report-{day_tag}_*.txt")):
        if f not in processed:
            found_historicals.append(f)
            processed.add(f)
    
    # Secondary (Week folder)
    if os.path.isdir(week_folder_tag):
        for f in glob.glob(os.path.join(week_folder_tag, f"full_class_report-{day_tag}_*.txt")):
            if f not in processed:
                found_historicals.append(f)
                processed.add(f)

    # Sort by date
    def parse_ts(path):
        try:
             ts = path.split('_')[-2] + "_" + path.split('_')[-1].split('.')[0]
             return datetime.strptime(ts, "%Y-%m-%d_%H-%M")
        except: return datetime.min
    
    found_historicals.sort(key=parse_ts, reverse=True)
    
    # Add historicals to the list (after current report)
    report_files.extend(found_historicals[:settings.HISTORICAL_FILE_COUNT])

    # Output filename tagged with session_id
    suffix = session_id if session_id else datetime.now().strftime("%Y-%m-%d_%H-%M")
    output_filename = os.path.join(real_day_folder, f"long_term_analysis-{day_tag}_{suffix}.txt")

    if not report_files:
        with open(output_filename, "w") as f:
            f.write(f"# Long-Term Progress Analysis ({day_tag.upper()})\n\nNo historical data found.\n")
        return True, output_filename

    try:
        uploaded = []
        for f in report_files:
            uploaded.append(genai.upload_file(path=f))
            
        with open(settings.ANALYZER_PROMPT_FILE, 'r') as f:
            prompt = f.read()

        model = genai.GenerativeModel(model_name=settings.ANALYZER_MODEL)
        response = model.generate_content([prompt] + uploaded)
        
        with open(output_filename, "w", encoding='utf-8') as f:
            f.write(response.text)
            
        return True, output_filename
    except Exception as e:
        return False, str(e)
