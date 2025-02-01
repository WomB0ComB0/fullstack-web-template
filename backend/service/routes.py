# spell: ignore Rofrano jsonify restx dbname
"""
Pet Store Service with Swagger

Paths:
------
GET / - Displays a UI for Selenium testing
"""

import secrets
from functools import wraps
from flask import request
from flask import current_app as app  # Import Flask application
from flask_restx import Resource, fields, reqparse, inputs
from service.models import Pet, Gender
from service.common import status  # HTTP Status Codes
from . import api


######################################################################
# Configure the Root route before OpenAPI
######################################################################
@app.route("/")
def index():
    """Index page"""
    return app.send_static_file("index.html")


# Define the model so that the docs reflect what can be sent
create_model = api.model(
    #
)

base_model = api.inherit(
    "BaseModel",
    create_model,
    {
        "_id": fields.String(
            readOnly=True, description="The unique id assigned internally by service"
        ),
    },
)

# query string arguments
base_args = reqparse.RequestParser()
base_args.add_argument(
    "name", type=str, location="args", required=False, help="List Pets by name"
)

######################################################################
# Authorization Decorator
######################################################################
def token_required(func):
    """Decorator to require a token for this endpoint"""

    @wraps(func)
    def decorated(*args, **kwargs):
        token = None
        if "X-Api-Key" in request.headers:
            token = request.headers["X-Api-Key"]

        if app.config.get("API_KEY") and app.config["API_KEY"] == token:
            return func(*args, **kwargs)

        return {"message": "Invalid or missing token"}, 401

    return decorated


######################################################################
# Function to generate a random API key (good for testing)
######################################################################
def generate_apikey():
    """Helper function used when testing API keys"""
    return secrets.token_hex(16)

######################################################################
#  U T I L I T Y   F U N C T I O N S
######################################################################


def abort(error_code: int, message: str):
    """Logs errors before aborting"""
    app.logger.error(message)
    api.abort(error_code, message)


def data_reset():
    """Removes all Pets from the database"""
    Pet.remove_all()
