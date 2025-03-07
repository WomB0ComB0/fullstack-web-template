# spell: ignore Rofrano jsonify restx dbname
"""
People Service with Swagger

Paths:
------
GET / - Displays a UI for Selenium testing
"""

import secrets
from functools import wraps
from flask import request
from flask import current_app as app  # Import Flask application
from flask_restx import Resource, fields, reqparse, inputs
from service.common import status  # HTTP Status Codes
from service.models import Person
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
    "Person",
    {
        "name": fields.String(required=True, description="The name of the Person"),
        "email": fields.String(required=True, description="The email address of the Person"),
        "phone": fields.String(required=False, description="The phone number of the Person"),
        "address": fields.String(required=False, description="The address of the Person"),
        "active": fields.Boolean(required=False, description="Is the Person active?"),
        "date_joined": fields.Date(required=False, description="The date the Person joined"),
    },
)

person_model = api.inherit(
    "PersonModel",
    create_model,
    {
        "id": fields.Integer(readOnly=True, description="The unique id assigned internally by service"),
    },
)

# query string arguments
person_args = reqparse.RequestParser()
person_args.add_argument("name", type=str, location="args", required=False, help="List People by name")
person_args.add_argument("email", type=str, location="args", required=False, help="List Person by email")
person_args.add_argument("active", type=inputs.boolean, location="args", required=False, help="List People by activity status")


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
    """Removes all People from the database"""
    Person.remove_all()
