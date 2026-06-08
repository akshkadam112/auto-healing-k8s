"""
OOMKilled handler.

Detection: container terminated with reason=OOMKilled.

Healing strategy:
  1. Increase the memory limit on the parent Deployment by MEMORY_BUMP_PERCENT.
  2. Remove the MEMORY_HOG_MB env var if it was an injected fault.
  3. Emit a warning event so it's visible in kubectl describe / Grafana.

In production you'd cap the bump and page an on-call engineer; for the demo
we bump once and log clearly so MTTR is measurable.
"""

import kopf
import logging
from kubernetes import client, config as k8s_config

log = logging.getLogger(__name__)

MEMORY_BUMP_PERCENT = 50     # raise limit by 50% on first OOM
WATCHED_ANNOTATION = "auto-healing.io/enabled"


def _clients():
    try:
        k8s_config.load_incluster_config()
    except k8s_config.ConfigException:
        k8s_config.load_kube_config()
    return client.CoreV1Api(), client.AppsV1Api()


def _parse_memory_mi(mem_str: str) -> int:
    """Convert '150Mi' → 150, '1Gi' → 1024."""
    if mem_str.endswith("Mi"):
        return int(mem_str[:-2])
    if mem_str.endswith("Gi"):
        return int(mem_str[:-2]) * 1024
    return int(mem_str) // (1024 * 1024)


def _bump_memory_limit(namespace: str, deploy_name: str):
    _, apps = _clients()
    deploy = apps.read_namespaced_deployment(deploy_name, namespace)

    for c in deploy.spec.template.spec.containers:
        current_limit = c.resources.limits.get("memory", "150Mi")
        current_mi = _parse_memory_mi(current_limit)
        new_mi = int(current_mi * (1 + MEMORY_BUMP_PERCENT / 100))
        c.resources.limits["memory"] = f"{new_mi}Mi"

        # Also remove the injected fault env var if present
        if c.env:
            c.env = [e for e in c.env if e.name != "MEMORY_HOG_MB"]

        log.info(
            "Bumping memory limit for container %s: %dMi → %dMi",
            c.name, current_mi, new_mi,
        )

    apps.patch_namespaced_deployment(deploy_name, namespace, deploy)


@kopf.on.field("pods", field="status.containerStatuses")
def on_oomkill(name, namespace, new, meta, logger, **_):
    """Fires whenever containerStatuses changes — check for OOMKilled."""
    if not meta.get("annotations", {}).get(WATCHED_ANNOTATION):
        return

    if not new:
        return

    for cs in new:
        last_state = cs.get("lastState", {})
        terminated = last_state.get("terminated", {})
        if terminated.get("reason") != "OOMKilled":
            continue

        logger.warning(
            "OOMKilled detected: pod %s/%s container %s — healing",
            namespace, name, cs.get("name", "unknown"),
        )

        deploy_name = _find_deployment(name, namespace)
        if not deploy_name:
            logger.error("Could not find parent Deployment for pod %s — skipping", name)
            return

        try:
            _bump_memory_limit(namespace, deploy_name)
            logger.info("Healed OOMKill: raised memory limit on deployment/%s", deploy_name)
        except Exception as exc:
            logger.error("Failed to bump memory for deployment/%s: %s", deploy_name, exc)


def _find_deployment(pod_name: str, namespace: str) -> str | None:
    core, apps = _clients()
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
