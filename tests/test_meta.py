"""Unit and seeded-DAG property tests for .mk/meta.py."""

from __future__ import annotations

import json
import os
import random
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".mk"))
import meta as mk_meta  # noqa: E402


def _make_pkg(
    root: str,
    rel_dir: str,
    name: str,
    *,
    version: str = "0.1.0",
    kinds: list[str] | None = None,
    deps: list[tuple[str, str | None]] | None = None,
    rust_version: str | None = "1.100.0",
    license_id: str | None = "MIT",
    publish: list[str] | None = None,
) -> dict[str, object]:
    pkg_dir = os.path.join(root, rel_dir) if rel_dir != "." else root
    return {
        "id": f"path+file://{pkg_dir}#{name}@{version}",
        "name": name,
        "version": version,
        "manifest_path": os.path.join(pkg_dir, "Cargo.toml"),
        "rust_version": rust_version,
        "license": license_id,
        "publish": publish,
        "targets": [{"kind": kinds if kinds is not None else ["lib"]}],
        "dependencies": [
            {"name": dep_name, "path": dep_path, "source": None if dep_path else "registry"}
            for dep_name, dep_path in (deps or [])
        ],
    }


def _sample_workspace(root: str) -> dict[str, object]:
    core_dir = os.path.join(root, "crates", "core")
    mid_dir = os.path.join(root, "crates", "mid")
    pkgs = [
        _make_pkg(root, "crates/core", "core-x", version="0.1.0", kinds=["lib"], license_id="Apache-2.0"),
        _make_pkg(
            root,
            "crates/mid",
            "mid-x",
            version="0.2.0",
            kinds=["rlib"],
            deps=[("core-x", core_dir)],
            license_id="MIT",
        ),
        _make_pkg(
            root,
            "crates/cli",
            "cli-x",
            version="1.0.0",
            kinds=["bin"],
            deps=[("mid-x", mid_dir)],
            publish=[],
            license_id=None,
        ),
    ]
    return {
        "workspace_members": [pkg["id"] for pkg in pkgs],
        "packages": pkgs,
    }


class TestMetadataQueries(unittest.TestCase):
    def test_workspace_queries_and_sorting(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            ws = _sample_workspace(root)
            self.assertEqual(mk_meta.package_names(ws), ["cli-x", "core-x", "mid-x"])
            self.assertEqual(len(mk_meta.manifest_paths(ws)), 3)
            self.assertTrue(mk_meta.has_lib_target(ws))
            self.assertEqual(mk_meta.first_msrv(ws), "1.100.0")
            self.assertEqual(mk_meta.first_license(ws), "Apache-2.0")
            self.assertTrue(mk_meta.has_stable_version(ws))
            self.assertTrue(mk_meta.has_publishable_package(ws))

    def test_bin_only_pre_1_unpublishable(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            pkg = _make_pkg(
                root,
                ".",
                "only-bin",
                version="0.3.0",
                kinds=["bin"],
                rust_version=None,
                license_id=None,
                publish=[],
            )
            ws = {"workspace_members": [pkg["id"]], "packages": [pkg]}
            self.assertFalse(mk_meta.has_lib_target(ws))
            self.assertEqual(mk_meta.first_msrv(ws), "")
            self.assertEqual(mk_meta.first_license(ws), "")
            self.assertFalse(mk_meta.has_stable_version(ws))
            self.assertFalse(mk_meta.has_publishable_package(ws))

    def test_lib_kinds_include_proc_macro_and_cdylib(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            for kind in ("proc-macro", "cdylib", "dylib", "staticlib"):
                pkg = _make_pkg(root, ".", f"k-{kind}", kinds=[kind])
                ws = {"workspace_members": [pkg["id"]], "packages": [pkg]}
                self.assertTrue(mk_meta.has_lib_target(ws), f"expected {kind} to count as lib")


class TestPackageGraphScoping(unittest.TestCase):
    def test_changed_packages_nested_longest_prefix(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            outer = _make_pkg(root, ".", "outer")
            inner = _make_pkg(root, "crates/inner", "inner")
            ws = {"workspace_members": [outer["id"], inner["id"]], "packages": [outer, inner]}
            self.assertEqual(
                mk_meta.changed_rust_packages(ws, root, ["crates/inner/src/lib.rs"]),
                ["inner"],
            )
            self.assertEqual(
                mk_meta.changed_rust_packages(ws, root, ["src/lib.rs"]),
                ["outer"],
            )
            self.assertEqual(mk_meta.changed_rust_packages(ws, root, []), [])

    def test_affected_transitive_reverse_deps(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            ws = _sample_workspace(root)
            self.assertEqual(
                mk_meta.affected_packages(ws, root, root, ["crates/core/src/lib.rs"]),
                ["cli-x", "core-x", "mid-x"],
            )
            self.assertEqual(
                mk_meta.affected_packages(ws, root, root, ["crates/mid/tests/smoke.rs"]),
                ["cli-x", "mid-x"],
            )
            self.assertEqual(
                mk_meta.affected_packages(ws, root, root, ["crates/cli/src/main.rs"]),
                ["cli-x"],
            )

    def test_affected_triggers_and_ignores(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            ws = _sample_workspace(root)
            for trigger in ("Cargo.toml", "mk", ".mk/core.sh", "mk.local"):
                self.assertEqual(
                    mk_meta.affected_packages(ws, root, root, [trigger]),
                    ["cli-x", "core-x", "mid-x"],
                    f"root trigger {trigger} must affect whole workspace",
                )
            self.assertEqual(
                mk_meta.affected_packages(ws, root, root, ["crates/core/docs/notes.md"]),
                [],
            )
            self.assertEqual(
                mk_meta.affected_packages(ws, root, root, ["crates/core/README.md"]),
                ["cli-x", "core-x", "mid-x"],
            )

    def test_seeded_dag_closure_property(self) -> None:
        rng = random.Random(20261124)
        for trial in range(50):
            with tempfile.TemporaryDirectory() as root:
                count = rng.randint(2, 8)
                pkgs = []
                edges: dict[str, set[str]] = {}
                for i in range(count):
                    name = f"pkg-{i}"
                    deps = []
                    for j in range(i):
                        if rng.random() < 0.4:
                            deps.append((f"pkg-{j}", os.path.join(root, "crates", f"pkg-{j}")))
                            edges.setdefault(f"pkg-{j}", set()).add(name)
                    pkgs.append(_make_pkg(root, f"crates/{name}", name, deps=deps))
                ws = {"workspace_members": [p["id"] for p in pkgs], "packages": pkgs}
                touched = rng.sample([f"pkg-{i}" for i in range(count)], rng.randint(1, count))
                files = [f"crates/{name}/src/lib.rs" for name in touched]
                changed = set(mk_meta.changed_rust_packages(ws, root, files))
                affected = set(mk_meta.affected_packages(ws, root, root, files))
                self.assertEqual(changed, set(touched), f"trial {trial}")
                self.assertTrue(changed.issubset(affected), f"trial {trial}")
                for pkg in list(affected):
                    self.assertTrue(
                        edges.get(pkg, set()).issubset(affected),
                        f"trial {trial}: reverse dep of {pkg} missing",
                    )


class TestShardPlanner(unittest.TestCase):
    def test_compute_shards_boundaries(self) -> None:
        self.assertEqual(mk_meta.compute_shards(0, 150, 4), 0)
        self.assertEqual(mk_meta.compute_shards(1, 150, 4), 1)
        self.assertEqual(mk_meta.compute_shards(5, 2, 4), 3)
        self.assertEqual(mk_meta.compute_shards(5, 1, 2), 2)
        with self.assertRaises(ValueError):
            mk_meta.compute_shards(-1, 10, 2)
        with self.assertRaises(ValueError):
            mk_meta.compute_shards(5, 0, 2)
        with self.assertRaises(ValueError):
            mk_meta.compute_shards(5, 10, 0)

    def test_format_plan_json(self) -> None:
        raw = mk_meta.format_plan_json("full", 5, 1, ["sample-bin", "sample-lib"])
        self.assertEqual(raw, '{"mode":"full","mutants":5,"shards":1,"packages":["sample-bin","sample-lib"]}')
        self.assertEqual(json.loads(raw)["mutants"], 5)


if __name__ == "__main__":
    unittest.main()
