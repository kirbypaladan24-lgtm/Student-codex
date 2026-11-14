package com.example.studentcodex.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.studentcodex.data.repo.ActivityRepository
import com.example.studentcodex.data.repo.CommunityRepository
import com.example.studentcodex.data.repo.ProfileRepository
import com.example.studentcodex.domain.model.Activity
import com.example.studentcodex.domain.model.CommunityPost
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Home aggregates the next deadlines and a peek at the community feed. */
sealed interface HomeUiState {
    data object Loading : HomeUiState

    data class Error(val message: String) : HomeUiState

    data class Content(
        val nextActivities: List<Activity>,
        val recentPosts: List<CommunityPost>,
        /** Deadlines falling due within the next 7 days (all of them, not just the preview rows). */
        val dueSoonCount: Int,
        /** The signed-in student's FIRST name for the greeting; null for
         * guests or a best-effort fetch that failed - the plain greeting
         * form covers both. */
        val userName: String? = null,
    ) : HomeUiState
}

class HomeViewModel(
    private val activityRepository: ActivityRepository,
    private val communityRepository: CommunityRepository,
    private val profileRepository: ProfileRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<HomeUiState>(HomeUiState.Loading)
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun load() {
        _uiState.value = HomeUiState.Loading
        viewModelScope.launch {
            try {
                _uiState.value = fetchContent()
            } catch (e: Exception) {
                _uiState.value = HomeUiState.Error(e.message ?: "Could not load your overview.")
            }
        }
    }

    /**
     * Silent refresh for tab resumes. The saved-state back stack keeps
     * this ViewModel alive across tab switches, so a school work just
     * added under the Beacon - or anything published meanwhile - would
     * otherwise stay invisible on Home until a process restart. Keeps
     * the current content while fetching (no skeleton flash) and on
     * failure keeps whatever is on screen; the explicit retry button
     * still surfaces hard errors.
     */
    fun refresh() {
        if (_uiState.value is HomeUiState.Loading) return // first load already in flight
        viewModelScope.launch {
            try {
                _uiState.value = fetchContent()
            } catch (_: Exception) {
                // Silent by design: show the last good overview.
            }
        }
    }

    private suspend fun fetchContent(): HomeUiState.Content {
        val now = Instant.now()
        // UPCOMING only: work that already lapsed is history — the
        // Beacon keeps overdue rows at its bottom, and the Home
        // overview must never lead with (or count) past deadlines.
        val activities = activityRepository.getActivities()
            .filter { it.dueAt?.isAfter(now) == true }
            .sortedBy { it.dueAt }
        val posts = communityRepository.getRecentPosts()
        // The greeting's personal name - the FIRST name only
        // ("Good morning, Kirby"), cut from the profile's
        // "First Last" display name. Best effort by design: a
        // profile hiccup must never take the deadlines overview
        // down with it - the greeting just falls back to no name.
        val userName = runCatching {
            profileRepository.getProfile().displayName.trim()
        }.getOrNull()
            ?.split(Regex("\\s+"))
            ?.firstOrNull()
            ?.ifBlank { null }
        val sevenDaysOut = now + Duration.ofDays(7)
        val dueSoonCount = activities.count { activity ->
            activity.dueAt?.isBefore(sevenDaysOut) == true
        }
        return HomeUiState.Content(
            nextActivities = activities.take(HomePreviewCount),
            recentPosts = posts.take(CommunityPreviewCount),
            dueSoonCount = dueSoonCount,
            userName = userName,
        )
    }

    fun retry() = load()

    companion object {
        const val HomePreviewCount = 3
        const val CommunityPreviewCount = 2
    }
}

