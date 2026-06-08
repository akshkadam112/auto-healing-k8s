import kopf
import logging

from handlers import crashloop, oomkill, rollout  # noqa: F401 — registers handlers via decorators

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


@kopf.on.startup()
def startup(logger, **_):
    logger.info("Auto-healing operator started — watching crashloop, oomkill, stuck rollout")
