#!/usr/bin/env python3
"""Validate the Socket Firewall Helm chart can render a complete socket.yml.

Runs three checks against the vendored ``socket.defaults.yml`` reference (the
authoritative list of every key the firewall reads):

  A. configOverride passthrough is lossless — rendering with
     ``socket.configOverride = <full reference>`` yields a socket.yml that
     deep-equals the reference (zero dropped keys, the ticket's acceptance
     criterion).
  B. extraConfig merge is lossless — rendering with
     ``socket.extraConfig = <full reference>`` yields a socket.yml whose key
     paths are a superset of the reference (merge drops nothing).
  C. First-class values wire up — the kitchen-sink values render the promoted
     sections (external_registry_cooldown, metadata_filtering knobs, cache
     revalidation, per-action log levels, nginx.resolver).

Usage: python3 tests/validate_config_coverage.py [--helm helm]
Requires: helm on PATH, PyYAML.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("PyYAML is required: pip install pyyaml")

HERE = os.path.dirname(os.path.abspath(__file__))
CHART_DIR = os.path.dirname(HERE)
REFERENCE = os.path.join(HERE, "socket.defaults.yml")
KITCHEN_SINK = os.path.join(HERE, "kitchen-sink.values.yaml")

HELM = "helm"


def render_socket_yml(values_file: str) -> dict:
    """Render the chart with a values file and return the parsed socket.yml."""
    proc = subprocess.run(
        [HELM, "template", "coverage-test", CHART_DIR, "-f", values_file,
         "--show-only", "templates/configmap.yaml"],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"helm template failed:\n{proc.stderr}")
    configmap = yaml.safe_load(proc.stdout)
    return yaml.safe_load(configmap["data"]["socket.yml"])


def render_with(values: dict) -> dict:
    with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as fh:
        yaml.safe_dump(values, fh)
        path = fh.name
    try:
        return render_socket_yml(path)
    finally:
        os.unlink(path)


def leaf_paths(obj, prefix: str = "") -> set[str]:
    """Collect dotted key paths for every leaf; lists use a ``[]`` marker and
    descend into dict items so nested keys (e.g. route/registry fields) count."""
    paths: set[str] = set()
    if isinstance(obj, dict):
        for key, value in obj.items():
            path = f"{prefix}.{key}" if prefix else key
            if isinstance(value, dict):
                paths |= leaf_paths(value, path)
            elif isinstance(value, list):
                paths.add(path)
                for item in value:
                    if isinstance(item, dict):
                        paths |= leaf_paths(item, f"{path}[]")
            else:
                paths.add(path)
    return paths


def diff_paths(want: dict, got: dict) -> list[str]:
    return sorted(leaf_paths(want) - leaf_paths(got))


def check_config_override(reference: dict) -> list[str]:
    rendered = render_with({"socket": {"configOverride": reference}})
    if rendered == reference:
        return []
    # Report the specific dropped/changed paths for a useful failure message.
    errs = [f"configOverride dropped key: {p}" for p in diff_paths(reference, rendered)]
    if not errs:
        errs.append("configOverride round-trip changed values (types/contents differ)")
    return errs


def check_extra_config(reference: dict) -> list[str]:
    rendered = render_with({"socket": {"extraConfig": reference}})
    return [f"extraConfig merge dropped key: {p}" for p in diff_paths(reference, rendered)]


def check_first_class() -> list[str]:
    rendered = render_socket_yml(KITCHEN_SINK)
    got = leaf_paths(rendered)
    expected = {
        "socket.block_log_level", "socket.warn_log_level",
        "socket.monitor_log_level", "socket.ignore_log_level",
        "cache.revalidation_lock_lease_seconds",
        "cache.revalidation_jitter_seconds", "cache.revalidation_async",
        "nginx.resolver", "nginx.resolver_timeout",
        "metadata_filtering.prefetch_enabled", "metadata_filtering.prefetch_ttl",
        "metadata_filtering.max_concurrent",
        "metadata_filtering.package_filter_timeout",
        "metadata_filtering.excluded_ecosystems",
        "metadata_filtering.conda_prefetch_archs",
        "external_registry_cooldown.enabled",
        "external_registry_cooldown.cooldown_period",
        "external_registry_cooldown.registries[].name",
        "external_registry_cooldown.registries[].ecosystem",
        "external_registry_cooldown.private_registry.enabled",
        "external_registry_cooldown.private_registry.source",
        "redis.ssl_server_name",
        "splunk.sourcetype", "splunk.batch_size",
    }
    return [f"first-class key not rendered: {p}" for p in sorted(expected - got)]


def main() -> int:
    global HELM
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--helm", default="helm", help="helm binary (default: helm)")
    args = parser.parse_args()
    HELM = args.helm

    with open(REFERENCE) as fh:
        reference = yaml.safe_load(fh)

    checks = [
        ("A. configOverride passthrough is lossless", check_config_override, (reference,)),
        ("B. extraConfig merge is lossless", check_extra_config, (reference,)),
        ("C. first-class values render", check_first_class, ()),
    ]

    failed = False
    for name, fn, fn_args in checks:
        try:
            errors = fn(*fn_args)
        except Exception as exc:  # noqa: BLE001
            errors = [f"error running check: {exc}"]
        if errors:
            failed = True
            print(f"FAIL  {name}")
            for err in errors:
                print(f"        - {err}")
        else:
            print(f"ok    {name}")

    print()
    if failed:
        print("Config coverage validation FAILED")
        return 1
    print("Config coverage validation PASSED — chart renders a complete socket.yml")
    return 0


if __name__ == "__main__":
    sys.exit(main())
