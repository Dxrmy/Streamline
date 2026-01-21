import sys
import logging
from app.bot.instance import main

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("bot.log")
    ]
)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
