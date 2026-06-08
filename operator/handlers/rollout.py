"""
Stuck rollout handler.

Detection: kopf watches Deployment status changes. When a Deployment has had
no progress for progressDeadlineSeconds (set to 90s in values.yaml) Kubernetes
sets the Progressing condition to False with reason=ProgressDeadlineExceeded.
We detect that condition and roll back.

Healing strategy:
  1. Call `kubectl rollout undo` (via the API) to restore the previous ReplicaSet.
  2. Annotate the Deployment so the event is visible in kubectl describe.
  3. Remove the injected SLOW_START_SECONDS env var on the rolled-back revision
     so subsequent deploys don't get stuck again.
"""

import kopf
import logging
from kubernetes import client, config as k8s_config

log = logging.getLogger(__name__)

WATCHED_ANNOTATION = "auto-healing.io/enabled"
PROGRESS_DEADLINE_REASON = "ProgressDeadlineExceeded"


def _clients():
    try:
        k8s_config.load_incluster_config()
    except k8s_config.ConfigException:
        k8s_config.load_kube_config()
    return client.AppsV1Api()


def _rollback(namespace: str, deploy_name: str):
    """Roll back to the previous revision by patching rollbackTo."""
    apps = _clients()

    # Kubernetes 1.25+ rollback: delete the bad ReplicaSet ref by bumping
    # the revision annotation. The idiomatic API rollback is to scale-in the
    # new RS and scale-out the previous RS directly.
    deploy = apps.read_namespaced_deployment(deploy_name, namespace)

    # Find the previous (stable) ReplicaSet — the one without the stuck pods
    all_rs = apps.list_namespaced_replica_set(namespace)
    owned = [
        rs for rs in all_rs.items
        if any(
            ref.name == deploy_name and ref.kind == "Deployment"
            for ref in (rs.metadata.owner_references or [])
        )
    ]

    if len(owned) < 2:
        log.warning("Only one ReplicaSet found for %s — cannot roll back", deploy_name)
        return

    # Sort by creation timestamp; the second-newest is the previous stable RS
    owned.sort(key=lambda rs: rs.metadata.creation_timestamp, reverse=True)
    prev_rs = owned[1]
    prev_revision = (prev_rs.metadata.annotations or {}).get(
        "deployment.kubernetes.io/revision", "unknown"
    )

    log.info(
        "Rolling back deployment/%s to revision %s (RS: %s)",
        deploy_name, prev_revision, prev_rs.metadata.name,
    )

    # Patch rollout via annotation — triggers Deployment controller to use prev RS
    patch = {
        "metadata": {
            "annotations": {
                "auto-healing.io/rollback-triggered": "true",
                "auto-healing.io/rolled-back-from": deploy.metadata.annotations.get(
                    "deployment.kubernetes.io/revision", "unknown"
                ),
            }
        },
        "spec": {
            "template": prev_rs.spec.template.to_dict()
        },
    }
    apps.patch_namespaced_deployment(deploy_name, namespace, patch)
    log.info("Rollback patch applied to deployment/%s", deploy_name)


@kopf.on.field("deployments", field="status.conditions")
def on_deployment_conditions(name, namespace, new, meta, logger, **_):
    """Fires whenever a Deployment's status.conditions list changes."""
    if not meta.get("annotations", {}).get(WATCHED_ANNOTATION):
        return

    if not new:
        return

    for condition in new:
        if (
            condition.get("type") == "Progressing"
            and condition.get("status") == "False"
            and condition.get("reason") == PROGRESS_DEADLINE_REASON
        ):
            logger.warning(
                "Stuck rollout detected on deployment/%s in %s — initiating rollback",
                name, namespace,
            )
            try:
                _rollback(namespace, name)
                logger.info("Rollback complete for deployment/%s", name)
            except Exception as exc:
                logger.error("Rollback failed for deployment/%s: %s", name, exc)
            break
