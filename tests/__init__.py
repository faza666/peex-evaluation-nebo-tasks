import os

# Point the app at a throwaway database before any test imports it.
# TEST_DATABASE_URL can select another database, e.g. PostgreSQL in CI.
_TEST_DB = os.path.join(os.path.abspath(os.path.dirname(__file__)), "test.db")
os.environ["DATABASE_URL"] = os.environ.get("TEST_DATABASE_URL") or "sqlite:///" + _TEST_DB
