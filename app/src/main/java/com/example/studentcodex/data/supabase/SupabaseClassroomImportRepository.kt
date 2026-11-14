package com.example.studentcodex.data.supabase

import android.util.Log
import com.example.studentcodex.data.repo.ClassroomCourseListResult
import com.example.studentcodex.data.repo.ClassroomCourseOption
import com.example.studentcodex.data.repo.ClassroomImportRepository
import com.example.studentcodex.data.repo.ClassroomImportResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * Google Classroom course IMPORT through the `classroom-import` Edge
 * Function.
 *
 * The session JWT travels in the Authorization header automatically
 * (functions-kt); the Google access token rides in the request body and
 * is used in transit only — never stored. `action: "list"` returns the
 * account's ACTIVE Classroom courses for the picker; `action: "import"`
 * runs the picked ids through the trusted RPC (course link + enrollment).
 * See supabase/functions/classroom-import/index.ts.
 *
 * Both invocations go through [invokeClassroomFunction]'s extended
 * timeout so a cold function instance or a long course list can never
 * trip supabase-kt's 10-second default mid-picker.
 */
class SupabaseClassroomImportRepository(
    private val client: SupabaseClient,
) : ClassroomImportRepository {

    override suspend fun listCourses(googleAccessToken: String): ClassroomCourseListResult = try {
        val response: HttpResponse = client.functions.invokeClassroomFunction(
            function = FUNCTION,
            body = buildJsonObject {
                put("action", "list")
                put("googleAccessToken", googleAccessToken)
            },
        )
        val text = response.bodyAsText()
        Log.i(TAG, "classroom-import list response: " + text.take(600))
        parseList(text)
    } catch (e: Exception) {
        Log.w(TAG, "classroom-import list invocation failed", e)
        ClassroomCourseListResult.Failed(e.message ?: e.javaClass.simpleName)
    }

    override suspend fun importCourses(
        googleAccessToken: String,
        courseIds: List<String>,
        accountEmail: String?,
    ): ClassroomImportResult = try {
        val response: HttpResponse = client.functions.invokeClassroomFunction(
            function = FUNCTION,
            body = buildJsonObject {
                put("action", "import")
                put("googleAccessToken", googleAccessToken)
                put("courseIds", buildJsonArray { courseIds.forEach { add(it) } })
                // Which Google account the token belongs to (when known):
                // the function stamps it on the connection registry so
                // later syncs pin to the same account.
                accountEmail?.let { put("accountEmail", it) }
            },
        )
        val text = response.bodyAsText()
        Log.i(TAG, "classroom-import response: " + text.take(600))
        parseSummary(text)
    } catch (e: Exception) {
        Log.w(TAG, "classroom-import invocation failed", e)
        ClassroomImportResult(status = "failed", error = e.message ?: e.javaClass.simpleName)
    }

    /** Maps the function's course list JSON into the domain result. */
    private fun parseList(text: String): ClassroomCourseListResult = runCatching {
        val obj = Json.parseToJsonElement(text).jsonObject
        val status = obj["status"]?.jsonPrimitive?.content ?: "failed"
        if (status != "ok") {
            return@runCatching ClassroomCourseListResult.Failed(
                obj["message"]?.jsonPrimitive?.content
                    ?: obj["error"]?.jsonPrimitive?.content,
            )
        }
        val courses = obj["courses"]?.jsonArray
            ?.mapNotNull { entry ->
                runCatching {
                    val course = entry.jsonObject
                    ClassroomCourseOption(
                        id = course["id"]?.jsonPrimitive?.content ?: return@runCatching null,
                        name = course["name"]?.jsonPrimitive?.content ?: return@runCatching null,
                        // contentOrNull, NOT .content: a JSON null parses
                        // as JsonNull, which IS a JsonPrimitive whose
                        // .content is the literal STRING "null" — that
                        // string sailed through isNotBlank() and rendered
                        // as "Section null" in the picker (user report).
                        section = course["section"]?.jsonPrimitive?.contentOrNull
                            ?.takeIf { it.isNotBlank() },
                    )
                }.getOrNull()
            }
            ?.filter { it.id.isNotBlank() && it.name.isNotBlank() }
            .orEmpty()
        ClassroomCourseListResult.Courses(courses = courses)
    }.getOrElse {
        ClassroomCourseListResult.Failed("unreadable course list response")
    }

    /** Maps the function's import summary JSON into the domain result. */
    private fun parseSummary(text: String): ClassroomImportResult = runCatching {
        val obj = Json.parseToJsonElement(text).jsonObject

        fun intAt(key: String): Int = obj[key]?.jsonPrimitive?.int ?: 0

        fun nameListAt(key: String): List<String> =
            obj[key]?.jsonArray
                ?.mapNotNull { entry ->
                    runCatching { entry.jsonPrimitive.content }.getOrNull()
                }
                ?.filter { it.isNotBlank() }
                ?: emptyList()

        ClassroomImportResult(
            status = obj["status"]?.jsonPrimitive?.content ?: "failed",
            enrolled = intAt("enrolled"),
            createdCourses = nameListAt("created"),
            linkedCourses = nameListAt("linked"),
            matchedCourses = nameListAt("matched"),
            invalidCourses = nameListAt("invalid"),
            sectionsCreated = intAt("sectionsCreated"),
            error = obj["error"]?.jsonPrimitive?.content,
            message = obj["message"]?.jsonPrimitive?.content,
        )
    }.getOrElse {
        ClassroomImportResult(status = "failed", error = "unreadable import response")
    }

    private companion object {
        private const val TAG = "ClassroomImport"
        private const val FUNCTION = "classroom-import"
    }
}
