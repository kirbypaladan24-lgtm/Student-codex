package com.example.studentcodex.ui.home

import com.example.studentcodex.data.fake.FakeActivityRepository
import com.example.studentcodex.data.fake.FakeCommunityRepository
import com.example.studentcodex.data.fake.FakeProfileRepository
import com.example.studentcodex.data.repo.ActivityDraft
import com.example.studentcodex.data.repo.ActivityRepository
import com.example.studentcodex.domain.model.Activity
import java.time.Duration
import java.time.Instant
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
class HomeViewModelTest {

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
    fun `starts in loading state`() {
        val vm = HomeViewModel(FakeActivityRepository(), FakeCommunityRepository(), FakeProfileRepository())
        assertEquals(HomeUiState.Loading, vm.uiState.value)
    }

    @Test
    fun `loads content sorted by due date and limited to preview count`() = runTest {
        val vm = HomeViewModel(FakeActivityRepository(), FakeCommunityRepository(), FakeProfileRepository())
        advanceUntilIdle()

        val state = vm.uiState.value
        assertTrue("Expected Content, was $state", state is HomeUiState.Content)
        state as HomeUiState.Content

        // The greeting's personal name rides along with the content -
        // the FIRST name only, cut from the "Demo Student" display name.
        assertEquals("Demo", state.userName)
        assertEquals(HomeViewModel.HomePreviewCount, state.nextActivities.size)
        val dueDates = state.nextActivities.mapNotNull { it.dueAt }
        assertEquals(dueDates, dueDates.sorted())
        assertEquals(HomeViewModel.CommunityPreviewCount, state.recentPosts.size)
    }

    @Test
    fun `refresh picks up a school work just added elsewhere`() = runTest {
        // The saved-state back stack keeps Home's ViewModel alive across
        // tab switches - the exact scenario the resume refresh fixes: a
        // work added under the Beacon must appear on the next Home visit.
        val repo = FakeActivityRepository()
        val vm = HomeViewModel(repo, FakeCommunityRepository(), FakeProfileRepository())
        advanceUntilIdle()
        val before = (vm.uiState.value as HomeUiState.Content).nextActivities.size

        // "Added in the Beacon": the repository now holds one more future
        // deadline; Home's retained ViewModel knows nothing of it yet.
        repo.createActivity(
            ActivityDraft(
                title = "Added elsewhere",
                description = null,
                type = "assignment",
                // Sooner than every demo deadline: it must lead the
                // preview, proving the refresh pulled the new row in.
                dueAt = Instant.now() + Duration.ofMinutes(30),
                isPersonal = false,
                sectionId = "sec-cs101",
                courseId = "crs-cs101",
                teacherConfirmed = false,
            )
        )
        // The stale instance still shows the old count...
        assertEquals(before, (vm.uiState.value as HomeUiState.Content).nextActivities.size)

        // ...until the tab resume refresh runs.
        vm.refresh()
        advanceUntilIdle()
        val state = vm.uiState.value as HomeUiState.Content
        assertTrue(state.nextActivities.any { it.title == "Added elsewhere" })
    }

    @Test
    fun `past deadlines are excluded from the list and the 7-day count`() = runTest {
        val now = Instant.now()
        val repo = object : ActivityRepository {
            override suspend fun getActivities(): List<Activity> = listOf(
                Activity(id = "past-1", title = "Already lapsed", dueAt = now - Duration.ofHours(2)),
                Activity(id = "soon-1", title = "Due today", dueAt = now + Duration.ofHours(6)),
                Activity(id = "week-1", title = "Due in 3 days", dueAt = now + Duration.ofDays(3)),
                Activity(id = "far-1", title = "Due next month", dueAt = now + Duration.ofDays(30)),
                Activity(id = "none-1", title = "No deadline"),
            )
            override suspend fun createActivity(draft: ActivityDraft) = error("not used")
            override suspend fun updateActivity(id: String, draft: ActivityDraft) = error("not used")
            override suspend fun deleteActivity(id: String) = error("not used")
            override suspend fun getMySections() = error("not used")
        }
        val vm = HomeViewModel(repo, FakeCommunityRepository(), FakeProfileRepository())
        advanceUntilIdle()

        val state = vm.uiState.value as HomeUiState.Content
        // Only upcoming work, soonest first — the lapsed item never shows.
        assertEquals(listOf("soon-1", "week-1", "far-1"), state.nextActivities.map { it.id })
        // The count covers ONLY the next 7 days: today + in-3-days, not
        // the lapsed work and not the far-future item.
        assertEquals(2, state.dueSoonCount)
    }
}

