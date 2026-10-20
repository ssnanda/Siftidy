"""Protect the latest passing release while removing old GitHub Actions runs."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prune_workflows import cleanup_candidates  # noqa: E402


def run(number, *, status="completed", conclusion="failure", event="push", name=None):
    return {
        "id": number,
        "name": name or "Siftidy - Build, Release & Maintenance",
        "event": event,
        "status": status,
        "conclusion": conclusion,
        "created_at": f"2026-10-20T{number:02}:00:00Z",
    }


class PruneWorkflowsTest(unittest.TestCase):
    def test_successful_new_release_deletes_every_previous_completed_run(self):
        runs = [run(5, status="in_progress", conclusion=None),
                run(4, conclusion="success"), run(3),
                run(2, conclusion="success"), run(1)]
        got = cleanup_candidates(runs, current_run_id=5, current_build_passed=True)
        self.assertEqual([r["id"] for r in got], [4, 3, 2, 1])

    def test_failed_new_release_keeps_last_pass(self):
        runs = [run(5, status="in_progress", conclusion=None),
                run(4), run(3, conclusion="success"),
                run(2, conclusion="success"), run(1)]
        got = cleanup_candidates(runs, current_run_id=5, current_build_passed=False)
        self.assertEqual([r["id"] for r in got], [4, 2, 1])

    def test_running_other_workflows_are_never_deleted(self):
        runs = [run(5, status="in_progress", conclusion=None),
                run(4, status="queued", conclusion=None), run(3)]
        got = cleanup_candidates(runs, current_run_id=5, current_build_passed=True)
        self.assertEqual([r["id"] for r in got], [3])

    def test_maintenance_only_success_does_not_supersede_a_build(self):
        runs = [run(5, status="in_progress", conclusion=None),
                run(4, conclusion="success", event="schedule"),
                run(3, conclusion="success"), run(2)]
        got = cleanup_candidates(runs, current_run_id=5, current_build_passed=False)
        self.assertEqual([r["id"] for r in got], [4, 2])

    def test_no_prior_success_still_prunes_completed_failures(self):
        runs = [run(5, status="in_progress", conclusion=None), run(4), run(3)]
        got = cleanup_candidates(runs, current_run_id=5, current_build_passed=False)
        self.assertEqual([r["id"] for r in got], [4, 3])


if __name__ == "__main__":
    unittest.main()