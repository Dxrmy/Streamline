import logging
import os
import asyncio
from playwright.async_api import async_playwright
from datetime import datetime, timedelta
from app.config.settings import settings

log = logging.getLogger(__name__)

async def save_as_mhtml(page, file_path):
    try:
        session = await page.context.new_cdp_session(page)
        doc = await session.send('Page.captureSnapshot', { 'format': 'mhtml' })
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(doc['data'])
        await session.detach()
    except Exception as e:
        log.error(f"Failed to save MHTML: {e}")

async def run_downloader():
    log.info("Starting On-Demand Downloader...")
    async with async_playwright() as p:
        # Optimization: Only launch browser when this function is called
        # Close it immediately after.
        browser = await p.chromium.launch(headless=True, args=["--no-sandbox"])
        try:
             # Logic for downloading sessions would go here
             # Ported from original script logic
             pass
        finally:
            await browser.close()
            log.info("Browser closed. RAM freed.")
