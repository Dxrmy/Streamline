import re
import os
import glob
import logging
from email import message_from_bytes
from email.policy import default
from datetime import datetime, timedelta
from bs4 import BeautifulSoup 
from app.config.settings import settings

log = logging.getLogger(__name__)

def get_real_folder_path(folder_tag):
    """Refactored helper to find folder case-insensitively."""
    # Safety check: if folder_tag is typically just 'mon', check current dir
    for item in os.listdir('.'):
        if os.path.isdir(item) and item.lower() == folder_tag.lower():
            return item
    log.warning(f"Could not find a case-insensitive match for folder '{folder_tag}'.")
    return folder_tag

def find_insensitive_path(directory, base_filename):
    try:
        if not os.path.exists(directory):
            return None
        base_lower = base_filename.lower()
        for item in os.listdir(directory):
            if item.lower() == base_lower:
                return os.path.join(directory, item)
    except Exception as e:
        log.error(f"Error scanning {directory}: {e}")
        return None
    return None

def get_html_from_mhtml(file_path):
    if not file_path: return None
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
            return None
    except Exception as e:
        log.error(f"Error reading MHTML {file_path}: {e}")
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
        return None
        
    try:
        soup = BeautifulSoup(html_content, 'lxml')
        class_rows = soup.find_all('tr', class_='clickable')
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
        log.error(f"Error parsing percentages: {e}")
        return {}

def parse_skill_objectives(html_content, students_dict):
    try:
        soup = BeautifulSoup(html_content, 'lxml')
        skill_groups = soup.find_all('div', class_='v-list-group')
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
        return students_dict
    except Exception as e:
        log.error(f"Error parsing skills: {e}")
        return students_dict

def format_data_for_ai(class_name, students_data):
    report_lines = [f"# Class Report: {class_name}\n", "## Student Progress Summary\n"]
    if not students_data:
        report_lines.append("No students found in register file.\n")
        return "\n".join(report_lines)
        
    for student_name in sorted(students_data.keys()):
        student = students_data[student_name]
        display_name = student.get('display_name', student_name)
        report_lines.append(f"### {display_name}")
        report_lines.append(f"* **Overall Progress:** {student['overall_progress']}")
        if student['skills']:
            report_lines.append("* **Skill Status:**")
            for skill in student['skills']:
                report_lines.append(f"    * {skill['objective']}: **{skill['status']}**")
        else:
            report_lines.append("* **Skill Status:** No individual skills assessed.")
        report_lines.append("\n")
    return "\n".join(report_lines)

def run_parser(day_tag, session_id):
    log.info(f"--- Running Parser for {day_tag} (Session: {session_id}) ---")
    real_day_folder = get_real_folder_path(day_tag)
    if not os.path.exists(real_day_folder):
        log.error(f"Folder {day_tag} does not exist.")
        return False, "Folder not found"

    # Housekeeping (still good to keep to avoid disk fill up, but session_id solves logical staleness)
    try:
        cutoff = datetime.now() - timedelta(days=settings.FILE_RETENTION_DAYS)
        patterns = [
            os.path.join(real_day_folder, "full_class_report-*.txt"),
            os.path.join(real_day_folder, "lesson_plans_output-*.txt"),
            os.path.join(real_day_folder, "long_term_analysis-*.txt")
        ]
        for pat in patterns:
            for f in glob.glob(pat):
                try:
                    ts = f.split('_')[-2] + "_" + f.split('_')[-1].split('.')[0]
                    fdate = datetime.strptime(ts, "%Y-%m-%d_%H-%M")
                    if fdate < cutoff:
                        os.remove(f)
                        log.info(f"Deleted old file: {f}")
                except: pass
    except Exception as e:
        log.warning(f"Housekeeping error: {e}")

    # Output filename now strictly uses session_id (which should be a timestamp string)
    output_filename = os.path.join(real_day_folder, f"full_class_report-{day_tag}_{session_id}.txt")
    
    sessions_path = find_insensitive_path(real_day_folder, settings.SESSIONS_FILENAME)
    if not sessions_path:
        return False, f"Sessions file {settings.SESSIONS_FILENAME} not found in {real_day_folder}"

    html_class_list = get_html_from_mhtml(sessions_path)
    all_classes = parse_all_classes(html_class_list) if html_class_list else []
    
    if not all_classes:
        return False, "No classes parsed from sessions file"

    final_report_content = []
    
    for class_info in all_classes:
        class_name = class_info['full_name']
        stage_key = class_info['stage_key']
        time_key = class_info['time_key']

        base_reg = f"{time_key}stage{stage_key}register.mhtml"
        base_skill = f"{time_key}stage{stage_key}skill.mhtml"

        reg_path = find_insensitive_path(real_day_folder, base_reg)
        if not reg_path:
            # Fallback to .mht if .mhtml not found (legacy support)
            base_reg_legacy = base_reg.replace('.mhtml', '.mht')
            reg_path = find_insensitive_path(real_day_folder, base_reg_legacy)
        
        # MHTML content
        html_reg = get_html_from_mhtml(reg_path)
        students_data = parse_student_percentages(html_reg) if html_reg else {}

        # Skills
        all_skills_html = []
        skill_path = find_insensitive_path(real_day_folder, base_skill)
        if not skill_path:
             base_skill_legacy = base_skill.replace('.mhtml', '.mht')
             skill_path = find_insensitive_path(real_day_folder, base_skill_legacy)

        if skill_path:
            all_skills_html.append(get_html_from_mhtml(skill_path))
            # Extra skill pages
            for i in range(1, 6):
                suffix = f"{time_key}stage{stage_key}skill-{i}.mhtml"
                p = find_insensitive_path(real_day_folder, suffix)
                if not p:
                     p = find_insensitive_path(real_day_folder, suffix.replace('.mhtml', '.mht'))
                if p:
                    all_skills_html.append(get_html_from_mhtml(p))
                else:
                    break
        
        for html in all_skills_html:
            if html:
                students_data = parse_skill_objectives(html, students_data)

        report_text = format_data_for_ai(class_name, students_data)
        final_report_content.append(report_text)

    if not final_report_content:
        return False, "No report content generated"

    try:
        with open(output_filename, "w", encoding="utf-8") as f:
            f.write("\n\n".join(final_report_content))
        return True, output_filename
    except Exception as e:
        return False, str(e)
