package com.example.studentcodex.data.auth

import android.accounts.Account
import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.google.android.gms.auth.api.identity.AuthorizationClient
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.auth.GoogleAuthException
import com.google.android.gms.auth.GoogleAuthUtil
import com.google.android.gms.auth.UserRecoverableAuthException
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Scope
import com.google.android.gms.tasks.Task
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** Outcome of asking Google for Classroom read authorization. */
sealed interface ClassroomAuthorizationOutcome {

    /** An access token was granted; it authorizes one sync run. */
    data class Token(val accessToken: String) : ClassroomAuthorizationOutcome

    /** The user closed the consent sheet; nothing to do. */
    data object Cancelled : ClassroomAuthorizationOutcome

    /** The sheet finished without a token (user declined the scopes). */
    data object Declined : ClassroomAuthorizationOutcome

    /**
     * Play services refused the request itself: GMS code 13
     * (DEVELOPER_ERROR). The app's package name + SHA-1 signing
     * fingerprint are not registered as an OAuth Android client in the
     * Google Cloud project that has the Classroom API enabled. Fix is
     * developer-side (Google Cloud Console), not on the device.
     */
    data class Rejected(val code: Int?) : ClassroomAuthorizationOutcome

    /** Something else failed; essage] carries diagnostics. */
    data class Error(val message: String?) : ClassroomAuthorizationOutcome

    /**
     * SILENT-ONLY authorization (auto-sync) found scopes that were never
     * granted (or were revoked): a consent sheet would be needed, which
     * automatic background sync must never show. The caller skips the run.
     */
    data object SilentUnavailable : ClassroomAuthorizationOutcome

    /**
     * The pinned email names no Google account signed in on this device:
     * the pinned request fails fast with no sheet ever shown. The caller
     * decides the fallback - the import flow opens the system account
     * picker, the connect card retries without a pin.
     */
    data object PinUnresolved : ClassroomAuthorizationOutcome
}

/** The read-only Classroom scopes the sync needs (student view). */
object ClassroomScopes {
    val READONLY = listOf(
        "https://www.googleapis.com/auth/classroom.courses.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me.readonly",
        "https://www.googleapis.com/auth/classroom.announcements.readonly",
    )
}

/**
 * Boundary around the Google Authorization API so ViewModels stay
 * testable: unit tests substitute a fake, production uses
 * [PlayServicesClassroomAuthorizer].
 */
interface ClassroomAuthorizer {

    /**
     * Shows the Google consent sheet for the read-only Classroom scopes
     * and returns a short-lived access token. [activity] must be a live
     * activity so the sheet can show its UI; nullable keeps the flow
     * testable on the JVM.
     *
     * When [accountEmail] names a Google account that is signed in on
     * this device, the authorization is PINNED to exactly that account —
     * no silent reuse of whichever account happened to grant the scopes
     * earlier. When the email doesn't match any device account the
     * outcome is [ClassroomAuthorizationOutcome.PinUnresolved] and the
     * caller decides the fallback. Null behaves exactly like the
     * account-choice flow of old.
     */
    suspend fun fetchAccessToken(
        activity: Activity?,
        accountEmail: String? = null,
    ): ClassroomAuthorizationOutcome

    /**
     * SILENT-ONLY variant for automatic background sync: returns a token
     * ONLY when the account already granted the scopes — no consent sheet,
     * no UI, nothing interrupting the student. When interaction would be
     * needed (never granted / revoked / expired), the outcome is
     * [ClassroomAuthorizationOutcome.SilentUnavailable] and the caller
     * simply skips that run.
     *
     * When [accountEmail] names the connected Google account (the
     * connection registry's google_email), the silent request is PINNED to
     * exactly that account: a background import must never quietly pull
     * some OTHER account's roster. Any pinned failure (the account left
     * the device, consent is needed, Google refuses) is a SKIP — never a
     * silent fallback to another account's grant. Null keeps the legacy
     * unpinned behavior (Google's own account choice).
     */
    suspend fun fetchSilentAccessToken(
        activity: Activity?,
        accountEmail: String? = null,
    ): ClassroomAuthorizationOutcome
}

/**
 * Google Authorization API (play-services-auth) — the consent sheet that
 * grants the read-only Classroom scopes and mints a short-lived access
 * token. The token is used for exactly one sync run and is never stored
 * (no refresh tokens, no client secret anywhere in the app): each sync
 * re-authorizes, which also means revoking in the Google account settings
 * takes effect immediately.
 *
 * Consent handshake detail: [AuthorizationClient.authorize] only returns
 * the token directly when the account has ALREADY granted the scopes.
 * Otherwise the Task succeeds with hasResolution() and a PendingIntent
 * pointing at Google's consent activity — the app must launch that
 * intent itself and parse the returned Intent with
 * [AuthorizationClient.getAuthorizationResultFromIntent]. Skipping the
 * launch makes every first-time connect look like "Declined" with no
 * sheet ever shown.
 *
 * Account pinning: [fetchAccessToken] accepts an optional Google account
 * email. A pinned request runs the classic GoogleAuthUtil path, which is
 * STRICTLY bound to that account - the Authorization API's setAccount is
 * only a hint, and with an existing grant for another account it returns
 * that grant's token silently, which would import the wrong roster. A pin
 * that cannot resolve comes back as PinUnresolved and the CALLER runs its
 * own fallback (the import launcher shows the system account picker).
 */
class PlayServicesClassroomAuthorizer : ClassroomAuthorizer {

    private val flowMutex = Mutex()

    override suspend fun fetchAccessToken(
        activity: Activity?,
        accountEmail: String?,
    ): ClassroomAuthorizationOutcome {
        val email = accountEmail?.trim()?.takeIf { it.isNotBlank() }
        if (email != null) {
            // A PINNED request runs the classic GoogleAuthUtil path: it is
            // strictly bound to the given account, so it can never
            // silently hand out another account's grant the way the
            // Authorization API's setAccount hint can. A pin that cannot
            // resolve (the email names no account on this device, or the
            // account refuses) comes back as PinUnresolved so the caller
            // can run its own account choice.
            return fetchPinnedAccessToken(activity, email, allowInteractive = true)
        }
        return authorize(activity, allowInteractive = true)
    }

    // The silent path is pinned to the connection registry's google_email
    // when the caller knows it: a background import must never quietly run
    // a DIFFERENT Google account's roster. A pinned silent failure of any
    // kind (account gone, consent needed, refusal) is a SKIP, never a
    // silent answer with another account's grant.
    override suspend fun fetchSilentAccessToken(
        activity: Activity?,
        accountEmail: String?,
    ): ClassroomAuthorizationOutcome {
        val email = accountEmail?.trim()?.takeIf { it.isNotBlank() }
        if (email != null) {
            val pinned = fetchPinnedAccessToken(activity, email, allowInteractive = false)
            return if (pinned is ClassroomAuthorizationOutcome.Token) {
                pinned
            } else {
                ClassroomAuthorizationOutcome.SilentUnavailable
            }
        }
        return authorize(activity, allowInteractive = false)
    }

    /**
     * Shared authorization core for UNPINNED requests (Google picks the
     * account: the granted one, the single signed-in one, or its own
     * chooser). [allowInteractive] decides what happens when Google wants
     * the consent sheet: the manual connect flow LAUNCHES it (first-time
     * grant), the silent auto-sync path REFUSES to and reports
     * [ClassroomAuthorizationOutcome.SilentUnavailable] instead — a
     * background import must never put a Google dialog on screen.
     */
    private suspend fun authorize(
        activity: Activity?,
        allowInteractive: Boolean,
    ): ClassroomAuthorizationOutcome {
        val host = activity
            ?: return ClassroomAuthorizationOutcome.Error(
                "no activity to attach the consent sheet to",
            )
        if (host !is ComponentActivity) {
            return ClassroomAuthorizationOutcome.Error(
                "consent sheet needs a ComponentActivity to receive its result",
            )
        }
        return flowMutex.withLock {
            try {
                val request = AuthorizationRequest.builder()
                    .setRequestedScopes(ClassroomScopes.READONLY.map(::Scope))
                    .build()
                val client = Identity.getAuthorizationClient(host)
                val first = client.authorize(request).awaitResult()
                val token = first.accessToken
                val resolution = first.pendingIntent
                when {
                    !token.isNullOrBlank() -> ClassroomAuthorizationOutcome.Token(token)
                    first.hasResolution() && resolution != null && allowInteractive ->
                        awaitConsentSheet(host, client, resolution)
                    first.hasResolution() && resolution != null ->
                        ClassroomAuthorizationOutcome.SilentUnavailable
                    // No token AND no consent resolution: a decline.
                    else -> ClassroomAuthorizationOutcome.Declined
                }
            } catch (e: ApiException) {
                Log.w(TAG, "Classroom authorization refused (code=${e.statusCode})", e)
                when {
                    e.statusCode == CommonStatusCodes.CANCELED -> ClassroomAuthorizationOutcome.Cancelled
                    e.statusCode == CommonStatusCodes.DEVELOPER_ERROR ->
                        ClassroomAuthorizationOutcome.Rejected(e.statusCode)
                    else -> ClassroomAuthorizationOutcome.Error("Google error code ${e.statusCode}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Classroom authorization failed", e)
                ClassroomAuthorizationOutcome.Error(e.message ?: e.javaClass.simpleName)
            }
        }
    }

    /**
     * Google needs interactive consent: the authorize Task resolved with
     * a PendingIntent to the consent activity. Launch it through the
     * activity's result registry (registrable at tap time — no
     * MainActivity changes needed) and await the sheet's outcome.
     */
    private suspend fun awaitConsentSheet(
        host: ComponentActivity,
        client: AuthorizationClient,
        pendingIntent: PendingIntent,
    ): ClassroomAuthorizationOutcome {
        val sheetResult = CompletableDeferred<ActivityResult?>()
        val launcher = host.activityResultRegistry.register(
            CONSENT_KEY,
            ActivityResultContracts.StartIntentSenderForResult(),
        ) { result -> sheetResult.complete(result) }
        return try {
            launcher.launch(IntentSenderRequest.Builder(pendingIntent.intentSender).build())
            val outcome = withTimeoutOrNull(CONSENT_TIMEOUT_MS) { sheetResult.await() }
            val data = outcome?.data
            when {
                outcome == null -> ClassroomAuthorizationOutcome.Cancelled
                data == null -> ClassroomAuthorizationOutcome.Cancelled
                else -> try {
                    val authorized = client.getAuthorizationResultFromIntent(data)
                    val token = authorized.accessToken
                    if (token.isNullOrBlank()) {
                        ClassroomAuthorizationOutcome.Declined
                    } else {
                        ClassroomAuthorizationOutcome.Token(token)
                    }
                } catch (e: ApiException) {
                    Log.w(TAG, "Classroom consent refused (code=${e.statusCode})", e)
                    when (e.statusCode) {
                        CommonStatusCodes.CANCELED -> ClassroomAuthorizationOutcome.Cancelled
                        CommonStatusCodes.DEVELOPER_ERROR ->
                            ClassroomAuthorizationOutcome.Rejected(e.statusCode)
                        else -> ClassroomAuthorizationOutcome.Error("Google error code ${e.statusCode}")
                    }
                }
            }
        } finally {
            launcher.unregister()
        }
    }

    /**
     * Strictly account-bound authorization for a pinned email via the
     * classic GoogleAuthUtil: the token is requested for EXACTLY that
     * account, so no other account's grant can ever sneak in. getToken
     * blocks on the network, so it runs on IO; a consent-needing account
     * throws a recoverable exception whose intent is launched through
     * the activity's result registry (then the token is retried once)
     * when [allowInteractive] is true — the SILENT background path
     * instead reports [ClassroomAuthorizationOutcome.SilentUnavailable],
     * because auto-sync must never put a Google dialog on screen.
     */
    private suspend fun fetchPinnedAccessToken(
        activity: Activity?,
        email: String,
        allowInteractive: Boolean,
    ): ClassroomAuthorizationOutcome {
        val host = activity
            ?: return ClassroomAuthorizationOutcome.Error(
                "no activity to attach the consent sheet to",
            )
        if (host !is ComponentActivity) {
            return ClassroomAuthorizationOutcome.Error(
                "consent sheet needs a ComponentActivity to receive its result",
            )
        }
        val account = Account(email, GOOGLE_ACCOUNT_TYPE)
        return flowMutex.withLock {
            try {
                val token = withContext(Dispatchers.IO) {
                    GoogleAuthUtil.getToken(host, account, CLASSROOM_SCOPE_STRING)
                }
                ClassroomAuthorizationOutcome.Token(token)
            } catch (e: UserRecoverableAuthException) {
                if (allowInteractive) {
                    awaitRecoverableConsent(host, account, e.intent)
                } else {
                    // The pinned account needs the consent sheet, which
                    // the silent background path must never show: skip.
                    ClassroomAuthorizationOutcome.SilentUnavailable
                }
            } catch (e: GoogleAuthException) {
                // Non-recoverable for THIS account: the email names no
                // account on this device, or the account refuses the
                // app outright. Either way the pin did not resolve.
                Log.w(TAG, "Pinned Classroom authorization refused (${e.message})")
                ClassroomAuthorizationOutcome.PinUnresolved
            } catch (e: IOException) {
                if (e.message.equals(ACCOUNT_NOT_PRESENT, ignoreCase = true)) {
                    // GoogleAuthUtil reports "the email names no account
                    // on this device" as an IOException with exactly this
                    // message - an unresolved pin, so the caller's
                    // system-chooser fallback takes over.
                    ClassroomAuthorizationOutcome.PinUnresolved
                } else {
                    Log.w(TAG, "Pinned Classroom authorization network failure", e)
                    ClassroomAuthorizationOutcome.Error("network error while contacting Google")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Pinned Classroom authorization failed", e)
                ClassroomAuthorizationOutcome.Error(e.message ?: e.javaClass.simpleName)
            }
        }
    }

    /**
     * The pinned account needs interactive consent: GoogleAuthUtil threw
     * a recoverable exception carrying Google's consent intent. Launch it
     * through the registry, then retry the token once - a granted consent
     * mints the token, a dismissed one cancels.
     */
    private suspend fun awaitRecoverableConsent(
        host: ComponentActivity,
        account: Account,
        intent: Intent?,
    ): ClassroomAuthorizationOutcome {
        if (intent == null) {
            return ClassroomAuthorizationOutcome.Error("Google returned no consent intent")
        }
        val sheetResult = CompletableDeferred<ActivityResult?>()
        val launcher = host.activityResultRegistry.register(
            PINNED_CONSENT_KEY,
            ActivityResultContracts.StartActivityForResult(),
        ) { result -> sheetResult.complete(result) }
        return try {
            launcher.launch(intent)
            val outcome = withTimeoutOrNull(CONSENT_TIMEOUT_MS) { sheetResult.await() }
            when (outcome?.resultCode) {
                Activity.RESULT_OK -> try {
                    val token = withContext(Dispatchers.IO) {
                        GoogleAuthUtil.getToken(host, account, CLASSROOM_SCOPE_STRING)
                    }
                    if (token.isNullOrBlank()) {
                        ClassroomAuthorizationOutcome.Declined
                    } else {
                        ClassroomAuthorizationOutcome.Token(token)
                    }
                } catch (e: UserRecoverableAuthException) {
                    // Still recoverable after a "granted" result: the
                    // scopes were not actually granted.
                    ClassroomAuthorizationOutcome.Declined
                } catch (e: GoogleAuthException) {
                    Log.w(TAG, "Pinned Classroom consent refused (${e.message})")
                    ClassroomAuthorizationOutcome.PinUnresolved
                } catch (e: IOException) {
                    if (e.message.equals(ACCOUNT_NOT_PRESENT, ignoreCase = true)) {
                        ClassroomAuthorizationOutcome.PinUnresolved
                    } else {
                        ClassroomAuthorizationOutcome.Error("network error while contacting Google")
                    }
                }
                else -> ClassroomAuthorizationOutcome.Cancelled
            }
        } finally {
            launcher.unregister()
        }
    }

    private companion object {
        private const val TAG = "ClassroomAuth"
        private const val CONSENT_KEY = "studentcodex-classroom-consent"
        private const val PINNED_CONSENT_KEY = "studentcodex-classroom-pinned-consent"
        private const val CONSENT_TIMEOUT_MS = 300_000L

        /** GoogleAuthUtil's "the account is not on this device" marker. */
        private const val ACCOUNT_NOT_PRESENT = "AccountNotPresent"

        /** The Classroom scopes in GoogleAuthUtil's "oauth2:..." form. */
        private val CLASSROOM_SCOPE_STRING =
            "oauth2:" + ClassroomScopes.READONLY.joinToString(" ")

        /** Account type of the Google accounts signed in on the device. */
        private const val GOOGLE_ACCOUNT_TYPE = "com.google"
    }
}

/**
 * Awaits a GMS [Task] in a coroutine without the play-services coroutines
 * artifact: registers the three listeners and resumes the continuation.
 */
private suspend fun <T : Any> Task<T>.awaitResult(): T =
    suspendCancellableCoroutine { continuation ->
        addOnSuccessListener { result ->
            if (continuation.isActive) continuation.resume(result)
        }
        addOnFailureListener { e ->
            if (continuation.isActive) continuation.resumeWithException(e)
        }
        addOnCanceledListener {
            if (continuation.isActive) continuation.cancel()
        }
    }

