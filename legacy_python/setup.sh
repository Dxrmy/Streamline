#!/bin/bash

# --- This script will migrate your entire project to use Playwright ---
# --- It will replace ALL existing scripts ---

echo "[INFO] Starting setup. This will overwrite all existing Python scripts and prompts."
set -e

# --- 1. Housekeeping ---
echo "[INFO] Removing old scripts..."
rm -f main_bot.py parser.py run_analyzer.py run_planner.py downloader.py requirements.txt config.ini

echo "[INFO] Ensuring data folders exist..."
mkdir -p mon tue wed thu fri sat sun week
echo "[INFO] Folders created/verified."

# --- 2. Create requirements.txt (Now with Playwright) ---
echo "[INFO] Creating requirements.txt with Playwright..."
cat <<'EOF' > requirements.txt
beautifulsoup4
lxml
google-generativeai
requests
python-telegram-bot
apscheduler
playwright
EOF

echo "[INFO] Installing all required Python libraries..."
pip install -r requirements.txt
echo "[INFO] Installing Playwright browser dependencies (this may take a minute)..."
python -m playwright install chromium
echo "[INFO] Libraries installed."

# --- 3. Create the NEW config.ini (with new login and days) ---
echo "[INFO] Creating new 'config.ini' file..."
cat <<'EOF' > config.ini
[API]
# Your keys (NO QUOTES)
GEMINI_API_KEY = AIzaSyCi6XBKLnaK2O3YCVIrXm8k2CMu36V9DqM
TELEGRAM_BOT_TOKEN = 8155456769:AAHIFZn3vsqvU0AxfqTVKO28vkyYrbOmu6Q

[AI]
ANALYZER_MODEL = models/gemini-2.0-flash-lite
PLANNER_MODEL = models/gemini-2.5-flash-lite
ANALYZER_PROMPT_FILE = AI_ANALYZER_SYSTEM_PROMPT.txt
PLANNER_PROMPT_FILE = AI_LESSON_PLANNER_SYSTEM_PROMPT.txt
PDF_KNOWLEDGE_BASE = SEQRESOURCE.pdf, SEQL1ASSISTANT.pdf, SEQL2TEACHING.pdf, TEACHINGGUIDE.pdf, SWIMTEACHV3.pdf

[System]
# --- UPDATED TEACHING DAYS ---
TEACHING_DAYS = mon, tue, thu
WEEK_SAVE_FOLDER = week
# --- UPDATED FILENAME: Playwright saves .mhtml ---
SESSIONS_FILENAME = sessions.mhtml
FILE_RETENTION_DAYS = 64
HISTORICAL_FILE_COUNT = 3
WEEKLY_NOTES_FILENAME = weekly_notes.txt
ADHOC_NOTES_FILENAME = adhoc_notes.txt

[Playwright]
# --- UPDATED LOGIN DETAILS ---
PORTAL_URL = https://worcester.coachportal.co.uk/login
PORTAL_USERNAME = krich
PORTAL_PASSWORD = Perdiswell1!
EOF
echo "[INFO] config.ini created."

# --- 4. Create the new 'downloader.py' (Full Playwright Script) ---
echo "[INFO] Creating new 'downloader.py' (Playwright enabled)..."
cat <<'EOF' > downloader.py
import logging
import sys
import os
import configparser
import re
import json
from datetime import datetime, timedelta
from playwright.sync_api import sync_playwright, TimeoutError

# --- 1. LOGGING ---
logging.basicConfig(level=logging.INFO, format="[%(levelname)s] (Downloader) %(message)s", handlers=[logging.StreamHandler(sys.stdout)])
log = logging.getLogger(__name__)

# --- 2. CONFIGURATION ---
config = configparser.ConfigParser()
config.read('config.ini')

try:
    PORTAL_URL = config.get('Playwright', 'PORTAL_URL')
    PORTAL_USERNAME = config.get('Playwright', 'PORTAL_USERNAME')
    PORTAL_PASSWORD = config.get('Playwright', 'PORTAL_PASSWORD')
    TEACHING_DAYS = [day.strip() for day in config.get('System', 'TEACHING_DAYS').split(',')]
    SESSIONS_FILENAME = config.get('System', 'SESSIONS_FILENAME', fallback='sessions.mhtml')
except Exception as e:
    log.critical(f"FATAL ERROR reading config.ini for Playwright: {e}")
    sys.exit(1)

BASE_URL = "https://worcester.coachportal.co.uk"

# --- 3. HELPER FUNCTIONS ---
def get_real_folder_path(folder_tag):
    """Finds the real, cased path for a lowercase folder tag."""
    for item in os.listdir('.'):
        if os.path.isdir(item) and item.lower() == folder_tag.lower():
            return item
    log.warning(f"Could not find a case-insensitive match for folder '{folder_tag}'. Creating it.")
    os.makedirs(folder_tag, exist_ok=True)
    return folder_tag

def get_stage_key(class_name_text):
    """Helper to get '6' from 'Stage 6', 'a' from 'Adults', etc."""
    class_name_lower = class_name_text.lower()
    if 'adult' in class_name_lower: return 'a'
    matches = re.findall(r'\d+', class_name_text)
    if matches:
        first_match = matches[0]
        if first_match in ['8', '9', '10']: return '8'
        return first_match 
    log.warning(f"Could not determine stage key for class: {class_name_text}")
    return "unknown"

def get_target_dates():
    """Gets the dates for the configured teaching days of the *current* week."""
    today = datetime.now()
    # 0 = Monday, 6 = Sunday
    start_of_week = today - timedelta(days=today.weekday())
    
    date_map = {}
    day_map = {
        'mon': 0, 'tue': 1, 'wed': 2, 'thu': 3, 'fri': 4, 'sat': 5, 'sun': 6
    }
    
    for day_tag in TEACHING_DAYS:
        day_tag = day_tag.lower().strip()
        if day_tag in day_map:
            target_date = start_of_week + timedelta(days=day_map[day_tag])
            date_map[day_tag] = target_date
            log.info(f"Mapping day '{day_tag}' to date: {target_date.strftime('%Y-%m-%d')}")
            
    return date_map

async def save_as_mhtml(page, file_path):
    """Saves the current page as an MHTML file."""
    try:
        session = await page.context.new_cdp_session(page)
        doc = await session.send('Page.captureSnapshot', { 'format': 'mhtml' })
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(doc['data'])
        await session.detach()
        log.info(f"    Saved {file_path}")
    except Exception as e:
        log.error(f"    Failed to save MHTML: {e}")

# --- 4. MAIN DOWNLOAD FUNCTION ---
def main_downloader():
    log.info("--- Starting Playwright Downloader ---")
    
    target_dates = get_target_dates()
    if not target_dates:
        log.error("No valid TEACHING_DAYS configured in config.ini. Aborting.")
        return False
        
    with sync_playwright() as p:
        browser = None
        try:
            browser = p.chromium.launch(headless=True, args=["--no-sandbox"])
            # Emulate a mobile device at 1080x1920
            context = browser.new_context(
                viewport={'width': 1080, 'height': 1920},
                user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
            )
            page = context.new_page()

            # --- 1. LOGIN ---
            log.info(f"Navigating to {PORTAL_URL}...")
            page.goto(PORTAL_URL, timeout=60000)
            
            log.info("Filling login form...")
            page.wait_for_selector("input[name='username']", timeout=30000).fill(PORTAL_USERNAME)
            page.fill("input[name='password']", PORTAL_PASSWORD)
            
            log.info("Submitting login...")
            page.click("button[type='submit']")
            page.wait_for_url(f"{BASE_URL}/member-groups", timeout=60000)
            log.info("Login successful. Now on member-groups page.")
            
            # --- 2. LOOP THROUGH EACH TEACHING DAY ---
            for day_tag, target_date in target_dates.items():
                real_day_folder = get_real_folder_path(day_tag)
                log.info(f"--- Processing Day: {day_tag.upper()} ({target_date.strftime('%Y-%m-%d')}) ---")
                
                # --- 3. NAVIGATE TO THE CORRECT DATE ---
                log.info("Opening calendar popup...")
                page.click("button:has(i.mdi-calendar)", timeout=30000)
                
                day_number_str = str(target_date.day)
                log.info(f"Selecting day '{day_number_str}' from calendar...")
                
                # Click the button in the calendar
                page.click(f"button:not(.v-btn--disabled):has(div.v-btn__content:text-is('{day_number_str}'))")
                
                log.info("Waiting for network to be idle...")
                page.wait_for_load_state('networkidle', timeout=30000)
                log.info("Date selected. Saving sessions page...")

                # --- 4. DOWNLOAD SESSIONS PAGE (as MHTML) ---
                sessions_file_path = os.path.join(real_day_folder, SESSIONS_FILENAME)
                
                # We need to run the async save_as_mhtml function
                import asyncio
                asyncio.run(save_as_mhtml(page, sessions_file_path))
                
                # --- 5. PARSE SESSIONS PAGE TO FIND CLASSES ---
                class_rows = page.query_selector_all("tr.clickable")
                if not class_rows:
                    log.warning(f"No classes found for {day_tag}. Skipping to next day.")
                    continue
                
                log.info(f"Found {len(class_rows)} classes for {day_tag}.")
                
                class_info_list = []
                for row in class_rows:
                    time_el = row.query_selector("td:nth-child(1)")
                    name_el = row.query_selector("td:nth-child(2)")
                    link_el = row.query_selector("a[href*='/member-groups/']")
                    
                    if time_el and name_el and link_el:
                        class_info_list.append({
                            "time": time_el.inner_text().strip(),
                            "name": name_el.inner_text().strip(),
                            "url": link_el.get_attribute("href")
                        })
                
                # --- 6. LOOP THROUGH EACH CLASS ---
                for class_info in class_info_list:
                    time_key = class_info['time'].replace(':', '')
                    stage_key = get_stage_key(class_info['name'])
                    log.info(f"  Processing class: {class_info['name']} at {class_info['time']}")
                    
                    class_url = class_info['url']
                    page.goto(f"{BASE_URL}{class_url}", timeout=60000)
                    
                    # --- 7. MARK ALL PRESENT ---
                    try:
                        page.click("button:has-text('Mark All Present')", timeout=10000)
                        log.info("    Marked all as present.")
                    except TimeoutError:
                        log.warning("    Could not find 'Mark All Present' button.")
                    
                    page.go_back()
                    
                    # --- 8. DOWNLOAD PERCENTAGES (ASSESS BY MEMBER) ---
                    page.goto(f"{BASE_URL}{class_url}", timeout=60000)
                    log.info("    Downloading percentages page...")
                    page.click("a:has-text('Assess by member')", timeout=30000)
                    page.wait_for_load_state('networkidle')
                    
                    register_file_path = os.path.join(real_day_folder, f"{time_key}stage{stage_key}register.mhtml")
                    asyncio.run(save_as_mhtml(page, register_file_path))
                    page.go_back()

                    # --- 9. DOWNLOAD SKILLS (ASSESS BY SKILL) ---
                    log.info("    Downloading skills page(s)...")
                    page.click("a:has-text('Assess by skill')", timeout=30000)
                    
                    skill_links = page.query_selector_all("a[href*='/assess-by-skill/']")
                    
                    if not skill_links:
                        log.warning("    No skill sub-pages found. Skipping skills.")
                        page.go_back() # Back to class page
                        page.go_back() # Back to sessions page
                        continue

                    skill_hrefs = [link.get_attribute("href") for link in skill_links]
                    log.info(f"    Found {len(skill_hrefs)} skill pages to download.")
                    
                    for i, skill_href in enumerate(skill_hrefs):
                        suffix = f"-{i}.mhtml" if i > 0 else ".mhtml"
                        skill_file_path = os.path.join(real_day_folder, f"{time_key}stage{stage_key}skill{suffix}")
                        
                        log.info(f"    Navigating to skill page: {skill_href}")
                        page.goto(f"{BASE_URL}{skill_href}", timeout=60000)
                        
                        dropdowns = page.query_selector_all("div.v-list-group__header")
                        if dropdowns:
                            log.info(f"    Expanding {len(dropdowns)} skill dropdowns...")
                            for dd in dropdowns:
                                try: dd.click(timeout=1000)
                                except Exception as e: log.warning(f"      Could not click dropdown: {e}")
                        
                        asyncio.run(save_as_mhtml(page, skill_file_path))
                        page.go_back()
                    
                    page.go_back() # Back to class page
                    page.go_back() # Back to sessions page
            
                log.info(f"--- Finished processing {day_tag.upper()} ---")
                page.goto(f"{BASE_URL}/member-groups", timeout=60000)
            
            log.info("All days processed.")
            
        except TimeoutError as e:
            log.critical(f"FATAL ERROR: A navigation step timed out. The website might be slow or selectors are wrong.")
            log.critical(f"Error: {e}")
            return False
        except Exception as e:
            log.critical(f"An unexpected error occurred: {e}")
            return False
        finally:
            if browser:
                log.info("Closing browser.")
                browser.close()
        
    log.info("--- Downloader Finished Successfully ---")
    return True

if __name__ == "__main__":
    main_downloader()
EOF
echo "[INFO] downloader.py created."

# --- 5. Create parser.py (now reads .mhtml) ---
echo "[INFO] Updating 'parser.py' to read .mhtml files..."
cat <<'EOF' > parser.py
import re
import os
import sys
import glob
import logging
import configparser
from email import message_from_bytes
from email.policy import default
from datetime import datetime, timedelta
from bs4 import BeautifulSoup 

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] (Parser) %(message)s", handlers=[logging.StreamHandler(sys.stdout)])
log = logging.getLogger(__name__)

config = configparser.ConfigParser()
config.read('config.ini')
try:
    RETENTION_DAYS = config.getint('System', 'FILE_RETENTION_DAYS', fallback=64)
    SESSIONS_FILENAME_LOWER = config.get('System', 'SESSIONS_FILENAME', fallback='sessions.mhtml').lower()
except Exception as e:
    log.error(f"Error reading config.ini: {e}. Using defaults.")
    RETENTION_DAYS = 64
    SESSIONS_FILENAME_LOWER = "sessions.mhtml"

def get_real_folder_path(folder_tag):
    for item in os.listdir('.'):
        if os.path.isdir(item) and item.lower() == folder_tag.lower():
            return item
    log.warning(f"Could not find a case-insensitive match for folder '{folder_tag}'. Using the tag directly.")
    return folder_tag

def find_insensitive_path(directory, base_filename):
    try:
        base_lower = base_filename.lower()
        for item in os.listdir(directory):
            if item.lower() == base_lower:
                return os.path.join(directory, item)
    except FileNotFoundError:
        log.error(f"Directory not found: {directory}")
        return None
    except Exception as e:
        log.error(f"Error scanning {directory}: {e}")
        return None
    return None

def perform_housekeeping(day_folder_real):
    log.info(f"--- Starting Housekeeping in folder: '{day_folder_real}' ---")
    files_deleted = 0
    now = datetime.now()
    cutoff_date = now - timedelta(days=RETENTION_DAYS)
    file_patterns = [
        os.path.join(day_folder_real, "full_class_report-*.txt"),
        os.path.join(day_folder_real, "lesson_plans_output-*.txt"),
        os.path.join(day_folder_real, "long_term_analysis-*.txt")
    ]
    for pattern in file_patterns:
        for file_path in glob.glob(pattern):
            try:
                timestamp_str = file_path.split('_')[-2] + "_" + file_path.split('_')[-1].split('.')[0]
                file_date = datetime.strptime(timestamp_str, "%Y-%m-%d_%H-%M")
                if file_date < cutoff_date:
                    os.remove(file_path)
                    log.info(f"  DELETED: {file_path} (older than {RETENTION_DAYS} days)")
                    files_deleted += 1
            except (IndexError, ValueError):
                log.warning(f"  SKIPPED: Could not parse date from '{file_path}'.")
            except Exception as e:
                log.error(f"  ERROR: Could not delete '{file_path}'. Reason: {e}")
    log.info(f"Housekeeping complete. Deleted {files_deleted} old files.")

def get_html_from_mhtml(file_path):
    """
    Extracts HTML from a .mhtml file.
    """
    if not file_path:
        return None
    try:
        with open(file_path, 'rb') as f:
            data = f.read()
            msg = message_from_bytes(data, policy=default)
            for part in msg.walk():
                if part.get_content_type() == 'text/html':
                    payload_bytes = part.get_payload(decode=True)
                    charset = part.get_charset() or 'utf-8'
                    try: return payload_bytes.decode(charset, errors='ignore')
                    except LookupError: return payload_bytes.decode('utf-8', errors='ignore')
            log.warning(f"Could not find 'text/html' part in {file_path}")
            return None
    except FileNotFoundError:
        log.warning(f"File not found: {file_path}")
        return None
    except Exception as e:
        log.error(f"An error occurred reading {file_path}: {e}")
        return None

def parse_all_classes(html_content):
    classes = []
    def get_stage_key(class_name_text):
        class_name_lower = class_name_text.lower()
        if 'adult' in class_name_lower: return 'a'
        matches = re.findall(r'\d+', class_name_text)
        if matches:
            first_match = matches[0]
            if first_match in ['8', '9', '10']: return '8'
            return first_match 
        log.warning(f"Could not determine stage key for class: {class_name_text}")
        return None
    try:
        soup = BeautifulSoup(html_content, 'lxml')
        class_rows = soup.find_all('tr', class_='clickable')
        if not class_rows:
            log.error(f"No 'tr' with class 'clickable' found in {SESSIONS_FILENAME_LOWER}. Cannot find any classes.")
            return []
        for row in class_rows:
            columns = row.find_all('td')
            if len(columns) >= 2:
                time, name = columns[0].get_text(strip=True), columns[1].get_text(strip=True)
                stage_key, time_key = get_stage_key(name), time.replace(':', '')
                if stage_key:
                    classes.append({'full_name': f"{time} {name}", 'stage_key': stage_key.lower(), 'time_key': time_key})
        return classes
    except Exception as e:
        log.error(f"Error parsing class list: {e}")
        return []

def parse_student_percentages(html_content):
    students = {}
    try:
        soup = BeautifulSoup(html_content, 'lxml')
        student_items = soup.find_all('a', href=re.compile(r'/assess-by-member/'))
        for item in student_items:
            title_div = item.find('div', class_='v-list-item__title')
            if title_div:
                percentage_span = title_div.find('span', class_='percentage-complete')
                if percentage_span:
                    percentage = percentage_span.get_text(strip=True)
                    full_text = title_div.get_text(strip=True)
                    display_name = full_text.replace(percentage, '', 1).strip()
                    clean_name = display_name.split(' (Stage')[0].strip()
                    students[clean_name] = {'overall_progress': percentage, 'skills': [], 'display_name': display_name}
        return students
    except Exception as e:
        log.error(f"Error parsing student percentages: {e}")
        return students

def parse_skill_objectives(html_content, students_dict):
    try:
        soup = BeautifulSoup(html_content, 'lxml')
        skill_groups = soup.find_all('div', class_='v-list-group')
        if not skill_groups:
            log.warning("No skill groups found in skill objectives file.")
            return students_dict
        for skill_group in skill_groups:
            if skill_group.find('div', class_='v-list-group'): continue
            objective_title_elem = skill_group.find('div', class_='v-list-item__title')
            student_rows = skill_group.find_all('div', role='listitem')
            if not objective_title_elem or not student_rows: continue
            objective_title = ' '.join(objective_title_elem.get_text(strip=True).split())
            for row in student_rows:
                student_name_elem = row.find('a')
                if not student_name_elem: continue
                name_raw = student_name_elem.get_text(strip=True)
                student_name = name_raw.split(' (Stage')[0].strip()
                status_btn = row.find('button', class_='v-item--active')
                status = status_btn.get_text(strip=True) if status_btn else "Not Assessed"
                if student_name in students_dict:
                    students_dict[student_name]['skills'].append({'objective': objective_title, 'status': status})
                else:
                    log.warning(f"Found skill data for '{student_name}' but they were not in the register file.")
        return students_dict
    except Exception as e:
        log.error(f"Error parsing skill objectives: {e}")
        return students_dict

def format_data_for_ai(class_name, students_data):
    report_lines = [f"# Class Report: {class_name}\n", "## Student Progress Summary\n"]
    if not students_data:
        report_lines.append("No students found in register file for this class.\n")
        return "\n".join(report_lines)
    for student_name in sorted(students_data.keys()):
        student = students_data[student_name]
        display_name_to_use = student.get('display_name', student_name)
        report_lines.append(f"### {display_name_to_use}")
        report_lines.append(f"* **Overall Progress:** {student['overall_progress']}")
        if student['skills']:
            report_lines.append("* **Skill Status:**")
            for skill in student['skills']:
                report_lines.append(f"    * {skill['objective']}: **{skill['status']}**")
        else:
            report_lines.append("* **Skill Status:** No individual skills assessed.")
        report_lines.append("\n")
    return "\n".join(report_lines)

def main():
    if len(sys.argv) < 2:
        log.critical("FATAL ERROR: No day_tag provided.")
        sys.exit(1)
    day_tag = sys.argv[1].lower()
    
    real_day_folder = get_real_folder_path(day_tag)
    if not os.path.isdir(real_day_folder):
        log.critical(f"FATAL ERROR: Folder '{day_tag}' (or a case-variant) does not exist.")
        sys.exit(1)
    
    log.info(f"--- Starting Multi-Class Parser for folder: '{real_day_folder}' ---")
    
    try:
        perform_housekeeping(real_day_folder)
    except Exception as e:
        log.error(f"Failed to perform housekeeping. Error: {e}")
    
    now = datetime.now()
    filename_timestamp = now.strftime("%Y-%m-%d_%H-%M")
    readable_timestamp = now.strftime("%A, %B %d, %Y at %I:%M %p")
    output_filename = os.path.join(real_day_folder, f"full_class_report-{day_tag}_{filename_timestamp}.txt")

    sessions_file_path = find_insensitive_path(real_day_folder, SESSIONS_FILENAME_LOWER)
    html_class_list = get_html_from_mhtml(sessions_file_path) # <-- CHANGED
    if not html_class_list:
        log.critical(f"FATAL ERROR: Could not read '{SESSIONS_FILENAME_LOWER}' (case-insensitive) in {real_day_folder}.")
        return

    log.info(f"Parsing all classes from {sessions_file_path}...")
    all_classes = parse_all_classes(html_class_list)
    log.info(f"Found {len(all_classes)} classes to process.")
    if not all_classes:
        log.warning("No classes were found in the sessions file. Exiting.")
        return

    final_report_content = []
    for class_info in all_classes:
        class_name, stage_key, time_key = class_info['full_name'], class_info['stage_key'], class_info['time_key']
        log.info(f"--- Processing Class: {class_name} (Time Key: '{time_key}') ---")

        base_register_name = f"{time_key}stage{stage_key}register.mhtml" # <-- CHANGED
        base_skill_name = f"{time_key}stage{stage_key}skill.mhtml" # <-- CHANGED

        register_file_path = find_insensitive_path(real_day_folder, base_register_name)
        html_percentages = get_html_from_mhtml(register_file_path) # <-- CHANGED
        
        if not html_percentages:
            log.error(f"Could not find register file for '{class_name}' (looked for '{base_register_name}' in {real_day_folder}).")
            log.warning(f"  Skipping this class.")
            continue

        log.info(f"Parsing student percentages from {register_file_path}...")
        students_data = parse_student_percentages(html_percentages)
        if not students_data: log.warning(f"No students found in {register_file_path}.")
        else: log.info(f"Found {len(students_data)} students.")

        all_skill_htmls = []
        base_skill_file_path = find_insensitive_path(real_day_folder, base_skill_name)
        base_html = get_html_from_mhtml(base_skill_file_path) # <-- CHANGED
            
        if not base_html:
            log.error(f"Could not find base skill file for '{class_name}' (looked for '{base_skill_name}' in {real_day_folder}).")
            log.warning(f"  Skipping this class.")
            continue
        
        all_skill_htmls.append(base_html)
        log.info(f"Parsing skill objectives from {base_skill_file_path}...")
        
        for i in range(1, 6):
            suffix = f"-{i}.mhtml" # <-- CHANGED
            base_skill_name_seq = f"{time_key}stage{stage_key}skill{suffix}"
            
            seq_skill_file_path = find_insensitive_path(real_day_folder, base_skill_name_seq)
            html_content = get_html_from_mhtml(seq_skill_file_path) # <-- CHANGED
            
            if html_content:
                log.info(f"Parsing additional skills from {seq_skill_file_path}...")
                all_skill_htmls.append(html_content)
            else:
                log.info(f"No more skill files found (stopped at suffix {suffix}).")
                break
        
        final_data = students_data
        for html in all_skill_htmls:
            final_data = parse_skill_objectives(html, final_data)

        log.info("Formatting data for this class...")
        report_text = format_data_for_ai(class_name, final_data)
        final_report_content.append(report_text)
        log.info(f"Successfully processed {class_name}.")
    
    if not final_report_content:
        log.warning("No data was processed successfully. No report generated.")
        return

    log.info("--- ALL CLASSES PROCESSED ---")
    try:
        main_content = "\n\n".join(final_report_content)
        footer = (
            f"\n\n---\n"
            f"Report generated for: {day_tag.upper()}\n"
            f"Generated on: {readable_timestamp}\n"
            f"Generated by: {os.path.basename(__file__)}\n"
            f"---"
        )
        with open(output_filename, "w", encoding="utf-8") as f:
            f.write(main_content)
            f.write(footer)
        log.info(f"Full, combined report saved to: {output_filename}")
    except Exception as e:
        log.critical(f"FATAL ERROR: Could not write final output file: {e}")

if __name__ == "__main__":
    main()
EOF
echo "[INFO] parser.py (MHTML-aware) created."

# --- 6. Create run_analyzer.py (Unchanged but regenerated) ---
echo "[INFO] Creating 'run_analyzer.py' (config-aware)..."
cat <<'EOF' > run_analyzer.py
import google.generativeai as genai
import os
import sys
import glob
import logging
import configparser
from datetime import datetime

config = configparser.ConfigParser()
config.read('config.ini')
try:
    API_KEY = config.get('API', 'GEMINI_API_KEY')
    ANALYZER_MODEL_NAME = config.get('AI', 'ANALYZER_MODEL')
    SYSTEM_PROMPT_FILE = config.get('AI', 'ANALYZER_PROMPT_FILE')
    HISTORICAL_FILE_COUNT = config.getint('System', 'HISTORICAL_FILE_COUNT')
except Exception as e:
    print(f"FATAL ERROR reading config.ini: {e}")
    sys.exit(1)

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] (Analyzer) %(message)s", handlers=[logging.StreamHandler(sys.stdout)])
log = logging.getLogger(__name__)

def get_real_folder_path(folder_tag):
    for item in os.listdir('.'):
        if os.path.isdir(item) and item.lower() == folder_tag.lower():
            return item
    log.warning(f"Could not find a case-insensitive match for folder '{folder_tag}'. Using the tag directly.")
    return folder_tag

def find_historical_reports(real_day_folder, real_week_folder, day_tag, num_files):
    log.info(f"Searching for last {num_files} reports for day: '{day_tag}', using '{real_week_folder}' as fallback...")
    report_files_with_dates = []
    processed_paths = set()
    
    day_pattern = os.path.join(real_day_folder, f"full_class_report-{day_tag}_*.txt")
    log.info(f"Checking primary location: {day_pattern}")
    for file_path in glob.glob(day_pattern):
        if file_path not in processed_paths:
            try:
                timestamp_str = file_path.split('_')[-2] + "_" + file_path.split('_')[-1].split('.')[0]
                file_date = datetime.strptime(timestamp_str, "%Y-%m-%d_%H-%M")
                report_files_with_dates.append((file_date, file_path))
                processed_paths.add(file_path)
            except (IndexError, ValueError):
                log.warning(f"Could not parse date from '{file_path}'. Skipping.")

    week_pattern = os.path.join(real_week_folder, f"full_class_report-{day_tag}_*.txt")
    log.info(f"Checking fallback location: {week_pattern}")
    for file_path in glob.glob(week_pattern):
        if file_path not in processed_paths:
            try:
                timestamp_str = file_path.split('_')[-2] + "_" + file_path.split('_')[-1].split('.')[0]
                file_date = datetime.strptime(timestamp_str, "%Y-%m-%d_%H-%M")
                report_files_with_dates.append((file_date, file_path))
                processed_paths.add(file_path)
            except (IndexError, ValueError):
                log.warning(f"Could not parse date from '{file_path}'. Skipping.")

    if not report_files_with_dates:
        log.warning("No historical reports found in any location.")
        return []
        
    report_files_with_dates.sort(key=lambda x: x[0], reverse=True)
    historical_paths = [path for date, path in report_files_with_dates[:num_files]]
    
    log.info(f"Found {len(historical_paths)} unique historical reports:")
    for path in historical_paths:
        log.info(f"  - {path}")
    return historical_paths

def main():
    if len(sys.argv) < 3:
        log.critical("FATAL ERROR: Not enough arguments.")
        sys.exit(1)
        
    day_tag = sys.argv[1].lower()
    week_folder_tag = sys.argv[2].lower()
    
    real_day_folder = get_real_folder_path(day_tag)
    real_week_folder = get_real_folder_path(week_folder_tag)
    
    output_filename = os.path.join(real_day_folder, f"long_term_analysis-{day_tag}.txt")
    log.info(f"--- Starting Analyzer for folder: '{real_day_folder}' ---")

    try:
        genai.configure(api_key=API_KEY)

        log.info(f"Loading analyzer prompt from {SYSTEM_PROMPT_FILE}...")
        with open(SYSTEM_PROMPT_FILE, 'r') as f:
            system_prompt_text = f.read()

        historical_files_to_upload = find_historical_reports(real_day_folder, real_week_folder, day_tag, HISTORICAL_FILE_COUNT)
        
        if not historical_files_to_upload:
            log.warning("No historical files to analyze. Saving empty analysis file.")
            with open(output_filename, "w") as f:
                f.write(f"# Long-Term Progress Analysis ({day_tag.upper()})\n\nNo historical data found.\n")
            return

        uploaded_files = []
        log.info("Uploading historical files to Gemini...")
        for file_path in historical_files_to_upload:
            try:
                file_obj = genai.upload_file(path=file_path)
                uploaded_files.append(file_obj)
            except Exception as e:
                log.error(f"Could not upload '{file_path}': {e}")
        
        if not uploaded_files:
            log.critical("FATAL ERROR: Failed to upload any historical files. Exiting.")
            return

        log.info(f"Connecting to Gemini (using {ANALYZER_MODEL_NAME}) to generate analysis...")
        model = genai.GenerativeModel(model_name=ANALYZER_MODEL_NAME)
        prompt_parts = [system_prompt_text]
        prompt_parts.extend(uploaded_files)
        response = model.generate_content(prompt_parts)
        
        log.info("Analysis generation complete.")
        ai_output = response.text
        output_lines = ai_output.splitlines()

        log.info("--- Long-Term Analysis Complete (Preview) ---")
        for line in output_lines[:10]: print(line)
        if len(output_lines) > 15: print("\n[... full content ...]\n")
        for line in output_lines[-5:]: print(line)
        print("---------------------------------------------")

        try:
            with open(output_filename, "w", encoding="utf-8") as f:
                f.write(ai_output)
            log.info(f"SUCCESS: Long-term analysis saved to: {output_filename}")
        except Exception as e:
            log.error(f"Could not save analysis file. Error: {e}")

    except FileNotFoundError as e:
        log.critical(f"FATAL ERROR: Missing file: {e.filename}")
    except Exception as e:
        log.critical(f"An unexpected error occurred: {e}\nFull error details: {e}")

if __name__ == "__main__":
    main()
EOF
echo "[INFO] run_analyzer.py created."

# --- 7. Create run_planner.py (Unchanged but regenerated) ---
echo "[INFO] Creating 'run_planner.py' (config-aware)..."
cat <<'EOF' > run_planner.py
import google.generativeai as genai
import os
import sys
import glob
import logging
import configparser
from datetime import datetime

config = configparser.ConfigParser()
config.read('config.ini')
try:
    API_KEY = config.get('API', 'GEMINI_API_KEY')
    PLANNER_MODEL_NAME = config.get('AI', 'PLANNER_MODEL')
    SYSTEM_PROMPT_FILE = config.get('AI', 'PLANNER_PROMPT_FILE')
    pdf_names = config.get('AI', 'PDF_KNOWLEDGE_BASE', fallback='')
    PDF_KNOWLEDGE_BASE = [name.strip() for name in pdf_names.split(',') if name.strip()]
    WEEKLY_NOTES_FILENAME = config.get('System', 'WEEKLY_NOTES_FILENAME')
    ADHOC_NOTES_FILENAME_TEMPLATE = config.get('System', 'ADHOC_NOTES_FILENAME')
except Exception as e:
    print(f"FATAL ERROR reading config.ini: {e}")
    sys.exit(1)

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] (Planner) %(message)s", handlers=[logging.StreamHandler(sys.stdout)])
log = logging.getLogger(__name__)

def get_real_folder_path(folder_tag):
    if not folder_tag: return '.'
    for item in os.listdir('.'):
        if os.path.isdir(item) and item.lower() == folder_tag.lower():
            return item
    log.warning(f"Could not find a case-insensitive match for folder '{folder_tag}'. Using the tag directly.")
    return folder_tag

def get_real_file_path(base_folder, filename):
    if not filename: return None
    real_folder = get_real_folder_path(base_folder)
    if not real_folder or not os.path.exists(real_folder):
        log.warning(f"Cannot find base folder '{base_folder}' for file '{filename}'")
        return None
    for item in os.listdir(real_folder):
        if not os.path.isdir(item) and item.lower() == filename.lower():
            return os.path.join(real_folder, item)
    return None

def find_latest_report_file(real_day_folder, day_tag):
    log.info(f"Searching for the latest report file in folder: '{real_day_folder}'...")
    try:
        file_pattern = os.path.join(real_day_folder, f"full_class_report-{day_tag}_*.txt")
        report_files = glob.glob(file_pattern)
        if not report_files: return None
        return max(report_files, key=os.path.getmtime)
    except Exception as e:
        log.error(f"Error finding report file for {day_tag}: {e}")
        return None

def main():
    if len(sys.argv) < 3:
        log.critical("FATAL ERROR: Not enough arguments.")
        sys.exit(1)
        
    day_tag = sys.argv[1].lower()
    save_folder_tag = sys.argv[2].lower()
    
    real_day_folder = get_real_folder_path(day_tag)
    real_save_folder = get_real_folder_path(save_folder_tag)
    
    analysis_file_path = os.path.join(real_day_folder, f"long_term_analysis-{day_tag}.txt")
    adhoc_notes_file = ADHOC_NOTES_FILENAME_TEMPLATE.replace('.txt', f'-{day_tag}.txt')
    output_filename_template = os.path.join(real_save_folder, f"lesson_plans_output-{day_tag}")
    
    log.info(f"--- Starting Planner for data in: '{real_day_folder}', saving to: '{real_save_folder}' ---")

    try:
        genai.configure(api_key=API_KEY)

        log.info(f"Loading planner prompt from {SYSTEM_PROMPT_FILE}...")
        with open(SYSTEM_PROMPT_FILE, 'r') as f:
            system_prompt_text = f.read()

        report_file_path = find_latest_report_file(real_day_folder, day_tag)
        if not report_file_path:
            log.critical(f"FATAL ERROR: No '{day_tag}' report file found in {real_day_folder}.")
            return

        uploaded_files = []
        log.info("Uploading Knowledge Base PDFs...")
        for pdf_name in PDF_KNOWLEDGE_BASE:
            real_pdf_path = get_real_file_path('.', pdf_name)
            if real_pdf_path:
                try:
                    log.info(f"  Uploading {real_pdf_path}...")
                    file_obj = genai.upload_file(path=real_pdf_path)
                    uploaded_files.append(file_obj)
                except Exception as e:
                    log.error(f"  Error uploading {real_pdf_path}: {e}")
            else:
                 log.warning(f"  Could not find '{pdf_name}'. Skipping.")

        log.info(f"Uploading today's report: {report_file_path}...")
        report_file_obj = genai.upload_file(path=report_file_path)

        log.info(f"Uploading long-term analysis: {analysis_file_path}...")
        try:
            analysis_file_obj = genai.upload_file(path=analysis_file_path)
        except Exception:
            log.warning(f"  Could not find '{analysis_file_path}'.")
            analysis_file_obj = None

        real_weekly_notes_path = get_real_file_path('.', WEEKLY_NOTES_FILENAME)
        if real_weekly_notes_path:
            log.info(f"Uploading weekly notes: {real_weekly_notes_path}...")
            try:
                weekly_notes_obj = genai.upload_file(path=real_weekly_notes_path)
            except Exception:
                log.warning(f"  Could not find '{real_weekly_notes_path}'.")
                weekly_notes_obj = None
        else:
            log.info("No weekly notes file found.")
            weekly_notes_obj = None

        real_adhoc_notes_path = get_real_file_path('.', adhoc_notes_file)
        if real_adhoc_notes_path:
            log.info(f"Uploading on-the-fly notes: {real_adhoc_notes_path}...")
            try:
                adhoc_notes_obj = genai.upload_file(path=real_adhoc_notes_path)
            except Exception:
                log.warning(f"  Could not find '{real_adhoc_notes_path}'.")
                adhoc_notes_obj = None
        else:
            log.info("No on-the-fly notes file found.")
            adhoc_notes_obj = None

        prompt_parts = [system_prompt_text, report_file_obj]
        if analysis_file_obj: prompt_parts.append(analysis_file_obj)
        if weekly_notes_obj: prompt_parts.append(weekly_notes_obj)
        if adhoc_notes_obj: prompt_parts.append(adhoc_notes_obj)
        prompt_parts.extend(uploaded_files)

        log.info(f"Connecting to Gemini (using {PLANNER_MODEL_NAME}) to generate lesson plans...")
        model = genai.GenerativeModel(model_name=PLANNER_MODEL_NAME)
        response = model.generate_content(prompt_parts)

        log.info("--- AI Lesson Plan Generation Complete (Preview) ---")
        ai_output = response.text
        output_lines = ai_output.splitlines()
        for line in output_lines[:10]: print(line)
        if len(output_lines) > 15: print("\n[... full content ...]\n")
        for line in output_lines[-5:]: print(line)
        print("--------------------------------------------------")

        now = datetime.now()
        filename_timestamp = now.strftime("%Y-%m-%d_%H-%M")
        output_filename = f"{output_filename_template}_{filename_timestamp}.txt"
        
        with open(output_filename, "w", encoding="utf-8") as f:
            f.write(ai_output)
        log.info(f"SUCCESS: Full lesson plans saved to: {output_filename}")

    except FileNotFoundError as e:
        log.critical(f"FATAL ERROR: Missing file: {e.filename}")
    except Exception as e:
        log.critical(f"An unexpected error occurred: {e}\nFull error details: {e}")

if __name__ == "__main__":
    main()
EOF
echo "[INFO] run_planner.py created."

# --- 8. Create main_bot.py (Unchanged but regenerated) ---
echo "[INFO] Creating 'main_bot.py' (config-aware)..."
cat <<'EOF' > main_bot.py
import logging
import os
import sys
import subprocess
import glob
import configparser
from datetime import datetime, time
from telegram import Update, ReplyKeyboardMarkup, ReplyKeyboardRemove
from telegram.ext import (
    Application, CommandHandler, MessageHandler, ConversationHandler,
    ContextTypes, filters
)

# --- 1. CONFIGURATION ---
config = configparser.ConfigParser()
config.read('config.ini')

try:
    BOT_TOKEN = config.get('API', 'TELEGRAM_BOT_TOKEN')
    WEEKLY_NOTES_FILENAME = config.get('System', 'WEEKLY_NOTES_FILENAME')
    ADHOC_NOTES_FILENAME_TEMPLATE = config.get('System', 'ADHOC_NOTES_FILENAME')
    WEEK_FOLDER = config.get('System', 'WEEK_SAVE_FOLDER')
    SESSIONS_FILENAME_LOWER = config.get('System', 'SESSIONS_FILENAME').lower()
    days_str = config.get('System', 'TEACHING_DAYS', fallback='fri,sat,sun')
    ALL_DAYS_LOWER = [day.strip() for day in days_str.split(',') if day.strip()]
except Exception as e:
    print(f"FATAL ERROR reading config.ini: {e}")
    sys.exit(1)

(START_CHOICE, GET_DAY, GET_NOTES_DECISION, RECEIVE_NOTES,
 NOTE_GET_DAY, NOTE_RECEIVE) = range(6)

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] (MainBot) %(message)s", handlers=[logging.StreamHandler(sys.stdout)])
log = logging.getLogger(__name__)

# --- 3. HELPER FUNCTIONS ---
def get_real_folder_path(folder_tag):
    if not folder_tag: return None
    for item in os.listdir('.'):
        if os.path.isdir(item) and item.lower() == folder_tag.lower():
            return item
    log.warning(f"Could not find a case-insensitive match for folder '{folder_tag}'.")
    return folder_tag

def get_populated_days():
    log.info("Checking for populated day folders...")
    populated = []
    try:
        all_items = os.listdir('.')
        day_folders = [d for d in all_items if os.path.isdir(d) and d.lower() in ALL_DAYS_LOWER]
        for folder_name in day_folders:
            found_session = False
            try:
                for file in os.listdir(folder_name):
                    if file.lower() == SESSIONS_FILENAME_LOWER:
                        log.info(f"  Found '{file}' in '{folder_name}'. Adding '{folder_name.lower()}'.")
                        populated.append(folder_name.lower())
                        found_session = True
                        break
            except FileNotFoundError:
                log.warning(f"Folder '{folder_name}' not found during scan.")
                continue
            if not found_session:
                log.warning(f"  Folder '{folder_name}' exists, but no '{SESSIONS_FILENAME_LOWER}' was found.")
    except Exception as e:
        log.error(f"Error while finding populated days: {e}")
    log.info(f"Found populated days: {list(set(populated))}")
    return sorted(list(set(populated)))

def run_script(script_name, *args):
    command = [sys.executable, script_name] + list(args)
    log.info(f"--- Calling: {' '.join(command)} ---")
    try:
        process = subprocess.run(
            command, capture_output=True, text=True, check=True, encoding='utf-8'
        )
        log.info(f"[{script_name} output]:\n{process.stdout}")
        if process.stderr:
            log.warning(f"[{script_name} errors]:\n{process.stderr}")
        log.info(f"--- Finished {script_name} ---")
        return True, process.stdout
    except subprocess.CalledProcessError as e:
        log.critical(f"FATAL ERROR: {script_name} failed.")
        log.critical(f"STDOUT: {e.stdout}\nSTDERR: {e.stderr}")
        return False, e.stderr
    except Exception as e:
        log.critical(f"Unknown error running {script_name}: {e}")
        return False, str(e)

def find_latest_file(pattern):
    try:
        files = glob.glob(pattern, recursive=True) # Search all subdirs
        if not files: return None
        return max(files, key=os.path.getmtime)
    except Exception as e:
        log.error(f"Error finding file for {pattern}: {e}")
        return None

def cleanup_note_files(day_tag):
    log.info(f"Cleaning up note files for {day_tag}...")
    try:
        if os.path.exists(WEEKLY_NOTES_FILENAME):
            os.remove(WEEKLY_NOTES_FILENAME)
            log.info(f"Removed {WEEKLY_NOTES_FILENAME}")
        adhoc_file = ADHOC_NOTES_FILENAME_TEMPLATE.replace('.txt', f'-{day_tag}.txt')
        if os.path.exists(adhoc_file):
            os.remove(adhoc_file)
            log.info(f"Removed {adhoc_file}")
    except Exception as e:
        log.error(f"Error during note file cleanup: {e}")

# --- 4. THE AUTOMATED WORKFLOW ---
async def run_full_workflow(context: ContextTypes.DEFAULT_TYPE, chat_id: int, day_tag: str, save_folder_tag: str, notes_content: str, is_weekly_run: bool):
    log.info(f"Starting workflow for day: {day_tag}, saving to: {save_folder_tag}")
    
    try:
        if not is_weekly_run:
            with open(WEEKLY_NOTES_FILENAME, "w", encoding="utf-8") as f: f.write(notes_content)
            log.info(f"Saved user notes to {WEEKLY_NOTES_FILENAME}")
        else:
            if os.path.exists(WEEKLY_NOTES_FILENAME): os.remove(WEEKLY_NOTES_FILENAME)
    except Exception as e:
        log.error(f"Could not save/clear notes file: {e}")
        await context.bot.send_message(chat_id, f"⚠️ Warning: Could not manage notes file: {e}")

    await context.bot.send_message(chat_id, f"Parsing data for {day_tag.upper()}...")
    success, output = run_script("parser.py", day_tag)
    if not success:
        await context.bot.send_message(chat_id, f"❌ FATAL ERROR: parser.py failed for {day_tag}.\n`{output}`")
        return False

    await context.bot.send_message(chat_id, f"Analyzing long-term data for {day_tag.upper()}...")
    success, output = run_script("run_analyzer.py", day_tag, WEEK_FOLDER)
    if not success:
        await context.bot.send_message(chat_id, f"❌ FATAL ERROR: run_analyzer.py failed for {day_tag}.\n`{output}`")
        return False

    await context.bot.send_message(chat_id, f"Generating lesson plans for {day_tag.upper()}...")
    success, output = run_script("run_planner.py", day_tag, save_folder_tag)
    if not success:
        await context.bot.send_message(chat_id, f"❌ FATAL ERROR: run_planner.py failed for {day_tag}.\n`{output}`")
        return False

    real_save_folder = get_real_folder_path(save_folder_tag)
    if not real_save_folder:
        log.error(f"Could not find save folder {save_folder_tag}")
        return False
        
    final_plan_file = find_latest_file(os.path.join(real_save_folder, f"lesson_plans_output-{day_tag}_*.txt"))
    if final_plan_file:
        log.info(f"Sending final file: {final_plan_file}")
        await context.bot.send_message(chat_id, f"✅ Plans for {day_tag.upper()} are ready!")
        await context.bot.send_document(chat_id, document=open(final_plan_file, 'rb'))
        cleanup_note_files(day_tag)
        return True
    else:
        log.error(f"Could not find lesson plan output file in {real_save_folder}")
        await context.bot.send_message(chat_id, f"❌ ERROR: Planner ran, but I couldn't find the final file for {day_tag}.")
        return False

# --- 5. TELEGRAM BOT HANDLERS ---
async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    log.info("Manual /start command received.")
    reply_keyboard = [["Plan for a Specific Day"], ["Plan for the Whole Week"], ["Skip for now"]]
    await update.message.reply_text(
        "Hi! I'm the Lesson Planner Bot. What would you like to do?",
        reply_markup=ReplyKeyboardMarkup(reply_keyboard, one_time_keyboard=True, resize_keyboard=True),
    )
    return START_CHOICE

async def start_choice(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    text = update.message.text
    populated_days = get_populated_days()
    if not populated_days:
         await update.message.reply_text(f"I couldn't find any populated day folders with a '{SESSIONS_FILENAME_LOWER}' file inside. Please add your files and type /start.", reply_markup=ReplyKeyboardRemove())
         return ConversationHandler.END
    context.user_data['populated_days'] = populated_days
         
    if text == "Plan for a Specific Day":
        reply_keyboard = [[day.upper()] for day in populated_days]
        await update.message.reply_text(
            "Which day are you planning for?",
            reply_markup=ReplyKeyboardMarkup(reply_keyboard, one_time_keyboard=True, resize_keyboard=True),
        )
        return GET_DAY
        
    elif text == "Plan for the Whole Week":
        days_str = ", ".join([d.upper() for d in populated_days])
        await update.message.reply_text(
            f"Okay, generating plans for all populated days: ({days_str}). "
            "This will run without specific notes. This may take a few minutes...",
            reply_markup=ReplyKeyboardRemove(),
        )
        await run_week_workflow(update, context)
        return ConversationHandler.END
        
    else: # "Skip for now"
        await update.message.reply_text("Okay, I'll skip this time. You can run me again with /start.", reply_markup=ReplyKeyboardRemove())
        return ConversationHandler.END

async def get_day(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    day_tag = update.message.text.lower()
    if day_tag not in context.user_data['populated_days']:
        await update.message.reply_text("That's not a valid or populated day. Please use /start to begin again.")
        return ConversationHandler.END
    context.user_data['day_tag'] = day_tag
    reply_keyboard = [["I have notes"], ["No notes"]]
    await update.message.reply_text(
        f"Do you have any notes for {day_tag.upper()}?",
        reply_markup=ReplyKeyboardMarkup(reply_keyboard, one_time_keyboard=True, resize_keyboard=True),
    )
    return GET_NOTES_DECISION

async def get_notes_decision(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    text = update.message.text
    chat_id = update.message.chat_id
    day_tag = context.user_data['day_tag']
    
    if text == "I have notes":
        await update.message.reply_text("Please send me your notes.", reply_markup=ReplyKeyboardRemove())
        return RECEIVE_NOTES
    else:
        await update.message.reply_text("Got it. Running with no notes.", reply_markup=ReplyKeyboardRemove())
        await run_full_workflow(context, chat_id, day_tag, day_tag, f"No specific notes provided for {day_tag}.", is_weekly_run=False)
        return ConversationHandler.END

async def receive_notes(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    user_notes = update.message.text
    chat_id = update.message.chat_id
    day_tag = context.user_data['day_tag']
    log.info(f"Received notes for {day_tag}: {user_notes}")
    await update.message.reply_text("Notes received!", reply_markup=ReplyKeyboardRemove())
    await run_full_workflow(context, chat_id, day_tag, day_tag, user_notes, is_weekly_run=False)
    return ConversationHandler.END

async def run_week_workflow(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.message.chat_id
    all_successful = True
    for day_folder_tag in context.user_data['populated_days']:
        await context.bot.send_message(chat_id, f"--- Starting processing for {day_folder_tag.upper()} ---")
        success = await run_full_workflow(
            context, chat_id, day_folder_tag, WEEK_FOLDER,
            f"No specific notes provided (Weekly run).", is_weekly_run=True
        )
        if not success:
            all_successful = False
            await context.bot.send_message(chat_id, f"--- Processing failed for {day_folder_tag.upper()} ---")
    if all_successful:
        await context.bot.send_message(chat_id, "✅ **All weekly plans are complete!** Files are saved in the 'week' folder.")
    else:
        await context.bot.send_message(chat_id, "⚠️ **Weekly run finished, but one or more days failed.**")

# --- 6. "ON-THE-FLY" /note COMMAND ---
async def note_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    log.info("Manual /note command received.")
    populated_days = get_populated_days()
    if not populated_days:
         await update.message.reply_text("I couldn't find any populated day folders. Please add files first.", reply_markup=ReplyKeyboardRemove())
         return ConversationHandler.END
    context.user_data['populated_days'] = populated_days
    reply_keyboard = [[day.upper()] for day in populated_days]
    await update.message.reply_text(
        "Which day is this note for? (This note will be saved and used in your next plan)",
        reply_markup=ReplyKeyboardMarkup(reply_keyboard, one_time_keyboard=True, resize_keyboard=True),
    )
    return NOTE_GET_DAY

async def note_get_day(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    day_tag = update.message.text.lower()
    if day_tag not in context.user_data['populated_days']:
        await update.message.reply_text("That's not a valid day. Please use /note to begin again.")
        return ConversationHandler.END
    context.user_data['day_tag'] = day_tag
    await update.message.reply_text(f"What is your persistent note for {day_tag.upper()}?", reply_markup=ReplyKeyboardRemove())
    return NOTE_RECEIVE

async def note_receive(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    note_text = update.message.text
    day_tag = context.user_data['day_tag']
    adhoc_file = ADHOC_NOTES_FILENAME_TEMPLATE.replace('.txt', f'-{day_tag}.txt')
    try:
        with open(adhoc_file, "a", encoding="utf-8") as f:
            f.write(f"- {note_text} (Added: {datetime.now().strftime('%Y-%m-%d %H:%M')})\n")
        log.info(f"Appended ad-hoc note to {adhoc_file}")
        await update.message.reply_text(f"✅ Note for {day_tag.upper()} saved! I will use this in the next plan.")
    except Exception as e:
        log.error(f"Failed to save ad-hoc note: {e}")
        await update.message.reply_text(f"Sorry, I failed to save that note. Error: {e}")
    return ConversationHandler.END

# --- 7. NEW /download COMMAND ---
async def download_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    log.info("Manual /download command received.")
    await update.message.reply_text("Starting the Playwright downloader script. This may take a while...")
    
    success, output = run_script("downloader.py") # No args needed
    
    if success:
        await update.message.reply_text("✅ Downloader script finished successfully.")
    else:
        await update.message.reply_text(f"❌ Downloader script failed. Check logs. \n`{output}`")

# --- 8. SCHEDULER ---
async def send_reminder_ping(context: ContextTypes.DEFAULT_TYPE):
    chat_id = context.job.chat_id
    log.info(f"Sending scheduled reminder ping to chat_id: {chat_id}")
    await context.bot.send_message(
        chat_id,
        "🔔 **Reminder!** 🔔\n\nIt's Friday, time to think about lesson plans. "
        "Type `/start` when you're ready to begin, or `/download` to fetch new files."
    )

async def schedule_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.message.chat_id
    jobs = context.job_queue.get_jobs_by_name(str(chat_id))
    for job in jobs:
        job.schedule_removal()
        log.info(f"Removed old job: {job.name}")
    context.job_queue.run_daily(
        send_reminder_ping,
        time=time(hour=9, minute=0), # 9:00 AM GMT
        days=(4,), # 4=Friday
        chat_id=chat_id,
        name=str(chat_id)
    )
    await update.message.reply_text("✅ Success! I will now ping you every Friday at 9:00 AM.")
    log.info(f"Job scheduled for chat_id: {chat_id} on Fridays at 9:00.")

async def cancel_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    await update.message.reply_text("Operation cancelled. Type /start to begin again.", reply_markup=ReplyKeyboardRemove())
    return ConversationHandler.END

# --- 9. MAIN FUNCTION TO RUN THE BOT ---
def main():
    log.info("Starting bot...")
    application = Application.builder().token(BOT_TOKEN).build()
    
    main_conv_handler = ConversationHandler(
        entry_points=[CommandHandler("start", start_command), CommandHandler("run", start_command)],
        states={
            START_CHOICE: [MessageHandler(filters.Regex("^(Plan for a Specific Day|Plan for the Whole Week|Skip for now)$"), start_choice)],
            GET_DAY: [MessageHandler(filters.TEXT & ~filters.COMMAND, get_day)],
            GET_NOTES_DECISION: [MessageHandler(filters.Regex("^(I have notes|No notes)$"), get_notes_decision)],
            RECEIVE_NOTES: [MessageHandler(filters.TEXT & ~filters.COMMAND, receive_notes)],
        },
        fallbacks=[CommandHandler("cancel", cancel_command)],
    )
    note_conv_handler = ConversationHandler(
        entry_points=[CommandHandler("note", note_command)],
        states={
            NOTE_GET_DAY: [MessageHandler(filters.TEXT & ~filters.COMMAND, note_get_day)],
            NOTE_RECEIVE: [MessageHandler(filters.TEXT & ~filters.COMMAND, note_receive)],
        },
        fallbacks=[CommandHandler("cancel", cancel_command)],
    )

    application.add_handler(main_conv_handler)
    application.add_handler(note_conv_handler)
    application.add_handler(CommandHandler("schedule", schedule_command))
    application.add_handler(CommandHandler("download", download_command))

    log.info("Bot is polling for messages...")
    application.run_polling()

if __name__ == "__main__":
    main()
EOF
echo "[INFO] main_bot.py created."

# --- 10. Create AI_ANALYZER_SYSTEM_PROMPT.txt (Unchanged) ---
echo "[INFO] Creating 'AI_ANALYZER_SYSTEM_PROMPT.txt'..."
cat <<'EOF' > AI_ANALYZER_SYSTEM_PROMPT.txt
### ROLE AND PRIMARY DIRECTIVE
You are a **Senior Swim England Coordinator and Teaching Mentor**. Your job is to analyze the provided historical class reports (e.g., from the last 3 Fridays) to find long-term trends.
Your goal is **not** to just list facts. Your goal is to **provide actionable insights** for a junior teacher. You must *hypothesize* why students are stuck and *prioritize* what to work on. Your output will be read by the main "Planner" AI to create a more targeted lesson.
### INPUT FILES
You will be given up to 3 historical report files.
### OUTPUT FORMAT
Your output MUST be a concise markdown file.
1.  Organize your analysis by class, using the class name (e.g., "16:00 Stage 6") as a heading.
2.  Use bullet points *only for students who have a notable trend* (either stuck or progressing well).
3.  **Do not list every student.** Only list those who need special attention.
### CRITICAL ANALYSIS RULES (MANDATORY)
1.  **DO NOT JUST LIST FACTS:**
    * **Weak (Do NOT do this):** `David Patras: Breaststroke is "Needs Practice".`
    * **Strong (Do this):** `David Patras: Has been stuck on "Breaststroke" at "Needs Practice" for 3 weeks. This is a clear **priority**. The issue is likely timing, as his leg kick is marked "Good" in other skills.`
2.  **IDENTIFY BLOCKERS:**
    * **Example:** `Marshall Mills: Shows no progress on "Push and glide" for 2 weeks. This is a **foundational blocker** for all of Stage 1. This must be the primary focus for him.`
3.  **HYPOTHESIZE "WHY":**
    * **Example:** `Multiple students in Stage 8 are "Needs Practice" on Breaststroke and Butterfly kick. This suggests a group-wide weakness in leg power or timing. Recommend a focus on kick-based drills.`
4.  **ACKNOWLEDGE LIMITED DATA (If Applicable):**
    * **Example:** `Note: Analysis is limited to 2 weeks of data. Trends are still emerging.`
EOF
echo "[INFO] AI_ANALYZER_SYSTEM_PROMPT.txt created."

# --- 11. Create AI_LESSON_PLANNER_SYSTEM_PROMPT.txt (Unchanged) ---
echo "[INFO] Creating 'AI_LESSON_PLANNER_SYSTEM_PROMPT.txt'..."
cat <<'EOF' > AI_LESSON_PLANNER_SYSTEM_PROMPT.txt
### ROLE AND PRIMARY DIRECTIVE
You are a specialist AI assistant for a qualified Swim England swimming teacher. Your *only* function is to receive files containing class data and, in response, generate a complete 30-minute lesson plan for *every class* listed in the main report. You must follow the user's workflow and all planning rules with precise, non-negotiable accuracy. Do not deviate.

### 1. CORE KNOWLEDGE BASE
**A. Swim England Frameworks:**
* Pre-School, Learn to Swim (1-7), Aquatic Skills (8-10), Adult, Challenge Awards, School Swimming.
**B. User-Provided Documents (Mandatory Reference):**
You must treat these 5 documents as gospel. You will reference them by these **exact** names:
1.  `SEQRESOURCE.pdf`
2.  `SEQL1ASSISTANT.pdf`
3.  `SEQL2TEACHING.pdf`
4.  `TEACHINGGUIDE.pdf`
5.  `SWIMTEACHV3.pdf`

### 2. USER'S TEACHING METHODOLOGY (MANDATORY)
* **Technique 1: "Motorbike/Pretzel Woggle" (For Stage 1/2)**
* **Technique 2: "Backstroke Legs" (For Backstroke)**
* **Technique 3: "Surface Dive Progression" (For Stage 6+)**
* **Technique 4: "Unconventional Drills" (For All Stages)**

### 3. LESSON PLAN FORMAT (MANDATORY)
All plans are 30 minutes and must follow this structure:
* **Header:** `Class: [Class Name from report] | Method: [e.g., Single-Lane (Top-and-Tailing)]`
* **Focus:** 1-line summary.
* **Swimmers:** Total number of swimmers.
* **Equipment:** List of all equipment.
* **Introduction & Safety (3-5 mins):**
* **Warm-up (5-7 mins):**
* **Main Activity (10-12 mins):** Focused on "Needs Practice".
* **Contrast Activity (5-7 mins):**
* **Cooldown & Fun (3-5 mins):**

### 4. CRITICAL PLANNING RULES (NON-NEGOTIABLE)
1.  **THE SINGLE-LANE CONSTRAINT (Default)**
2.  **THE "TOP-AND-TAILING" METHOD (Primary Strategy)**
3.  **DATA ANALYSIS MANDATE (How to Plan)**
4.  **MANAGE DISTRACTIONS (If Data Provided)**

### 5. USER INTERACTION PROTOCOL (MANDATORY & UPDATED)
This is your exact, step-by-step workflow.

1.  **Acknowledge Input:** You will be given a series of files:
    * **Knowledge Base:** Your 5 PDF knowledge files.
    * **Current Report:** `full_class_report-[day_tag]...txt`. This is the *primary source* for today's plan.
    * **Historical Analysis:** `long_term_analysis-[day_tag].txt`. This provides context.
    * **Teacher Notes (Weekly):** A *potential* file named `weekly_notes.txt`.
    * **Teacher Notes (Ad-Hoc):** A *potential* file named `adhoc_notes-[day_tag].txt`.

2.  **Process All Classes (Looping):**
    * You must read the **`full_class_report...txt`** file and process *every class* in it.

3.  **Generation Steps (Per Class):**
    * For *each* class, generate the following:
    * **a. State the Class:** `--- [Processing: {Class Name}] ---`
    * **b. Provide 'My Analysis':**
        * Generate a section titled `My Analysis`.
        * **Priority 1:** Read `weekly_notes.txt` and `adhoc_notes-[day_tag].txt`. Summarize any instructions (e.g., "Note: Marshall is on holiday and will be excluded.").
        * **Priority 2:** Consult `long_term_analysis.txt`. Summarize key trends (e.g., "Note: John has been stuck on Breaststroke for 3 weeks.").
        * **Priority 3:** Analyze the *current report*. Identify ability tiers and *today's* primary skill gaps.
        * State the planning method (e.g., "Planning Method: Top-and-Tailing").
    * **c. Generate the Lesson Plan:**
        * Immediately following your analysis, generate the complete 30-minute lesson plan.
        * **This plan MUST be based on the *current report* but *optimized* using the `long_term_analysis.txt` and *must obey all* instructions from both notes files.**

4.  **Separation:** Use `---` to separate each lesson plan.
EOF
echo "[INFO] AI_LESSON_PLANNER_SYSTEM_PROMPT.txt created."

# --- 11. Final Instructions ---
echo ""
echo "✅✅✅ SETUP COMPLETE! ✅✅✅"
echo ""
echo "All scripts have been replaced with new config-aware versions."
echo "The new '/note' and '/download' commands are now available in 'main_bot.py'."
echo "The downloader will now save .mhtml files, and the parser will read them."
echo ""
echo "--- YOUR 3-STEP STARTUP ---"
echo ""
echo "1. Double-check 'config.ini' to ensure your login details are correct."
echo ""
echo "2. Run the bot:"
echo "   python main_bot.py"
echo ""
echo "3. Go to Telegram and send your bot the /schedule command."
echo "   (You can also send /start, /note, or /download at any time.)"
echo ""
