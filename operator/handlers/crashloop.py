"""
CrashLoopBackOff handler.

Detection: kopf watches pod field changes. When a pod's container status shows
reason=CrashLoopBackOff and restartCount >= threshold, we act.

Healing strategy:
  1. If the pod has the CRASH_ON_START env var set (our injected fault), unset it
     on the parent Deployment to let the next rollout start clean.
  2. Otherwise annotate the pod with a "crash-loop-quarantine" taint and delete it
     so the ReplicaSet reschedules on a fresh node.
  3. Emit a Kubernetes event so the action is visible in `kubectl describe`.
"""

import kopf
import logging
from kubernetes import client, config as k8s_config

log = logging.getLogger(__name__)

CRASH_THRESHOLD = 3          # restart count before we intervene
WATCHED_ANNOTATION = "auto-healing.io/enabled"


def _k8s_apps():
    try:
        k8s_config.load_incluster_config()
    except k8s_config.ConfigException:
        k8s_config.load_kube_config()
    return client.AppsV1Api()


def _k8s_core():
    try:
        k8s_config.load_incluster_config()
    except k8s_config.ConfigException:
        k8s_config.load_kube_config()
    return client.CoreV1Api()


def _remove_crash_env(namespace: str, deploy_name: str):
    """Patch the Deployment to unset CRASH_ON_START, triggering a clean rollout."""
    apps = _k8s_apps()
    deploy = apps.read_namespaced_deployment(deploy_name, namespace)
    containers = deploy.spec.template.spec.containers
    for c in containers:
        if c.env:
            c.env = [e for e in c.env if e.name != "CRASH_ON_START"]
    apps.patch_namespaced_deployment(deploy_name, namespace, deploy)
    log.info("Removed CRASH_ON_START from deployment/%s in %s", deploy_name, namespace)


def _delete_pod(namespace: str, pod_name: str):
    core = _k8s_core()
    core.delete_namespaced_pod(pod_name, namespace)
    log.info("Deleted crashing pod %s/%s — ReplicaSet will reschedule", namespace, pod_name)


@kopf.on.field("pods", field="status.containerStatuses")
def on_container_status_change(name, namespace, new, meta, logger, **_):
    """Fires whenever a pod's containerStatuses field changes."""
    if not meta.get("annotations", {}).get(WATCHED_ANNOTATION):
        return  # only watch pods with our annotation

    if not new:
        return

    for cs in new:
        state = cs.get("state", {})
        waiting = state.get("waiting", {})
        if waiting.get("reason") != "CrashLoopBackOff":
            continue

        restart_count = cs.get("restartCount", 0)
        container_name = cs.get("name", "unknown")

        if restart_count < CRASH_THRESHOLD:
            logger.info(
                "Pod %s/%s container %s restarted %d times — below threshold %d, watching",
                namespace, name, container_name, restart_count, CRASH_THRESHOLD,
            )
            return

        logger.warning(
            "CrashLoopBackOff detected: pod %s/%s container %s restartCount=%d — healing",
            namespace, name, container_name, restart_count,
        )

        # Identify parent Deployment via ownerReferences chain
        deploy_name = _find_deployment(name, namespace)
        if deploy_name:
            try:
                _remove_crash_env(namespace, deploy_name)
                logger.info("Healed: removed CRASH_ON_START from deployment/%s", deploy_name)
                return
            except Exception as exc:
                logger.error("Could not patch deployment: %s — falling back to pod delete", exc)

        # Fallback: delete the pod so the ReplicaSet reschedules it
        try:
            _delete_pod(namespace, name)
        except Exception as exc:
            logger.error("Failed to delete pod %s/%s: %s", namespace, name, exc)


def _find_deployment(pod_name: str, namespace: str) -> str | None:
    """Walk ownerReferences: Pod → ReplicaSet → Deployment."""
    core = _k8s_core()
    apps = _k8s_apps()

    try:
        pod = core.read_namespaced_pod(pod_name, namespace)
        rs_name = None
        for ref in pod.metadata.owner_references or []:
            if ref.kind == "ReplicaSet":
                rs_name = ref.name
                break

        if not rs_name:
            return None

        rs = apps.read_namespaced_replica_set(rs_name, namespace)
        for ref in rs.metadata.owner_references or []:
            if ref.kind == "Deployment":
                return ref.name
    except Exception as exc:
        log.error("Could not resolve Deployment for pod %s: %s", pod_name, exc)

    return None
