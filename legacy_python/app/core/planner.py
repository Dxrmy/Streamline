import google.generativeai as genai
import os
import glob
import logging
from datetime import datetime
from app.config.settings import settings

log = logging.getLogger(__name__)

def find_latest_report(real_day_folder, day_tag, session_id=None):
    # If session_id provided, look for exact match FIRST
    if session_id:
        expected = os.path.join(real_day_folder, f"full_class_report-{day_tag}_{session_id}.txt")
        if os.path.exists(expected):
            return expected
        log.warning(f"Planner could not find report for session {session_id}. Falling back to latest.")

    try:
        files = glob.glob(os.path.join(real_day_folder, f"full_class_report-{day_tag}_*.txt"))
        if not files: return None
        return max(files, key=os.path.getmtime)
    except: return None

def run_planner(day_tag, save_folder_tag, session_id=None):
    log.info(f"Planning for {day_tag} (Session: {session_id})...")
    
    try:
        genai.configure(api_key=settings.GEMINI_API_KEY)
    except Exception as e:
        return False, f"API Key Error: {e}"

    real_day_folder = None
    real_save_folder = None
    
    for item in os.listdir('.'):
        if os.path.isdir(item):
            if item.lower() == day_tag.lower(): real_day_folder = item
            if item.lower() == save_folder_tag.lower(): real_save_folder = item
    
    if not real_day_folder: return False, f"Day folder {day_tag} not found"
    if not real_save_folder: real_save_folder = real_day_folder # Fallback

    report_file = find_latest_report(real_day_folder, day_tag, session_id)
    if not report_file: return False, f"No recent report found for {day_tag}"

    # Look for specific analysis file if session_id exists
    suffix = session_id if session_id else ""
    # Try finding one with the session_id first (suffix logic varies, we used _session_id in analyzer)
    potential_analysis = os.path.join(real_day_folder, f"long_term_analysis-{day_tag}_{suffix}.txt")
    
    analysis_file = None
    if os.path.exists(potential_analysis):
        analysis_file = potential_analysis
    else:
        # Fallback to generic latest check or legacy name
        legacy_name = os.path.join(real_day_folder, f"long_term_analysis-{day_tag}.txt")
        if os.path.exists(legacy_name):
            analysis_file = legacy_name
    
    # Uploads
    files_to_send = []
    
    # PDFs
    for pdf in settings.PDF_KNOWLEDGE_BASE:
        if os.path.exists(pdf):
            files_to_send.append(genai.upload_file(path=pdf))
    
    files_to_send.append(genai.upload_file(path=report_file))
    
    if analysis_file:
        files_to_send.append(genai.upload_file(path=analysis_file))
        
    if os.path.exists(settings.WEEKLY_NOTES_FILENAME):
        files_to_send.append(genai.upload_file(path=settings.WEEKLY_NOTES_FILENAME))
        
    adhoc = settings.ADHOC_NOTES_FILENAME_TEMPLATE.replace('.txt', f'-{day_tag}.txt')
    if os.path.exists(adhoc):
        files_to_send.append(genai.upload_file(path=adhoc))

    try:
        with open(settings.PLANNER_PROMPT_FILE, 'r') as f:
            prompt = f.read()

        model = genai.GenerativeModel(model_name=settings.PLANNER_MODEL)
        response = model.generate_content([prompt] + files_to_send)
        
        ts = session_id if session_id else datetime.now().strftime("%Y-%m-%d_%H-%M")
        output_file = os.path.join(real_save_folder, f"lesson_plans_output-{day_tag}_{ts}.txt")
        
        with open(output_file, "w", encoding="utf-8") as f:
            f.write(response.text)
            
        return True, output_file

    except Exception as e:
        return False, str(e)
