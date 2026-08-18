"""In-memory chat job registry.

An agent turn can run for several minutes (Genie polling plus Code Interpreter),
which is longer than the 230 second request limit on Azure App Service. Chat is
therefore started as a background job and the client polls for the result.

The store is per-process, so the API must run with a single worker.
"""

from __future__ import annotations

import logging
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Callable, Literal

logger = logging.getLogger(__name__)

JobStatus = Literal["running", "completed", "failed"]

JOB_TTL_SECONDS = 3600
MAX_JOBS = 200


@dataclass
class ChatJob:
    id: str
    agent_id: str
    status: JobStatus = "running"
    result: object | None = None
    error: str | None = None
    created_at: float = field(default_factory=time.time)
    completed_at: float | None = None


class JobStore:
    def __init__(self, max_workers: int = 4) -> None:
        self._jobs: dict[str, ChatJob] = {}
        self._lock = threading.Lock()
        self._executor = ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="chat")

    def _evict(self) -> None:
        cutoff = time.time() - JOB_TTL_SECONDS
        stale = [job_id for job_id, job in self._jobs.items() if job.created_at < cutoff]
        for job_id in stale:
            self._jobs.pop(job_id, None)
        while len(self._jobs) > MAX_JOBS:
            oldest = min(self._jobs.values(), key=lambda job: job.created_at)
            self._jobs.pop(oldest.id, None)

    def submit(self, agent_id: str, work: Callable[[], object]) -> ChatJob:
        job = ChatJob(id=uuid.uuid4().hex, agent_id=agent_id)
        with self._lock:
            self._evict()
            self._jobs[job.id] = job

        def run() -> None:
            try:
                result = work()
            except Exception as error:
                logger.exception("Chat job %s failed", job.id)
                with self._lock:
                    job.status = "failed"
                    job.error = str(error)
                    job.completed_at = time.time()
                return
            with self._lock:
                job.result = result
                job.status = "completed"
                job.completed_at = time.time()

        self._executor.submit(run)
        return job

    def get(self, job_id: str) -> ChatJob | None:
        with self._lock:
            return self._jobs.get(job_id)


job_store = JobStore()
