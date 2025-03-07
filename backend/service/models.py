#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# pylint: disable=W0622

"""
Models for People Service

All of the models are stored in this module
"""
import os
import logging
import psycopg2
from psycopg2.extras import RealDictCursor
from datetime import date

logger = logging.getLogger("flask.app")


class DatabaseConnectionError(Exception):
    """Custom Exception when database connection fails"""


class DataValidationError(Exception):
    """Custom Exception with data validation fails"""


class Person:
    """
    Class that represents a Person
    """

    app = None
    conn = None

    def __init__(self, id=None, name="", email="", phone=None, address=None, active=True, date_joined=None):
        """Constructor"""
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.address = address
        self.active = active
        self.date_joined = date_joined

    def __repr__(self):
        return f"<Person {self.name} id=[{self.id}]>"

    def create(self):
        """
        Creates a Person to the database
        """
        logger.info("Creating %s", self.name)

        # Check if required fields are present
        if not self.name or not self.email:
            raise DataValidationError("Name and email are required fields")

        try:
            cursor = Person.conn.cursor()
            cursor.execute(
                """
                INSERT INTO people(name, email, phone, address, active, date_joined)
                VALUES (%s, %s, %s, %s, %s, %s) RETURNING id
                """,
                (self.name, self.email, self.phone, self.address, self.active, self.date_joined),
            )
            self.id = cursor.fetchone()[0]
            Person.conn.commit()
            cursor.close()
        except psycopg2.Error as e:
            Person.conn.rollback()
            logger.error("Database error: %s", e)
            raise DataValidationError(f"Database error: {str(e)}") from e

    def update(self):
        """
        Updates a Person to the database
        """
        logger.info("Saving %s", self.name)
        if not self.id:
            raise DataValidationError("Update called with empty ID field")

        try:
            cursor = Person.conn.cursor()
            cursor.execute(
                """
                UPDATE people
                SET name=%s, email=%s, phone=%s, address=%s, active=%s, date_joined=%s
                WHERE id=%s
                """,
                (self.name, self.email, self.phone, self.address, self.active, self.date_joined, self.id),
            )
            Person.conn.commit()
            cursor.close()
        except psycopg2.Error as e:
            Person.conn.rollback()
            logger.error("Database error: %s", e)
            raise DataValidationError(f"Database error: {str(e)}") from e

    def delete(self):
        """Removes a Person from the data store"""
        logger.info("Deleting %s", self.name)
        try:
            cursor = Person.conn.cursor()
            cursor.execute("DELETE FROM people WHERE id=%s", (self.id,))
            Person.conn.commit()
            cursor.close()
        except psycopg2.Error as e:
            Person.conn.rollback()
            logger.error("Database error: %s", e)
            raise DataValidationError(f"Database error: {str(e)}") from e

    def serialize(self) -> dict:
        """Serializes a Person into a dictionary"""
        return {
            "id": self.id,
            "name": self.name,
            "email": self.email,
            "phone": self.phone,
            "address": self.address,
            "active": self.active,
            "date_joined": self.date_joined.isoformat() if self.date_joined else None,
        }

    def deserialize(self, data: dict):
        """
        Deserializes a Person from a dictionary

        Args:
            data (dict): A dictionary containing the Person data
        """
        try:
            self.name = data["name"]
            self.email = data["email"]
            if "phone" in data:
                self.phone = data["phone"]
            if "address" in data:
                self.address = data["address"]
            if "active" in data:
                self.active = data["active"]
            if "date_joined" in data and data["date_joined"] is not None:
                self.date_joined = (
                    date.fromisoformat(data["date_joined"]) if isinstance(data["date_joined"], str) else data["date_joined"]
                )
        except KeyError as error:
            raise DataValidationError("Invalid Person: missing " + error.args[0]) from error
        except TypeError as error:
            raise DataValidationError("Invalid Person: body of request contained bad or no data") from error
        return self

    @classmethod
    def init_db(cls, app):
        """Initializes the database connection"""
        logger.info("Initializing database connection")
        cls.app = app
        # Get the database URI from the app config
        database_uri = app.config["DATABASE_URI"]

        try:
            cls.conn = psycopg2.connect(database_uri)
            # Create the table if it doesn't exist
            cursor = cls.conn.cursor()
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS people (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(63) NOT NULL,
                    email VARCHAR(120) NOT NULL UNIQUE,
                    phone VARCHAR(32),
                    address VARCHAR(256),
                    active BOOLEAN NOT NULL DEFAULT TRUE,
                    date_joined DATE
                )
                """
            )
            cls.conn.commit()
            cursor.close()
        except psycopg2.Error as e:
            logger.error("Database connection error: %s", e)
            raise DatabaseConnectionError(f"Database connection error: {str(e)}") from e

    @classmethod
    def all(cls):
        """Returns all of the People in the database"""
        logger.info("Processing all People")
        try:
            cursor = cls.conn.cursor(cursor_factory=RealDictCursor)
            cursor.execute("SELECT * FROM people")
            result = cursor.fetchall()
            cursor.close()
            return [cls._dict_to_person(row) for row in result]
        except psycopg2.Error as e:
            logger.error("Database error: %s", e)
            return []

    @classmethod
    def find(cls, person_id):
        """Finds a Person by their ID"""
        logger.info("Processing lookup for id %s ...", person_id)
        try:
            cursor = cls.conn.cursor(cursor_factory=RealDictCursor)
            cursor.execute("SELECT * FROM people WHERE id=%s", (person_id,))
            result = cursor.fetchone()
            cursor.close()
            return cls._dict_to_person(result) if result else None
        except psycopg2.Error as e:
            logger.error("Database error: %s", e)
            return None

    @classmethod
    def find_by_name(cls, name):
        """Returns all People with the given name

        Args:
            name (string): the name of the People you want to match
        """
        logger.info("Processing name query for %s ...", name)
        try:
            cursor = cls.conn.cursor(cursor_factory=RealDictCursor)
            cursor.execute("SELECT * FROM people WHERE name=%s", (name,))
            result = cursor.fetchall()
            cursor.close()
            return [cls._dict_to_person(row) for row in result]
        except psycopg2.Error as e:
            logger.error("Database error: %s", e)
            return []

    @classmethod
    def find_by_email(cls, email):
        """Returns the Person with the given email

        Args:
            email (string): the email of the Person you want to match
        """
        logger.info("Processing email query for %s ...", email)
        try:
            cursor = cls.conn.cursor(cursor_factory=RealDictCursor)
            cursor.execute("SELECT * FROM people WHERE email=%s", (email,))
            result = cursor.fetchone()
            cursor.close()
            return cls._dict_to_person(result) if result else None
        except psycopg2.Error as e:
            logger.error("Database error: %s", e)
            return None

    @classmethod
    def find_by_activity(cls, active=True):
        """Returns all People by their activity status

        Args:
            active (boolean): True for people that are active
        """
        logger.info("Processing active query for %s ...", active)
        try:
            cursor = cls.conn.cursor(cursor_factory=RealDictCursor)
            cursor.execute("SELECT * FROM people WHERE active=%s", (active,))
            result = cursor.fetchall()
            cursor.close()
            return [cls._dict_to_person(row) for row in result]
        except psycopg2.Error as e:
            logger.error("Database error: %s", e)
            return []

    @classmethod
    def remove_all(cls):
        """Removes all people from the database (use for testing)"""
        try:
            cursor = cls.conn.cursor()
            cursor.execute("DELETE FROM people")
            cls.conn.commit()
            cursor.close()
        except psycopg2.Error as e:
            cls.conn.rollback()
            logger.error("Database error: %s", e)

    @classmethod
    def _dict_to_person(cls, row):
        """Converts a dictionary to a Person object"""
        if not row:
            return None
        person = Person()
        person.id = row["id"]
        person.name = row["name"]
        person.email = row["email"]
        person.phone = row["phone"]
        person.address = row["address"]
        person.active = row["active"]
        person.date_joined = row["date_joined"]
        return person
