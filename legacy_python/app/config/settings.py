import configparser
import os
import logging

log = logging.getLogger(__name__)

class Settings:
    def __init__(self, config_file='config.ini'):
        self.config = configparser.ConfigParser()
        if not os.path.exists(config_file):
            log.warning(f"Config file {config_file} not found. Using defaults.")
        else:
            self.config.read(config_file)

        # API
        self.GEMINI_API_KEY = self._get('API', 'GEMINI_API_KEY')
        self.TELEGRAM_BOT_TOKEN = self._get('API', 'TELEGRAM_BOT_TOKEN')

        # AI
        self.ANALYZER_MODEL = self._get('AI', 'ANALYZER_MODEL', 'models/gemini-2.0-flash-lite')
        self.PLANNER_MODEL = self._get('AI', 'PLANNER_MODEL', 'models/gemini-2.0-flash-lite')
        self.ANALYZER_PROMPT_FILE = self._get('AI', 'ANALYZER_PROMPT_FILE', 'AI_ANALYZER_SYSTEM_PROMPT.txt')
        self.PLANNER_PROMPT_FILE = self._get('AI', 'PLANNER_PROMPT_FILE', 'AI_LESSON_PLANNER_SYSTEM_PROMPT.txt')
        
        pdf_names = self._get('AI', 'PDF_KNOWLEDGE_BASE', '')
        self.PDF_KNOWLEDGE_BASE = [name.strip() for name in pdf_names.split(',') if name.strip()]

        # System
        days_str = self._get('System', 'TEACHING_DAYS', 'mon,tue,thu')
        self.TEACHING_DAYS = [day.strip().lower() for day in days_str.split(',') if day.strip()]
        self.WEEK_SAVE_FOLDER = self._get('System', 'WEEK_SAVE_FOLDER', 'week')
        self.SESSIONS_FILENAME = self._get('System', 'SESSIONS_FILENAME', 'sessions.mht')
        self.FILE_RETENTION_DAYS = self._get_int('System', 'FILE_RETENTION_DAYS', 64)
        self.HISTORICAL_FILE_COUNT = self._get_int('System', 'HISTORICAL_FILE_COUNT', 3)
        self.WEEKLY_NOTES_FILENAME = self._get('System', 'WEEKLY_NOTES_FILENAME', 'weekly_notes.txt')
        self.ADHOC_NOTES_FILENAME_TEMPLATE = self._get('System', 'ADHOC_NOTES_FILENAME', 'adhoc_notes.txt')
        
        # Playwright
        self.PORTAL_URL = self._get('Playwright', 'PORTAL_URL', '')
        self.PORTAL_USERNAME = self._get('Playwright', 'PORTAL_USERNAME', '')
        self.PORTAL_PASSWORD = self._get('Playwright', 'PORTAL_PASSWORD', '')

    def _get(self, section, key, fallback=None):
        try:
            return self.config.get(section, key, fallback=fallback)
        except (configparser.NoSectionError, configparser.NoOptionError):
            return fallback

    def _get_int(self, section, key, fallback=0):
        try:
            return self.config.getint(section, key, fallback=fallback)
        except (configparser.NoSectionError, configparser.NoOptionError, ValueError):
            return fallback

# Global instance
settings = Settings()
