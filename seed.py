import logging

from app import app, db
from app.models import Menu

log = logging.getLogger("seed")


class Seeder:
    def populate_database(self):
        if db.session.execute(db.select(Menu)).first() is None:
            db.session.add(Menu(name="Baked potatoes"))
            db.session.commit()
            log.info("seeded the menu table")
        else:
            log.info("menu table already has data, nothing to seed")


if __name__ == "__main__":
    with app.app_context():
        Seeder().populate_database()
