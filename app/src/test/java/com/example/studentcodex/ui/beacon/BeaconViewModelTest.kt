package com.example.studentcodex.ui.beacon

import com.example.studentcodex.data.fake.FakeActivityRepository
import com.example.studentcodex.data.fake.demoActivities
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class BeaconViewModelTest {

    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `loads all activities as a two-tier LIFO stack - not-overdue on top, overdue at the bottom`() = runTest {
        val vm = BeaconViewModel(FakeActivityRepository())
        advanceUntilIdle()

        val state = vm.uiState.value
        assertTrue(state is BeaconUiState.Content)
        state as BeaconUiState.Content

        assertEquals(BeaconFilter.ALL, state.selectedFilter)
        assertEquals(10, state.filtered.size)

        val now = java.time.Instant.now()
        val notOverdue = state.filtered.filter { !it.isOverdueAsOf(now) }
        val overdue = state.filtered.filter { it.isOverdueAsOf(now) }
        assertEquals(8, notOverdue.size)
        assertEquals(2, overdue.size)
        // The tier owns a contiguous block: not-overdue works fill the
        // top of the list, overdue works the bottom - nothing interleaves.
        assertEquals(
            state.filtered.dropLast(overdue.size).map { it.id },
            notOverdue.map { it.id },
        )

        // The overdue tier owns the very bottom - even though a-9 went
        // up an hour ago, nearly the newest upload of the whole set.
        assertEquals("a-9", state.filtered[8].id)
        assertEquals("a-10", state.filtered.last().id)

        // Each tier is still a LIFO stack on upload time.
        val topUploads = notOverdue.mapNotNull { it.createdAt }
        assertEquals(topUploads, topUploads.sortedDescending())
        val bottomUploads = overdue.mapNotNull { it.createdAt }
        assertEquals(bottomUploads, bottomUploads.sortedDescending())

        // The actionable stack: the 30-minute-old library reminder leads
        // and the four-day-old guest lecture closes it - upload order,
        // not due order.
        assertEquals("a-7", state.filtered.first().id)
        assertEquals("a-8", notOverdue.last().id)
        // Regression guard: the list is no longer due-date ordered - the
        // previous sort (deadline descending) would fail this line.
        val dueDates = state.filtered.mapNotNull { it.dueAt }
        assertTrue(dueDates != dueDates.sortedDescending())
        // The personal rows are still present without filtering.
        assertTrue(state.filtered.any { it.isPersonal })
    }

    @Test
    fun `overdue works sink below every not-overdue work - both tiers stay LIFO`() = runTest {
        val base = java.time.Instant.now()
        // The upload clock is spread to prove the tier dominates it: the
        // very newest upload of all is OVERDUE, the very oldest is not.
        val notOverdueNew = com.example.studentcodex.domain.model.Activity(
            id = "keep-new",
            title = "Newer upload, still open",
            dueAt = base.plusSeconds(3600),
            createdAt = base.minusSeconds(60),
        )
        val notOverdueOld = com.example.studentcodex.domain.model.Activity(
            id = "keep-old",
            title = "Older upload, still open",
            dueAt = base.plusSeconds(3600),
            createdAt = base.minusSeconds(86400 * 4),
        )
        val overdueNewest = com.example.studentcodex.domain.model.Activity(
            id = "late-newest",
            title = "Newest upload of all, but overdue",
            dueAt = base.minusSeconds(3600),
            createdAt = base.minusSeconds(30),
        )
        val overdueOld = com.example.studentcodex.domain.model.Activity(
            id = "late-old",
            title = "Oldest upload of all, overdue",
            dueAt = base.minusSeconds(86400),
            createdAt = base.minusSeconds(86400 * 5),
        )
        val noDeadline = com.example.studentcodex.domain.model.Activity(
            id = "no-due",
            title = "No deadline is never overdue",
            createdAt = base.minusSeconds(600),
        )
        val repo = object : com.example.studentcodex.data.repo.ActivityRepository {
            override suspend fun getActivities() =
                listOf(overdueNewest, notOverdueOld, overdueOld, noDeadline, notOverdueNew)
            override suspend fun createActivity(draft: com.example.studentcodex.data.repo.ActivityDraft) =
                error("not used in this test")
            override suspend fun updateActivity(id: String, draft: com.example.studentcodex.data.repo.ActivityDraft) =
                error("not used in this test")
            override suspend fun deleteActivity(id: String) = error("not used in this test")
            override suspend fun getMySections(): List<com.example.studentcodex.data.repo.MySection> =
                error("not used in this test")
        }
        val vm = BeaconViewModel(repo)
        advanceUntilIdle()

        val state = vm.uiState.value as BeaconUiState.Content
        // Not-overdue tier first (LIFO inside it; the no-deadline row
        // stays there), then the overdue tier (LIFO inside it) - the
        // newest upload of ALL sits fourth, not first: overdue beats
        // upload recency, every time.
        assertEquals(
            listOf("keep-new", "no-due", "keep-old", "late-newest", "late-old"),
            state.filtered.map { it.id },
        )
    }

    @Test
    fun `activities with an unknown upload time sink to the bottom of their tier`() = runTest {
        // A legacy row with a deadline but no upload stamp: it must not
        // claim the top of the stack - unknown upload time means honest
        // last place WITHIN its tier, whatever its due date says.
        val undated = com.example.studentcodex.domain.model.Activity(
            id = "undated",
            title = "Undated work",
            dueAt = java.time.Instant.now().plusSeconds(600),
        )
        val dated = demoActivities.first()
        val repo = object : com.example.studentcodex.data.repo.ActivityRepository {
            override suspend fun getActivities() = listOf(undated, dated)
            override suspend fun createActivity(draft: com.example.studentcodex.data.repo.ActivityDraft) =
                error("not used in this test")
            override suspend fun updateActivity(id: String, draft: com.example.studentcodex.data.repo.ActivityDraft) =
                error("not used in this test")
            override suspend fun deleteActivity(id: String) = error("not used in this test")
            override suspend fun getMySections(): List<com.example.studentcodex.data.repo.MySection> =
                error("not used in this test")
        }
        val vm = BeaconViewModel(repo)
        advanceUntilIdle()

        val state = vm.uiState.value as BeaconUiState.Content
        assertEquals(dated.id, state.filtered.first().id)
        assertEquals("undated", state.filtered.last().id)
    }

    @Test
    fun `assignment filter shows only assignments`() = runTest {
        val vm = BeaconViewModel(FakeActivityRepository())
        advanceUntilIdle()

        vm.setFilter(BeaconFilter.ASSIGNMENTS)
        val state = vm.uiState.value as BeaconUiState.Content

        assertTrue(state.filtered.isNotEmpty())
        assertTrue(state.filtered.all {
            it.type == com.example.studentcodex.domain.model.ActivityType.ASSIGNMENT
        })
    }

    @Test
    fun `activity filter shows only generic activities`() = runTest {
        val vm = BeaconViewModel(FakeActivityRepository())
        advanceUntilIdle()

        vm.setFilter(BeaconFilter.ACTIVITY)
        val state = vm.uiState.value as BeaconUiState.Content

        assertTrue(state.filtered.isNotEmpty())
        assertTrue(state.filtered.all {
            it.type == com.example.studentcodex.domain.model.ActivityType.OTHER
        })
    }

    @Test
    fun `overdue filter shows only overdue works, not-overdue filter only actionable ones`() = runTest {
        // Same five-row spread as the two-tier sort test: the overdue pair
        // owns the very newest and very oldest uploads, so only the
        // deadline line - not upload recency - can decide membership.
        val base = java.time.Instant.now()
        val overdueNewest = com.example.studentcodex.domain.model.Activity(
            id = "late-newest",
            title = "Newest upload of all, but overdue",
            dueAt = base.minusSeconds(3600),
            createdAt = base.minusSeconds(30),
        )
        val overdueOld = com.example.studentcodex.domain.model.Activity(
            id = "late-old",
            title = "Oldest upload of all, overdue",
            dueAt = base.minusSeconds(86400),
            createdAt = base.minusSeconds(86400 * 5),
        )
        val notOverdueNew = com.example.studentcodex.domain.model.Activity(
            id = "keep-new",
            title = "Newer upload, still open",
            dueAt = base.plusSeconds(3600),
            createdAt = base.minusSeconds(60),
        )
        val notOverdueOld = com.example.studentcodex.domain.model.Activity(
            id = "keep-old",
            title = "Older upload, still open",
            dueAt = base.plusSeconds(3600),
            createdAt = base.minusSeconds(86400 * 4),
        )
        val noDeadline = com.example.studentcodex.domain.model.Activity(
            id = "no-due",
            title = "No deadline is never overdue",
            createdAt = base.minusSeconds(600),
        )
        val repo = object : com.example.studentcodex.data.repo.ActivityRepository {
            override suspend fun getActivities() =
                listOf(overdueNewest, notOverdueOld, overdueOld, noDeadline, notOverdueNew)
            override suspend fun createActivity(draft: com.example.studentcodex.data.repo.ActivityDraft) =
                error("not used in this test")
            override suspend fun updateActivity(id: String, draft: com.example.studentcodex.data.repo.ActivityDraft) =
                error("not used in this test")
            override suspend fun deleteActivity(id: String) = error("not used in this test")
            override suspend fun getMySections(): List<com.example.studentcodex.data.repo.MySection> =
                error("not used in this test")
        }
        val vm = BeaconViewModel(repo)
        advanceUntilIdle()

        // Overdue-only view: exactly the two deadline-passed rows, and
        // still a LIFO stack (newest overdue upload first).
        vm.setFilter(BeaconFilter.OVERDUE)
        val overdueState = vm.uiState.value as BeaconUiState.Content
        assertEquals(listOf("late-newest", "late-old"), overdueState.filtered.map { it.id })

        // Not-overdue-only view: the still-open rows plus the no-deadline
        // row (never overdue), newest upload first.
        vm.setFilter(BeaconFilter.NOT_OVERDUE)
        val openState = vm.uiState.value as BeaconUiState.Content
        assertEquals(listOf("keep-new", "no-due", "keep-old"), openState.filtered.map { it.id })
    }

    @Test
    fun `retry recovers after a failure`() = runTest {
        var failing = true
        val flakyRepo = object : com.example.studentcodex.data.repo.ActivityRepository {
            override suspend fun getActivities(): List<com.example.studentcodex.domain.model.Activity> {
                if (failing) error("network down")
                return demoActivities
            }
            override suspend fun createActivity(draft: com.example.studentcodex.data.repo.ActivityDraft) =
                error("not used in this test")
            override suspend fun updateActivity(id: String, draft: com.example.studentcodex.data.repo.ActivityDraft) =
                error("not used in this test")
            override suspend fun deleteActivity(id: String) = error("not used in this test")
            override suspend fun getMySections(): List<com.example.studentcodex.data.repo.MySection> =
                error("not used in this test")
        }
        val vm = BeaconViewModel(flakyRepo)
        advanceUntilIdle()
        assertTrue(vm.uiState.value is BeaconUiState.Error)

        failing = false
        vm.retry()
        advanceUntilIdle()
        val state = vm.uiState.value
        assertTrue("Expected Content after retry, was $state", state is BeaconUiState.Content)
    }

    @Test
    fun `class report requires a section before saving`() = runTest {
        val repo = FakeActivityRepository()
        val vm = BeaconViewModel(repo)
        advanceUntilIdle()

        vm.openEditor()
        advanceUntilIdle()
        vm.onEditorTitleChange("Boardwork chapter 5")
        vm.saveEditor()
        advanceUntilIdle()

        val sheet = vm.editorSheet.value
        assertTrue("Expected SECTION_REQUIRED, was ${sheet?.error}", sheet?.error == "SECTION_REQUIRED")
    }

    @Test
    fun `saving a class report carries the enrolled section and course`() = runTest {
        val repo = FakeActivityRepository()
        val vm = BeaconViewModel(repo)
        advanceUntilIdle()

        vm.openEditor()
        advanceUntilIdle()
        vm.onEditorTitleChange("Boardwork chapter 5")
        advanceUntilIdle()
        vm.onEditorSectionChange("sec-cs201")
        vm.saveEditor()
        advanceUntilIdle()

        // Sheet closes on success; the draft carried the section cohort.
        assertTrue(vm.editorSheet.value == null)
        val draft = repo.lastDraft
        assertTrue("draft=$draft", draft != null)
        assertEquals("sec-cs201", draft?.sectionId)
        assertEquals("crs-cs201", draft?.courseId)
        assertEquals(false, draft?.isPersonal)
        assertEquals(false, draft?.teacherConfirmed) // enrolled as a student
    }

    @Test
    fun `a taught section saves as a teacher-confirmed class activity`() = runTest {
        val repo = FakeActivityRepository()
        val vm = BeaconViewModel(repo)
        advanceUntilIdle()

        vm.openEditor()
        advanceUntilIdle()
        vm.onEditorTitleChange("Prelim exam coverage")
        vm.onEditorSectionChange("sec-cs301") // the tutored section
        vm.saveEditor()
        advanceUntilIdle()

        assertTrue(vm.editorSheet.value == null)
        val draft = repo.lastDraft
        assertTrue("draft=$draft", draft != null)
        assertEquals("sec-cs301", draft?.sectionId)
        assertEquals("crs-cs301", draft?.courseId)
        assertEquals(false, draft?.isPersonal)
        assertEquals(true, draft?.teacherConfirmed) // taught -> teacher-confirmed
    }
}

