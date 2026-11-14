package com.example.studentcodex.domain.model

import java.time.Instant

/**
 * Core Activity Beacon concepts (see docs/ARCHITECTURE.md section 4 and the
 * build plan's data model). Phase 1 uses these shapes for demo data; Phase 2+
 * maps the same concepts onto the Supabase schema.
 */

enum class ActivityType { ASSIGNMENT, QUIZ, EXAM, PROJECT, ANNOUNCEMENT, OTHER }

/** Where the activity record came from. */
enum class ActivitySource { GOOGLE_CLASSROOM, MANUAL, STUDENT_REPORT }

/** How trustworthy the canonical activity is (displayed as a label). */
enum class VerificationStatus { IMPORTED, TEACHER_CONFIRMED, STUDENT_REPORTED, NEEDS_REVIEW }

/** A course the student is enrolled in. */
data class Course(
    val id: String,
    val code: String,
    val title: String,
)

/**
 * A canonical activity: the unit shown in calendars and workload calculations.
 * A canonical activity is counted once per affected student - sources and
 * reports attach to it, they never multiply it.
 */
data class Activity(
    val id: String,
    val title: String,
    val description: String? = null,
    val type: ActivityType = ActivityType.OTHER,
    val course: Course? = null,
    /** Null means "no deadline known" - displayed as unknown, never treated as past or zero. */
    val dueAt: Instant? = null,
    /** Optional estimated effort in minutes; null = unknown. */
    val effortMinutes: Int? = null,
    val source: ActivitySource = ActivitySource.MANUAL,
    val verification: VerificationStatus = VerificationStatus.NEEDS_REVIEW,
    /** True when the activity is visible only to this student (personal scope). */
    val isPersonal: Boolean = false,
    /**
     * The uploader's user id (activities.created_by_user_id): who manually
     * added or reported this school work. Null when unknown (legacy demo
     * rows). The Beacon offers edit/delete on the uploader's OWN manual
     * rows - personal planner entries and shared class uploads alike -
     * while imported (Google Classroom) rows stay read-only evidence
     * regardless of who synced them.
     */
    val createdByUserId: String? = null,
    /**
     * When this school work was uploaded - the server's created_at stamp,
     * never a device clock. The Beacon list is a LIFO stack on this field
     * (last in, first displayed); null = unknown upload time, and such
     * rows sink to the bottom instead of claiming the top.
     */
    val createdAt: Instant? = null,
)
