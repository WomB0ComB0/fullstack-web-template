"""
Error handlers

Handles all of the HTTP Error Codes returning JSON messages
"""

from flask import current_app as app  # Import Flask application
from service import api
from service.models import DataValidationError, DatabaseConnectionError
from . import status


######################################################################
# Special Error Handlers
######################################################################
@api.errorhandler(DataValidationError)
def request_validation_error(error):
    """Handles Value Errors from bad data"""
    message = str(error)
    app.logger.error(message)
    return {
        "status_code": status.HTTP_400_BAD_REQUEST,
        "error": "Bad Request",
        "message": message,
    }, status.HTTP_400_BAD_REQUEST


@api.errorhandler(DatabaseConnectionError)
def database_connection_error(error):
    """Handles Database Errors from connection attempts"""
    message = str(error)
    app.logger.critical(message)
    return {
        "status_code": status.HTTP_503_SERVICE_UNAVAILABLE,
        "error": "Service Unavailable",
        "message": message,
    }, status.HTTP_503_SERVICE_UNAVAILABLE
