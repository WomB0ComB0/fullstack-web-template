# spell: ignore Rofrano restx gunicorn
"""
Microservice module

This module contains the microservice code for
    service
    models
"""
import sys
from flask import Flask
from flask_restx import Api
from service.common import log_handlers
from service import config

# NOTE: Do not change the order of this code
# The Flask app must be created
# BEFORE you import modules that depend on it !!!

# Document the type of authorization required
authorizations = {
    "apikey": {
        "type": "apiKey",
        "in": "header",
        "name": "X-Api-Key"
    }
}

# Will be initialize when app is created
api = None  # pylint: disable=invalid-name


############################################################
# Initialize the Flask instance
############################################################
def create_app():
    """Initialize the core application."""

    # Create the Flask app
    app = Flask(__name__)
    app.config.from_object(config)

    # Turn off strict slashes because it violates best practices
    app.url_map.strict_slashes = False

    ######################################################################
    # Configure Swagger before initializing it
    ######################################################################
    global api
    api = Api(
        app,
        version="1.0.0",
        title="Pet Demo REST API Service",
        description="This is a sample server Pet store server.",
        default="pets",
        default_label="Pet shop operations",
        doc="/apidocs",  # default also could use doc='/apidocs/'
        authorizations=authorizations,
        prefix="/api",
    )

    with app.app_context():
        # Import the routes After the Flask app is created
        # pylint: disable=import-outside-toplevel
        from service import routes, models  # noqa: F401, E402
        from service.common import error_handlers   # pylint: disable=unused-import

        try:
            models.Pet.init_db(app.config["CLOUDANT_DBNAME"])
        except Exception as error:  # pylint: disable=broad-except
            app.logger.critical("%s: Cannot continue", error)
            # gunicorn requires exit code 4 to stop spawning workers when they die
            sys.exit(4)

        # Set up logging for production
        log_handlers.init_logging(app, "gunicorn.error")

        app.logger.info(70 * "*")
        app.logger.info("  P E T   S E R V I C E   R U N N I N G  ".center(70, "*"))
        app.logger.info(70 * "*")

        # If an API Key was not provided, autogenerate one
        if not app.config["API_KEY"]:
            app.config["API_KEY"] = routes.generate_apikey()
            app.logger.info("Missing API Key! Autogenerated: %s", app.config["API_KEY"])

        app.logger.info("Service initialized!")

        return app
