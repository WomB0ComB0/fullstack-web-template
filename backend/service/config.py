"""
Global Configuration for Application
"""

import os
import logging

LOGGING_LEVEL = logging.INFO

# Get configuration from environment
# psycopg2 connection string format: postgresql://username:password@host:port/dbname
DATABASE_URI = os.getenv("DATABASE_URI", "postgresql://postgres:postgres@postgres:5432/people")

# Secret for session management
SECRET_KEY = os.getenv("SECRET_KEY", "sup3r-s3cr3t-for-dev")

# See if an API Key has been set for security
API_KEY = os.getenv("API_KEY")

# Turn off helpful error messages that interfere with REST API messages
ERROR_404_HELP = False
