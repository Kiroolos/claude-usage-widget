package com.usage.claudewidget.data

import org.json.JSONObject

/** One usage window (5-hour or 7-day). */
data class Window(
    val utilization: Float,      // percent, 0..100
    val resetsAtEpochMs: Long,   // absolute reset time
)

/**
 * Parsed snapshot of the /usage endpoint.
 *
 * Either window may be absent: some plans only have a weekly limit, in which
 * case the API sends `"five_hour": null` (or omits it entirely).
 */
data class UsageSnapshot(
    val fiveHour: Window?,
    val sevenDay: Window?,
    val fetchedAtEpochMs: Long,
) {
    companion object {
        fun parse(body: String, now: Long): UsageSnapshot {
            val root = JSONObject(body)
            val fiveHour = root.window("five_hour")
            val sevenDay = root.window("seven_day") ?: root.busiestWeekly()
            if (fiveHour == null && sevenDay == null) {
                throw IllegalStateException("no usage windows in response")
            }
            return UsageSnapshot(fiveHour, sevenDay, now)
        }

        /** Null when the key is missing, JSON null, or not an object with a utilization. */
        private fun JSONObject.window(key: String): Window? {
            val o = optJSONObject(key) ?: return null
            if (!o.has("utilization") || o.isNull("utilization")) return null
            val util = o.optDouble("utilization", 0.0).toFloat()
            val reset = if (o.isNull("resets_at")) "" else o.optString("resets_at", "")
            return Window(util, Iso8601.toEpochMs(reset))
        }

        /** No overall weekly window: fall back to the fullest per-model one (seven_day_*). */
        private fun JSONObject.busiestWeekly(): Window? =
            keys().asSequence()
                .filter { it.startsWith("seven_day_") }
                .mapNotNull { window(it) }
                .maxByOrNull { it.utilization }
    }
}
