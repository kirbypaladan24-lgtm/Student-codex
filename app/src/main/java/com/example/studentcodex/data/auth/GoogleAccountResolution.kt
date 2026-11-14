package com.example.studentcodex.data.auth

import android.accounts.AccountManager
import android.app.Activity
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import com.google.android.gms.common.AccountPicker
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Shows the SYSTEM account chooser and returns the picked account's
 * email, or null when the student dismissed it.
 *
 * This chooser is THE Google account choice for every Classroom
 * authorization in the app (import, connect, re-sync): the student picks
 * the account explicitly, so the roster that gets imported can never be
 * silently guessed. Unlike Google's own authorization sheets — which hide
 * accounts that cannot complete their flow (a managed Workspace account
 * behind a device-policy wall, for example) — this chooser is
 * AccountManager-backed and lists EVERY Google account on the device,
 * plus an Add-account row, so a device with no Google account at all is
 * covered too. [description] is the subtitle shown under the chooser's
 * title.
 */
suspend fun awaitGoogleAccountChoice(activity: Activity?, description: String?): String? {
    val host = activity as? ComponentActivity ?: return null
    val chosen = CompletableDeferred<ActivityResult?>()
    val launcher = host.activityResultRegistry.register(
        ACCOUNT_PICKER_KEY,
        ActivityResultContracts.StartActivityForResult(),
    ) { result -> chosen.complete(result) }
    return try {
        val intent = AccountPicker.newChooseAccountIntent(
            /* selectedAccount = */ null,
            /* allowableAccounts = */ null,
            /* allowableAccountTypes = */ arrayOf(GOOGLE_ACCOUNT_TYPE),
            /* alwaysPromptForAccount = */ true,
            /* descriptionOverride = */ description,
            /* addAccountAuthTokenType = */ null,
            /* addAccountRequiredFeatures = */ null,
            /* addAccountOptions = */ null,
        )
        launcher.launch(intent)
        val result = withTimeoutOrNull(PICKER_TIMEOUT_MS) { chosen.await() }
        result
            ?.takeIf { it.resultCode == Activity.RESULT_OK }
            ?.data
            ?.getStringExtra(AccountManager.KEY_ACCOUNT_NAME)
            ?.takeIf { it.isNotBlank() }
    } finally {
        launcher.unregister()
    }
}

private const val GOOGLE_ACCOUNT_TYPE = "com.google"
private const val ACCOUNT_PICKER_KEY = "studentcodex-classroom-account-picker"
private const val PICKER_TIMEOUT_MS = 180_000L
