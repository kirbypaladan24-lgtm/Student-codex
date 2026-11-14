package com.example.studentcodex.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.studentcodex.R
import com.example.studentcodex.domain.model.Activity
import com.example.studentcodex.domain.model.ActivitySource
import com.example.studentcodex.domain.model.ActivityType
import com.example.studentcodex.domain.model.VerificationStatus
import com.example.studentcodex.ui.theme.Spacing
import java.time.Instant

/**
 * FULL-CONTENT sheet for one school work (Beacon row or Home upcoming row).
 *
 * Tapping a row used to be a dead end: the list rows are deliberately dense
 * (title + provenance chip + one metadata line + due block) so long notes
 * never fit. This sheet is where the whole record opens up: the full title,
 * the full course name, every deadline/effort/verification fact, and the
 * complete notes. Only the notes can still be huge (Google Classroom
 * instructions run to many paragraphs), so they start clamped to
 * [NOTES_COLLAPSED_LINES] with a See more / See less toggle that appears
 * only when the text actually overflows - short notes never show a button.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityDetailSheet(
    activity: Activity,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        key(activity.id) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = Spacing.lg)
                    .padding(bottom = Spacing.xl),
                verticalArrangement = Arrangement.spacedBy(Spacing.md),
            ) {
                // Header: type icon + the FULL title (no line cap - the row
                // already truncated it, the sheet is where it unwraps).
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ActivityTypeIcon(type = activity.type)
                    Spacer(Modifier.width(Spacing.md))
                    Text(
                        text = activity.title,
                        style = MaterialTheme.typography.titleLarge,
                    )
                }

                // Provenance chip + verification chip: same visual language
                // as the list rows, so the sheet reads as the same record.
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
                ) {
                    if (activity.source == ActivitySource.GOOGLE_CLASSROOM) {
                        ClassroomBadge()
                    } else {
                        ManualBadge()
                    }
                    VerificationChip(verification = activity.verification)
                }

                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                // Fact block. Course carries the FULL name (rows only ever
                // showed the code); the due value keeps its urgency color.
                DetailRow(
                    label = stringResource(R.string.activity_detail_type_label),
                    value = typeLabel(activity.type),
                )
                activity.course?.let { course ->
                    DetailRow(
                        label = stringResource(R.string.activity_detail_course_label),
                        value = if (course.title.isBlank()) {
                            course.code
                        } else {
                            "${course.code} - ${course.title}"
                        },
                    )
                }
                val dueAt = activity.dueAt
                val dueValue = if (dueAt == null) {
                    stringResource(R.string.no_deadline)
                } else {
                    "${dueLabel(dueAt)}, ${timeLabel(dueAt)}"
                }
                val dueColor = if (dueAt == null) {
                    null
                } else if (!dueAt.isAfter(Instant.now())) {
                    MaterialTheme.colorScheme.error
                } else {
                    MaterialTheme.colorScheme.primary
                }
                DetailRow(
                    label = stringResource(R.string.activity_detail_due_label),
                    value = dueValue,
                    valueColor = dueColor,
                )
                // Upload time: the stamp the Beacon's LIFO order runs on.
                activity.createdAt?.let { uploaded ->
                    DetailRow(
                        label = stringResource(R.string.activity_detail_uploaded_label),
                        value = uploadedStamp(uploaded),
                    )
                }
                activity.effortMinutes?.let { effort ->
                    DetailRow(
                        label = stringResource(R.string.activity_detail_effort_label),
                        value = stringResource(R.string.effort_minutes, effort),
                    )
                }

                // The reason this sheet exists: the notes, in full.
                if (activity.description.isNullOrBlank()) {
                    Text(
                        text = stringResource(R.string.activity_detail_no_notes),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    Text(
                        text = stringResource(R.string.activity_detail_desc_label),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    ExpandableNotes(text = activity.description)
                }

                Spacer(Modifier.height(Spacing.xs))
                TextButton(
                    onClick = onDismiss,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(stringResource(R.string.activity_detail_close))
                }
            }
        }
    }
}

/** Lines a long description shows before "See more" releases the rest. */
private const val NOTES_COLLAPSED_LINES = 8

/**
 * Notes text that starts clamped to [NOTES_COLLAPSED_LINES] and grows on
 * demand. The toggle button only renders when the first layout pass
 * actually overflows (measured via the text layout callback), so short
 * notes never show a See more button, and an expanded text always offers
 * See less to roll back up.
 */
@Composable
private fun ExpandableNotes(text: String) {
    var expanded by remember { mutableStateOf(false) }
    var overflowed by remember { mutableStateOf(false) }
    Column {
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            maxLines = if (expanded) Int.MAX_VALUE else NOTES_COLLAPSED_LINES,
            overflow = TextOverflow.Ellipsis,
            onTextLayout = { result ->
                // Only learn from the CLAMPED layout: once expanded the text
                // no longer overflows, and the remembered true keeps the
                // See less button alive.
                if (!expanded) overflowed = result.hasVisualOverflow
            },
        )
        if (overflowed) {
            TextButton(
                onClick = { expanded = !expanded },
                contentPadding = PaddingValues(horizontal = 0.dp),
            ) {
                Text(
                    text = stringResource(
                        if (expanded) R.string.see_less else R.string.see_more
                    ),
                )
            }
        }
    }
}

/** Label-over-value fact row used by the detail sheet. */
@Composable
private fun DetailRow(label: String, value: String, valueColor: Color? = null) {
    Column {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = valueColor ?: MaterialTheme.colorScheme.onSurface,
        )
    }
}

/** Compact trust chip: the verification status of the record. */
@Composable
private fun VerificationChip(verification: VerificationStatus) {
    Surface(
        shape = RoundedCornerShape(percent = 50),
        color = MaterialTheme.colorScheme.surfaceVariant,
        contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
    ) {
        Text(
            text = verificationLabel(verification),
            style = MaterialTheme.typography.labelSmall,
            maxLines = 1,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
        )
    }
}

@Composable
private fun verificationLabel(verification: VerificationStatus): String = when (verification) {
    VerificationStatus.IMPORTED -> stringResource(R.string.verification_imported)
    VerificationStatus.TEACHER_CONFIRMED -> stringResource(R.string.verification_teacher_confirmed)
    VerificationStatus.STUDENT_REPORTED -> stringResource(R.string.verification_student_reported)
    VerificationStatus.NEEDS_REVIEW -> stringResource(R.string.verification_needs_review)
}

@Composable
private fun typeLabel(type: ActivityType): String = when (type) {
    ActivityType.ASSIGNMENT -> stringResource(R.string.type_assignment)
    ActivityType.QUIZ -> stringResource(R.string.type_quiz)
    ActivityType.EXAM -> stringResource(R.string.type_exam)
    ActivityType.PROJECT -> stringResource(R.string.type_project)
    ActivityType.ANNOUNCEMENT -> stringResource(R.string.type_announcement)
    ActivityType.OTHER -> stringResource(R.string.type_other)
}
