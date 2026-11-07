package org.isoron.uhabits.ioskit

import org.isoron.uhabits.core.tasks.Task
import org.isoron.uhabits.core.tasks.TaskRunner
import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine

/**
 * Runs a suspend block to completion on the calling thread. Throws if the block
 * actually suspends (none of the core's database-backed code does).
 */
internal fun <T> runSync(block: suspend () -> T): T {
    var outcome: Result<T>? = null
    block.startCoroutine(
        Continuation(EmptyCoroutineContext) { outcome = it }
    )
    val r = outcome ?: throw IllegalStateException("suspended")
    return r.getOrThrow()
}

/** Executes tasks inline on the calling thread. */
internal class SyncTaskRunner : TaskRunner {
    private val listeners = mutableListOf<TaskRunner.Listener>()

    override fun addListener(listener: TaskRunner.Listener) {
        listeners.add(listener)
    }

    override fun removeListener(listener: TaskRunner.Listener) {
        listeners.remove(listener)
    }

    override fun execute(task: Task) {
        task.onAttached(this)
        listeners.toList().forEach { it.onTaskStarted(task) }
        task.onPreExecute()
        try {
            runSync { task.doInBackground() }
        } finally {
            listeners.toList().forEach { it.onTaskFinished(task) }
        }
        task.onPostExecute()
    }

    override fun publishProgress(task: Task, progress: Int) {
        task.onProgressUpdate(progress)
    }

    override val activeTaskCount: Int get() = 0

    override suspend fun await() {}
}
