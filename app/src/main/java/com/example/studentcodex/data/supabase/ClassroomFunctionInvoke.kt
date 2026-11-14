package com.example.studentcodex.data.supabase

import io.github.jan.supabase.functions.Functions
import io.ktor.client.plugins.timeout
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.append
import io.ktor.http.headers
import kotlinx.serialization.json.JsonObject

/**
 * Invokes a Google Classroom Edge Function with an EXTENDED request
 * timeout.
 *
 * Why this exists: supabase-kt 3.6.0 installs Ktor's HttpTimeout with a
 * 10-second default requestTimeout, and the OkHttp engine's socket read
 * timeout defaults to 10 seconds too. A Classroom import legitimately
 * runs longer than that once a student has several matched classes —
 * the function walks every course's coursework and announcements — so
 * the manual sync died with "Request timeout has expired ...
 * request_timeout=10000 ms" (Ktor's HttpRequestTimeoutException).
 *
 * These calls opt into a 120-second ceiling — under Supabase's ~150s
 * edge-function wall clock — while every other Supabase request (auth,
 * postgrest, storage) keeps the snappy library default.
 */
internal suspend fun Functions.invokeClassroomFunction(
    function: String,
    body: JsonObject,
): HttpResponse = invoke(function) {
    timeout {
        // Whole-request ceiling (Ktor cancels the call after this).
        requestTimeoutMillis = CLASSROOM_FUNCTION_TIMEOUT_MS
        // The OkHttp engine maps socketTimeoutMillis onto its READ
        // timeout; without this the engine's own 10s default would cut
        // the call while the function is still working.
        socketTimeoutMillis = CLASSROOM_FUNCTION_TIMEOUT_MS
        // Keep the TCP/TLS handshake bounded, just a little generous.
        connectTimeoutMillis = 15_000
    }
    headers {
        append(HttpHeaders.ContentType, ContentType.Application.Json.toString())
    }
    setBody(body.toString())
}

/** Max wall clock for one Classroom Edge Function invocation. */
private const val CLASSROOM_FUNCTION_TIMEOUT_MS = 120_000L
