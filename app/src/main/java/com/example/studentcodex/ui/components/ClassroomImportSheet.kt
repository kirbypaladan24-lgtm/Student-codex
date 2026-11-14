package com.example.studentcodex.ui.components

import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.example.studentcodex.R
import com.example.studentcodex.data.auth.ClassroomAuthorizer
import com.example.studentcodex.data.auth.ClassroomAuthorizationOutcome
import com.example.studentcodex.data.auth.awaitGoogleAccountChoice
import com.example.studentcodex.data.repo.ClassroomCourseOption
import com.example.studentcodex.ui.theme.Spacing
import kotlinx.coroutines.launch

/**
 * State of the "Import from Google Classroom" flow — shared by the
 * sign-up form, the Google profile-completion form and the Settings
 * school sheet. The sheet is visible for every state except [Idle].
 */
sealed interface ClassroomImportUiState {
    /** No import running — the picker sheet is closed. */
    data object Idle : ClassroomImportUiState

    /** The Google consent sheet is on screen. */
    data object Authorizing : ClassroomImportUiState

    /** Consent granted; the ACTIVE course list is loading. */
    data object LoadingCourses : ClassroomImportUiState

    /** The picker: the student ticks the Classroom courses to import. */
    data class Picking(
        val courses: List<ClassroomCourseOption>,
        val selected: Set<String>,
    ) : ClassroomImportUiState

    /** The picked courses are being imported right now. */
    data object Importing : ClassroomImportUiState

    /** The flow failed; [message] is ready to show. */
    data class Failed(val message: String?) : ClassroomImportUiState
}

/**
 * The course picker sheet: a modal bottom sheet over whichever course
 * editor launched the import. Authorization/loading/importing show a
 * spinner; the picking state lists the student's ACTIVE Google Classroom
 * courses as checkable rows; failures show the message with a close
 * button. [onDismiss] maps to every "put it away" gesture (scrim tap,
 * cancel, close) — the ViewModel returns the flow to
 * [ClassroomImportUiState.Idle].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClassroomImportSheet(
    state: ClassroomImportUiState,
    onToggleCourse: (String) -> Unit,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    if (state == ClassroomImportUiState.Idle) return
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Spacing.lg)
                .padding(bottom = Spacing.lg),
        ) {
            Text(
                text = stringResource(R.string.classroom_import_sheet_title),
                style = MaterialTheme.typography.titleMedium,
            )
            Spacer(Modifier.height(Spacing.xs))
            when (state) {
                ClassroomImportUiState.Authorizing -> SheetProgress(
                    stringResource(R.string.classroom_import_connecting),
                )
                ClassroomImportUiState.LoadingCourses -> SheetProgress(
                    stringResource(R.string.classroom_import_loading),
                )
                ClassroomImportUiState.Importing -> SheetProgress(
                    stringResource(R.string.classroom_import_working),
                )
                is ClassroomImportUiState.Picking -> {
                    Text(
                        text = stringResource(R.string.classroom_import_sheet_hint),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(Spacing.md))
                    if (state.courses.isEmpty()) {
                        Text(
                            text = stringResource(R.string.classroom_import_empty),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(320.dp)
                                .verticalScroll(rememberScrollState()),
                        ) {
                            state.courses.forEach { course ->
                                val checked = course.id in state.selected
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable { onToggleCourse(course.id) }
                                        .padding(vertical = Spacing.xs),
                                ) {
                                    Checkbox(
                                        checked = checked,
                                        onCheckedChange = { onToggleCourse(course.id) },
                                    )
                                    Column(modifier = Modifier.padding(start = Spacing.xs)) {
                                        Text(
                                            text = course.name,
                                            style = MaterialTheme.typography.bodyLarge,
                                        )
                                        if (!course.section.isNullOrBlank()) {
                                            Text(
                                                text = stringResource(
                                                    R.string.classroom_import_section_label,
                                                    course.section,
                                                ),
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Spacer(Modifier.height(Spacing.md))
                    Button(
                        onClick = onConfirm,
                        enabled = state.selected.isNotEmpty(),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(stringResource(R.string.classroom_import_confirm))
                    }
                }
                is ClassroomImportUiState.Failed -> {
                    Text(
                        // A raw transport error (HTTP body JSON, stack-ish
                        // text) is diagnostics, not student-facing copy —
                        // anything that is blank or starts with a JSON
                        // object falls back to the friendly line.
                        text = state.message
                            ?.takeIf { it.isNotBlank() && !it.trimStart().startsWith("{") }
                            ?: stringResource(R.string.classroom_import_failed),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error,
                    )
                    Spacer(Modifier.height(Spacing.md))
                    Button(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.classroom_import_close))
                    }
                }
                ClassroomImportUiState.Idle -> Unit
            }
        }
    }
}

/** Spinner + label used by the three progress states of the sheet. */
@Composable
private fun SheetProgress(label: String) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = Spacing.xl),
    ) {
        CircularProgressIndicator(modifier = Modifier.size(24.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * Runs the Google Classroom consent handshake for the import flow and
 * reports it to the ViewModel: [onStart] the moment the Import button is
 * tapped (so the picker sheet can open in its Authorizing state),
 * [onAuthorized] with the minted access token AND the Google account
 * email it was minted for (the ViewModel forwards both, so the server can
 * pin every later sync to the same account), [onCancelled] when the
 * student closes Google's sheet or the chooser (nothing to show), and
 * [onError] with a ready-to-render message for every other failure.
 * Cancelled consent is silent — the picker sheet simply closes.
 *
 * The Google account is an EXPLICIT choice on every surface — the email
 * typed into the sign-up form is deliberately NOT used as a silent pin
 * (it may be a personal address while the Classroom roster lives on a
 * school Workspace account): the account picked earlier in the same
 * screen session is reused without re-asking, otherwise the SYSTEM
 * account chooser opens FIRST and lists every Google account on the
 * device — AccountManager-backed, so managed Workspace accounts Google's
 * own sheets hide appear too — plus an Add-account row. The picked
 * account is then authorized strictly (pinned), so the course list can
 * only ever be that account's roster.
 *
 * The screen (which owns the live activity and the authorizer) calls the
 * returned lambda; the ViewModel never touches Play services.
 */
@Composable
fun rememberClassroomImportLauncher(
    authorizer: ClassroomAuthorizer,
    onStart: () -> Unit,
    onAuthorized: (String, String?) -> Unit,
    onCancelled: () -> Unit,
    onError: (String) -> Unit,
): () -> Unit {
    val activity = LocalActivity.current
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    // The account picked earlier in this screen session: canceling the
    // chooser and tapping Import again must not re-ask which Google
    // account to read from.
    var sessionAccount by remember { mutableStateOf<String?>(null) }
    return {
        onStart()
        scope.launch {
            // Reports one authorization round to the ViewModel; the
            // account email rides along so later syncs can be pinned to
            // the same account, and a pin that names no device account
            // routes to the chooser instead of surfacing an error.
            suspend fun runAuthorization(email: String, onPinUnresolved: suspend () -> Unit) {
                when (val outcome = authorizer.fetchAccessToken(activity, email)) {
                    is ClassroomAuthorizationOutcome.Token ->
                        onAuthorized(outcome.accessToken, email)
                    ClassroomAuthorizationOutcome.Cancelled -> onCancelled()
                    ClassroomAuthorizationOutcome.Declined ->
                        onError(context.getString(R.string.classroom_auth_declined))
                    is ClassroomAuthorizationOutcome.Rejected ->
                        onError(
                            context.getString(R.string.classroom_auth_rejected, outcome.code ?: 0),
                        )
                    is ClassroomAuthorizationOutcome.Error ->
                        onError(
                            context.getString(
                                R.string.classroom_sync_failed,
                                outcome.message ?: "unknown error",
                            ),
                        )
                    // Never returned by fetchAccessToken (interactive flow);
                    // exhaustive for the silent-only outcome the auto-syncer uses.
                    ClassroomAuthorizationOutcome.SilentUnavailable -> onCancelled()
                    // The pinned account left the device mid-flow: behave
                    // like closing the sheet.
                    ClassroomAuthorizationOutcome.PinUnresolved -> onPinUnresolved()
                }
            }

            // The system account chooser: AccountManager-backed, so it
            // lists EVERY Google account on the device - including managed
            // Workspace accounts Google's own pickers sometimes hide behind
            // a device-policy wall.
            suspend fun chooseAndRun() {
                val chosen = awaitGoogleAccountChoice(
                    activity,
                    context.getString(R.string.classroom_account_picker_prompt),
                )
                if (chosen == null) {
                    // Closed the chooser without picking: silent, the same
                    // as closing Google's own consent sheet.
                    onCancelled()
                } else {
                    sessionAccount = chosen
                    runAuthorization(chosen, onPinUnresolved = { chooseAndRun() })
                }
            }

            // Which Google account owns the Classroom roster to import is
            // ALWAYS the student's explicit call: the account picked
            // earlier in this session, or — first time through — the SYSTEM
            // chooser, which lists every Google account on the device.
            // No typed-email pinning, no silent single-account resolution:
            // the student sees and picks the roster they mean to import.
            val cached = sessionAccount
            if (cached == null) {
                chooseAndRun()
            } else {
                runAuthorization(cached, onPinUnresolved = { chooseAndRun() })
            }
        }
    }
}

