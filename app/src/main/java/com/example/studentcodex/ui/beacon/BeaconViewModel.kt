package com.example.studentcodex.ui.beacon

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.studentcodex.data.repo.ActivityDraft
import com.example.studentcodex.data.repo.ActivityRepository
import com.example.studentcodex.data.repo.MySection
import com.example.studentcodex.domain.model.Activity
import com.example.studentcodex.domain.SchoolZone
import com.example.studentcodex.domain.model.ActivitySource
import com.example.studentcodex.domain.model.ActivityType
import com.example.studentcodex.domain.toDueInstant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * Filters the Beacon list can apply. Each filter owns its full predicate.
 * "Now" is handed into the predicate so the time-based overdue rules agree
 * with the two-tier sort on exactly one sampled instant - the filter chips
 * and the list order can never disagree about which side of the deadline
 * line a school work sits on.
 */
enum class BeaconFilter(val matches: (Activity, Instant) -> Boolean) {
    ALL({ _, _ -> true }),
    /** Only deadline-passed school works - the overdue tier alone. */
    OVERDUE({ activity, now -> activity.isOverdueAsOf(now) }),
    /** Only still-actionable works - no deadline counts as not overdue. */
    NOT_OVERDUE({ activity, now -> !activity.isOverdueAsOf(now) }),
    /** Imported evidence from the Google Classroom sync (Phase 6). */
    CLASSROOM({ it, _ -> it.source == ActivitySource.GOOGLE_CLASSROOM }),
    ASSIGNMENTS({ it, _ -> it.type == ActivityType.ASSIGNMENT }),
    EXAMS({ it, _ -> it.type == ActivityType.EXAM }),
    QUIZZES({ it, _ -> it.type == ActivityType.QUIZ }),
    PROJECTS({ it, _ -> it.type == ActivityType.PROJECT }),
    /** Generic school work: the "Activity" type students pick by hand. */
    ACTIVITY({ it, _ -> it.type == ActivityType.OTHER }),
}

sealed interface BeaconUiState {
    data object Loading : BeaconUiState

    data class Error(val message: String) : BeaconUiState

    data class Content(
        val filtered: List<Activity>,
        val selectedFilter: BeaconFilter,
        /** True when the whole (unfiltered) list is empty. */
        val isEmptyOverall: Boolean,
    ) : BeaconUiState
}

/**
 * State of the manual-activity editor sheet. Null = closed. A non-null id
 * means an EDIT of the user's own activity; null id = creation.
 */
data class ActivityEditorUiState(
    val editingId: String? = null,
    val title: String = "",
    val description: String = "",
    val type: ActivityType = ActivityType.ASSIGNMENT,
    /** ISO-8601 local date text (yyyy-MM-dd); blank = no deadline. */
    val dueDateText: String = "",
    /** True only while EDITING an old personal row; new rows are class rows. */
    val isPersonal: Boolean = false,
    /** The user's own course sections - the class-activity audience picker. */
    val sections: List<MySection> = emptyList(),
    /** True while [sections] is being (re)fetched for a newly opened editor. */
    val sectionsLoading: Boolean = false,
    /** Chosen section id; null while the share target is unset. */
    val selectedSectionId: String? = null,
    /** Course code of the row being edited (scope is fixed server-side). */
    val originCourseCode: String? = null,
    val saving: Boolean = false,
    val error: String? = null,
    /** True while the sheet shows a validation/success message inline. */
    val saved: Boolean = false,
)

/**
 * Why an editor submit was rejected (resolved to strings in the UI).
 */
enum class ActivityEditorError { TITLE_BLANK, SECTION_REQUIRED }

/**
 * Beacon list + manual activity CRUD. Data comes
 * from the signed-in student's real Supabase rows (RLS-scoped); guests see
 * an honest signed-out state from the screen instead.
 */
class BeaconViewModel(
    private val activityRepository: ActivityRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<BeaconUiState>(BeaconUiState.Loading)
    val uiState: StateFlow<BeaconUiState> = _uiState.asStateFlow()

    private val _editorSheet = MutableStateFlow<ActivityEditorUiState?>(null)
    val editorSheet: StateFlow<ActivityEditorUiState?> = _editorSheet.asStateFlow()

    private var allActivities: List<Activity> = emptyList()

    init {
        load()
    }

    fun load() {
        _uiState.value = BeaconUiState.Loading
        viewModelScope.launch {
            try {
                allActivities = activityRepository.getActivities()
                publishContent(currentFilterOrNull() ?: BeaconFilter.ALL)
            } catch (e: Exception) {
                _uiState.value = BeaconUiState.Error(e.message ?: "Could not load activities.")
            }
        }
    }

    fun retry() = load()

    /**
     * Silent refresh for tab resumes. The saved-state back stack keeps this
     * ViewModel alive across tab switches, so a Classroom sync just run
     * under Settings - or anything a classmate published meanwhile - would
     * otherwise stay invisible until a process restart. Keeps the current
     * filter, keeps the current content while fetching (no skeleton flash),
     * and on failure keeps whatever is on screen; the explicit retry
     * button still surfaces hard errors.
     */
    fun refresh() {
        if (_uiState.value is BeaconUiState.Loading) return // first load already in flight
        viewModelScope.launch {
            try {
                allActivities = activityRepository.getActivities()
                publishContent(currentFilterOrNull() ?: BeaconFilter.ALL)
            } catch (_: Exception) {
                // Silent by design: show the last good list.
            }
        }
    }

    fun setFilter(filter: BeaconFilter) {
        if (uiState.value is BeaconUiState.Content) {
            publishContent(filter)
        }
    }

    // ------------------------------------------------------ activity editor

    /** Opens the editor for a NEW manual activity. */
    fun openEditor() {
        if (_editorSheet.value?.saving == true) return
        _editorSheet.value = ActivityEditorUiState(sectionsLoading = true)
        loadSections()
    }

    /**
     * Fetches the user's own sections for the course picker — EVERY time
     * the editor opens, never a session-stale cache: courses added under
     * Settings → School details (or picked up from classmates) show up on
     * the very next open. Empty for guests or accounts without
     * enrollments (the sheet then has no audience to offer).
     */
    private fun loadSections() {
        updateEditor { it.copy(sectionsLoading = true) }
        viewModelScope.launch {
            runCatching { activityRepository.getMySections() }
                .onSuccess { sections ->
                    updateEditor { sheet ->
                        // With exactly one section there is nothing to pick.
                        val auto = if (sheet.selectedSectionId == null && sections.size == 1)
                            sections[0].sectionId else sheet.selectedSectionId
                        // A previously picked section only survives if it
                        // still exists in the fresh list.
                        val kept = sheet.selectedSectionId
                            ?.let { id -> sections.firstOrNull { it.sectionId == id }?.sectionId }
                            ?: auto
                        sheet.copy(sections = sections, selectedSectionId = kept, sectionsLoading = false)
                    }
                }
                .onFailure {
                    // Fetch failed: stop the spinner; an empty list shows
                    // the honest "no courses" hint (retry by reopening).
                    updateEditor { it.copy(sectionsLoading = false) }
                }
        }
    }

    /**
     * Opens the editor for editing one of the user's own manual activities.
     * Non-manual/imported activities are read-only evidence, not editable.
     * The row's course code is shown as fixed origin info (scope is
     * immutable server-side, so no picker is offered).
     */
    fun openEditor(activity: Activity) {
        if (_editorSheet.value?.saving == true) return
        _editorSheet.value = ActivityEditorUiState(
            editingId = activity.id,
            title = activity.title,
            description = activity.description.orEmpty(),
            type = activity.type,
            dueDateText = activity.dueAt?.atZone(SchoolZone)?.toLocalDate()?.toString().orEmpty(),
            isPersonal = activity.isPersonal,
            originCourseCode = activity.course?.code,
        )
    }

    fun closeEditor() {
        if (_editorSheet.value?.saving == true) return
        _editorSheet.value = null
    }

    fun onEditorTitleChange(value: String) {
        updateEditor { it.copy(title = value, error = null, saved = false) }
    }

    fun onEditorDescriptionChange(value: String) {
        updateEditor { it.copy(description = value) }
    }

    fun onEditorTypeChange(value: ActivityType) {
        updateEditor { it.copy(type = value) }
    }

    fun onEditorDueDateChange(value: String) {
        updateEditor { it.copy(dueDateText = value, error = null) }
    }

    /** Picks which own course section the class activity belongs to. */
    fun onEditorSectionChange(sectionId: String) {
        updateEditor { it.copy(selectedSectionId = sectionId, error = null) }
    }

    /**
     * Saves the editor sheet: creates a new manual activity or updates the
     * edited one, refreshes the list, and closes the sheet on success.
     */
    fun saveEditor() {
        val sheet = _editorSheet.value ?: return
        if (sheet.saving) return
        val title = sheet.title.trim()
        if (title.isEmpty()) {
            updateEditor { it.copy(error = null, saved = false).withError(ActivityEditorError.TITLE_BLANK) }
            return
        }
        // A class activity needs its section - the one cohort question.
        // The section itself carries program / year / block (and the
        // profile already holds campus, program, year, section), so
        // nothing else is ever asked. Publishing is instant; no approval
        // exists.
        val shareAsClass = !sheet.isPersonal && sheet.editingId == null
        val section = sheet.sections.firstOrNull { it.sectionId == sheet.selectedSectionId }
        if (shareAsClass && section == null) {
            updateEditor { it.copy(error = null, saved = false).withError(ActivityEditorError.SECTION_REQUIRED) }
            return
        }
        val dueAt = parseLocalDate(sheet.dueDateText)
        val draft = ActivityDraft(
            title = title,
            description = sheet.description.trim().takeIf { it.isNotEmpty() },
            type = sheet.type.wireName,
            dueAt = dueAt,
            isPersonal = sheet.isPersonal,
            sectionId = if (shareAsClass) section?.sectionId else null,
            courseId = if (shareAsClass) section?.courseId else null,
            // A taught section saves as teacher-confirmed; the guard
            // trigger demands exactly that for teacher creators.
            teacherConfirmed = if (shareAsClass) section?.role == "teacher" else false,
        )
        updateEditor { it.copy(saving = true, error = null) }
        viewModelScope.launch {
            try {
                val editingId = sheet.editingId
                if (editingId == null) {
                    activityRepository.createActivity(draft)
                } else {
                    activityRepository.updateActivity(editingId, draft)
                }
                _editorSheet.value = null
                reloadKeepingFilter()
            } catch (e: Exception) {
                updateEditor { it.copy(saving = false, error = e.message ?: "Could not save the activity.") }
            }
        }
    }

    /** Soft-deletes one of the user's own activities after confirmation. */
    fun deleteActivity(id: String) {
        viewModelScope.launch {
            try {
                activityRepository.deleteActivity(id)
                reloadKeepingFilter()
            } catch (e: Exception) {
                // Deletion failures surface as a list reload; the row stays.
                _uiState.value = BeaconUiState.Error(e.message ?: "Could not delete the activity.")
            }
        }
    }

    // -------------------------------------------------------------- helpers

    private fun updateEditor(update: (ActivityEditorUiState) -> ActivityEditorUiState) {
        val sheet = _editorSheet.value ?: return
        _editorSheet.value = update(sheet)
    }

    private fun ActivityEditorUiState.withError(error: ActivityEditorError): ActivityEditorUiState =
        copy(error = error.name)

    private fun currentFilterOrNull(): BeaconFilter? =
        (_uiState.value as? BeaconUiState.Content)?.selectedFilter

    private fun reloadKeepingFilter() {
        viewModelScope.launch {
            try {
                allActivities = activityRepository.getActivities()
                publishContent(currentFilterOrNull() ?: BeaconFilter.ALL)
            } catch (e: Exception) {
                _uiState.value = BeaconUiState.Error(e.message ?: "Could not load activities.")
            }
        }
    }

    private fun publishContent(filter: BeaconFilter) {
        // "Now" is sampled once per publish so the whole list agrees
        // which side of the line every deadline sits on - the same rule
        // the row's due emphasis colors on (not after now = overdue).
        val now = Instant.now()
        val filtered = allActivities
            .filter { filter.matches(it, now) }
            // Two-tier LIFO stack. Tier 1 (top): every NOT-overdue school
            // work, newest upload first. Tier 2 (bottom): the OVERDUE
            // works as their own stack - also newest upload first - so a
            // deadline that already passed never buries actionable work,
            // while the overdue group still reads last-in-first-display.
            // The upload order runs on the server's created_at, so it is
            // identical on every device and never jitters with the local
            // clock. A work with no deadline is never overdue - it stays
            // in the top tier. Rows with an unknown upload time (legacy
            // local rows) sink last WITHIN their tier - nulls compare
            // smallest, so descending keeps them at the tier's end -
            // rather than claiming the top of either stack.
            .sortedWith(
                compareBy<Activity> { it.isOverdueAsOf(now) } // false (not overdue) sorts first
                    .thenByDescending { it.createdAt }         // LIFO within each tier
                    .thenBy { it.title },                      // stable tie-break
            )
        _uiState.value = BeaconUiState.Content(
            filtered = filtered,
            selectedFilter = filter,
            isEmptyOverall = allActivities.isEmpty(),
        )
    }

    private fun parseLocalDate(text: String): Instant? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null
        val date = runCatching { java.time.LocalDate.parse(trimmed) }.getOrNull() ?: return null
        // A due DATE means end-of-day on the school calendar (23:59
        // Asia/Manila) — the intuitive reading of "due Friday", kept
        // stable whatever zone the device itself is set to.
        return date.toDueInstant()
    }
}

/** Stable wire names shared with the database check constraint. */

/**
 * True when this school work's deadline has already passed as of [now] -
 * the exact rule the row's due emphasis uses ("Overdue" label + error
 * tint: not after now). A work with no deadline is never overdue.
 * Shared by the ViewModel's two-tier sort and the screen's overdue
 * section header, so list order and labeling can never disagree.
 */
fun Activity.isOverdueAsOf(now: Instant): Boolean =
    dueAt != null && !dueAt.isAfter(now)

val ActivityType.wireName: String
    get() = when (this) {
        ActivityType.ASSIGNMENT -> "assignment"
        ActivityType.QUIZ -> "quiz"
        ActivityType.EXAM -> "exam"
        ActivityType.PROJECT -> "project"
        ActivityType.ANNOUNCEMENT -> "announcement"
        ActivityType.OTHER -> "other"
    }
