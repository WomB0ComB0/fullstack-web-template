# spell: ignore Rofrano VCAP dbname SQLDB Kubernetes
"""
Base Model that uses Cloudant

You must initialize this class before use by calling initialize().
This class looks for an environment variable called VCAP_SERVICES
to get it's database credentials from. If it cannot find one, it
tries to connect to Cloudant on the localhost. If that fails it looks
for a server name 'cloudant' to connect to.

To use with Docker couchdb database use:
    docker run -d --name couchdb -p 5984:5984 -e COUCHDB_USER=admin -e COUCHDB_PASSWORD=pass couchdb

Docker Note:
    CouchDB uses /opt/couchdb/data to store its data, and is exposed as a volume
    e.g., to use current folder add: -v $(pwd):/opt/couchdb/data
    You can also use Docker volumes like this: -v couchdb_data:/opt/couchdb/data
"""

import os
import json
import logging
from retry import retry
from cloudant.client import Cloudant
from cloudant.query import Query
from cloudant.adapters import Replay429Adapter
from cloudant.database import CloudantDatabase
from requests import HTTPError, ConnectionError  # pylint: disable=redefined-builtin

# get configuration from environment (12-factor)
ADMIN_PARTY = os.getenv("ADMIN_PARTY", "False").lower() == "true"
CLOUDANT_HOST = os.getenv("CLOUDANT_HOST", "localhost")
CLOUDANT_USERNAME = os.getenv("CLOUDANT_USERNAME", "admin")
CLOUDANT_PASSWORD = os.getenv("CLOUDANT_PASSWORD", "pass")

# global variables for retry (must be int)
RETRY_COUNT = int(os.getenv("RETRY_COUNT", "10"))
RETRY_DELAY = int(os.getenv("RETRY_DELAY", "1"))
RETRY_BACKOFF = int(os.getenv("RETRY_BACKOFF", "2"))


class DatabaseConnectionError(Exception):
    """Custom Exception when database connection fails"""


class DataValidationError(Exception):
    """Custom Exception with data validation fails"""

class Base:
    """
    Class that represents a Base model

    This version uses a NoSQL database for persistence
    """

    logger = logging.getLogger(__name__)
    client: Cloudant = None
    database: CloudantDatabase = None

    def __init__(
        self,
        name: str = None,
    ):
        """Constructor"""
        self.id = None  # pylint: disable=invalid-name
        self.name = name

    def __repr__(self):
        return f"<Base {self.name} id=[{self.id}]>"

    @retry(
        HTTPError,
        delay=RETRY_DELAY,
        backoff=RETRY_BACKOFF,
        tries=RETRY_COUNT,
        logger=logger,
    )
    def create(self):
        """
        Creates a new record in the database
        """
        if self.name is None:  # name is the only required field
            raise DataValidationError("name attribute is not set")

        try:
            document = self.database.create_document(self.serialize())
        except HTTPError as err:
            Base.logger.warning("Create failed: %s", err)
            return

        if document.exists():
            self.id = document["_id"]

    @retry(
        HTTPError,
        delay=RETRY_DELAY,
        backoff=RETRY_BACKOFF,
        tries=RETRY_COUNT,
        logger=logger,
    )
    def update(self):
        """Updates a record in the database"""
        try:
            document = self.database[self.id]  # pylint: disable=unsubscriptable-object)
        except KeyError:
            document = None
        if document:
            document.update(self.serialize())
            document.save()

    @retry(
        HTTPError,
        delay=RETRY_DELAY,
        backoff=RETRY_BACKOFF,
        tries=RETRY_COUNT,
        logger=logger,
    )
    def delete(self):
        """Deletes a record from the database"""
        try:
            document = self.database[self.id]  # pylint: disable=unsubscriptable-object)
        except KeyError:
            document = None
        if document:
            document.delete()

    def serialize(self) -> dict:
        """serializes a record into a dictionary"""
        data = {
            "name": self.name
        }
        if self.id:
            data["_id"] = self.id
        return data

    def deserialize(self, data: dict) -> None:
        """deserializes a record by marshalling the data.

        :param data: a Python dictionary representing a record.
        """
        Base.logger.info("deserialize(%s)", data)
        try:
            self.name = data["name"]
        except KeyError as error:
            raise DataValidationError("Invalid record: missing " + error.args[0]) from error
        except TypeError as error:
            raise DataValidationError("Invalid record: body of request contained bad or no data") from error

        # if there is no id and the data has one, assign it
        if not self.id and "_id" in data:
            self.id = data["_id"]

        return self

    ######################################################################
    #  S T A T I C   D A T A B S E   M E T H O D S
    ######################################################################

    @classmethod
    def connect(cls):
        """Connect to the server"""
        cls.client.connect()

    @classmethod
    def disconnect(cls):
        """Disconnect from the server"""
        cls.client.disconnect()

    @classmethod
    @retry(
        HTTPError,
        delay=RETRY_DELAY,
        backoff=RETRY_BACKOFF,
        tries=RETRY_COUNT,
        logger=logger,
    )
    def create_query_index(cls, field_name: str, order: str = "asc"):
        """Creates a new query index for searching"""
        cls.database.create_query_index(
            index_name=field_name, fields=[{field_name: order}]
        )

    @classmethod
    @retry(
        HTTPError,
        delay=RETRY_DELAY,
        backoff=RETRY_BACKOFF,
        tries=RETRY_COUNT,
        logger=logger,
    )
    def remove_all(cls):
        """Removes all documents from the database (use for testing)"""
        for document in cls.database:  # pylint: disable=(not-an-iterable
            document.delete()

    @classmethod
    @retry(
        HTTPError,
        delay=RETRY_DELAY,
        backoff=RETRY_BACKOFF,
        tries=RETRY_COUNT,
        logger=logger,
    )
    def all(cls):
        """Query that returns all records"""
        results = []
        for doc in cls.database:  # pylint: disable=not-an-iterable
            record = Base().deserialize(doc)
            record.id = doc["_id"]
            results.append(record)
        return results

    ######################################################################
    #  F I N D E R   M E T H O D S
    ######################################################################

    @classmethod
    @retry(
        HTTPError,
        delay=RETRY_DELAY,
        backoff=RETRY_BACKOFF,
        tries=RETRY_COUNT,
        logger=logger,
    )
    def find_by(cls, **kwargs):
        """Find records using selector"""
        query = Query(cls.database, selector=kwargs)
        results = []
        for doc in query.result:
            record = Base()
            record.deserialize(doc) 
            results.append(record)
        return results

    @classmethod
    @retry(
        HTTPError,
        delay=RETRY_DELAY,
        backoff=RETRY_BACKOFF,
        tries=RETRY_COUNT,
        logger=logger,
    )
    def find(cls, record_id: str):
        """Query that finds records by their id"""
        try:
            document = cls.database[record_id]  # pylint: disable=unsubscriptable-object
            # Cloudant doesn't delete documents. :( It leaves the _id with no data
            # so we must validate that _id that came back has a valid _rev
            # if this next line throws a KeyError the document was deleted
            _ = document["_rev"]
            return Base().deserialize(document)
        except KeyError:
            return None

    @classmethod
    @retry(
        HTTPError,
        delay=RETRY_DELAY,
        backoff=RETRY_BACKOFF,
        tries=RETRY_COUNT,
        logger=logger,
    )
    def find_by_name(cls, name: str):
        """Query that finds records by their name"""
        return cls.find_by(name=name)

    ############################################################
    #  C L O U D A N T   D A T A B A S E   C O N N E C T I O N
    ############################################################

    @staticmethod
    def __check_for_cloud_foundry_binding():
        """Checks for Cloud Foundry environment"""
        opts = {}
        if "VCAP_SERVICES" in os.environ:
            Base.logger.info("Found Cloud Foundry VCAP_SERVICES bindings")
            vcap_services = json.loads(os.environ["VCAP_SERVICES"])
            # Look for Cloudant in VCAP_SERVICES
            for service in vcap_services:
                if service.startswith("cloudantNoSQLDB"):
                    opts = vcap_services[service][0]["credentials"]
        return opts

    @staticmethod
    def __check_for_kubernetes_binding():
        """Checks for Kubernetes environment"""
        opts = {}
        if "BINDING_CLOUDANT" in os.environ:
            Base.logger.info("Found Kubernetes BINDING_CLOUDANT bindings")
            opts = json.loads(os.environ["BINDING_CLOUDANT"])
        return opts

    @staticmethod
    def __check_for_local_binding():
        """Checks for local environment"""
        Base.logger.info("Looking for local environment bindings")
        opts = {
            "username": CLOUDANT_USERNAME,
            "password": CLOUDANT_PASSWORD,
            "host": CLOUDANT_HOST,
            "port": 5984,
            "url": "http://" + CLOUDANT_HOST + ":5984/",
        }
        return opts

    @staticmethod
    def init_db(dbname: str = "base"):
        """
        Initialized Cloudant database connection
        """
        # See if we are running Cloud Foundry
        opts = Base.__check_for_cloud_foundry_binding()

        # if VCAP_SERVICES isn't found, maybe we are running on Kubernetes?
        if not opts:
            opts = Base.__check_for_kubernetes_binding()

        # If Cloudant not found in VCAP_SERVICES or BINDING_CLOUDANT
        # get it from the CLOUDANT_xxx environment variables
        if not opts:
            opts = Base.__check_for_local_binding()

        if any(k not in opts for k in ("host", "username", "password", "port", "url")):
            raise DatabaseConnectionError(
                "Error - Failed to retrieve options. "
                "Check that app is bound to a Cloudant service."
            )

        Base.logger.info("Cloudant Endpoint: %s", opts["url"])
        try:
            if ADMIN_PARTY:
                Base.logger.info("Running in Admin Party Mode...")
            Base.client = Cloudant(
                opts["username"],
                opts["password"],
                url=opts["url"],
                connect=True,
                auto_renew=True,
                admin_party=ADMIN_PARTY,
                adapter=Replay429Adapter(retries=10, initialBackoff=0.01),
            )

        except ConnectionError as exc:
            raise DatabaseConnectionError("Cloudant service could not be reached") from exc

        # Create database if it doesn't exist
        try:
            Base.database = Base.client[dbname]  # pylint: disable=unsubscriptable-object
        except KeyError:
            # Create a database using an initialized client
            Base.database = Base.client.create_database(dbname)
        # check for success
        if not Base.database.exists():
            raise DatabaseConnectionError(f"Database [{dbname}] could not be obtained")
