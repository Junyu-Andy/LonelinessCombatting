/// Intake questionnaire response model.
///
/// Stored at `users/{uid}/onboarding_intake/v1`.
/// Covers 6 parts of the structured onboarding intake.

/// A person the user identified during intake (important contacts or
/// people they wish to reconnect with).
class PersonEntry {
  final String name;
  final String relationship;

  /// For important people: contact frequency. For reconnect people: barrier.
  final String? extra;

  const PersonEntry({
    required this.name,
    required this.relationship,
    this.extra,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'relationship': relationship,
        'extra': extra,
      };

  factory PersonEntry.fromMap(Map<String, dynamic> map) => PersonEntry(
        name: (map['name'] as String?) ?? '',
        relationship: (map['relationship'] as String?) ?? '',
        extra: map['extra'] as String?,
      );
}

/// Telemetry record for a single intake item.
class ItemTelemetry {
  final DateTime renderedAt;
  final DateTime? submittedAt;
  final bool skipped;
  final int? timeOnItemMs;

  const ItemTelemetry({
    required this.renderedAt,
    this.submittedAt,
    this.skipped = false,
    this.timeOnItemMs,
  });

  Map<String, dynamic> toMap() => {
        'renderedAt': renderedAt.toIso8601String(),
        'submittedAt': submittedAt?.toIso8601String(),
        'skipped': skipped,
        'timeOnItemMs': timeOnItemMs,
      };

  factory ItemTelemetry.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic v) {
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      try {
        final dynamic dyn = v;
        final result = dyn.toDate();
        if (result is DateTime) return result;
      } catch (_) {}
      return DateTime.now();
    }

    return ItemTelemetry(
      renderedAt: parseDate(map['renderedAt']),
      submittedAt: map['submittedAt'] != null ? parseDate(map['submittedAt']) : null,
      skipped: (map['skipped'] as bool?) ?? false,
      timeOnItemMs: (map['timeOnItemMs'] as num?)?.toInt(),
    );
  }
}

/// Option IDs for intake items — use constants, never magic strings.
class IntakeOptions {
  // Item 1.1 mainGoal
  static const String mainGoalCompanionship = 'companionship';
  static const String mainGoalEmotionalOutlet = 'emotional_outlet';
  static const String mainGoalReconnect = 'reconnect_others';
  static const String mainGoalLearning = 'learning';
  static const String mainGoalShareMemories = 'share_memories';
  static const String mainGoalCurious = 'curious';
  static const String mainGoalOther = 'other';

  // Item 1.2 lonelinessTimings
  static const String timingMornings = 'mornings';
  static const String timingAfternoons = 'afternoons';
  static const String timingEvenings = 'evenings';
  static const String timingNights = 'nights';
  static const String timingWeekends = 'weekends';
  static const String timingAfterMealsAlone = 'after_meals_alone';
  static const String timingFestivals = 'festivals';
  static const String timingVaries = 'varies';
  static const String timingOther = 'other';

  // Item 4.1 activities
  static const String actTv = 'tv';
  static const String actRadio = 'radio';
  static const String actReading = 'reading';
  static const String actMahjong = 'mahjong';
  static const String actTaichi = 'taichi';
  static const String actWalking = 'walking';
  static const String actGardening = 'gardening';
  static const String actCooking = 'cooking';
  static const String actReligious = 'religious';
  static const String actVolunteering = 'volunteering';
  static const String actDining = 'dining';
  static const String actGrandkids = 'grandkids';
  static const String actMusic = 'music';
  static const String actCrafts = 'crafts';
  static const String actOther = 'other';

  // Item 4.2 topics
  static const String topicHkHistory = 'hk_history';
  static const String topicFood = 'food';
  static const String topicFamilyStories = 'family_stories';
  static const String topicNature = 'nature';
  static const String topicMusicFilm = 'music_film';
  static const String topicHealth = 'health';
  static const String topicCurrentEvents = 'current_events';
  static const String topicReligion = 'religion';
  static const String topicTravel = 'travel';
  static const String topicSports = 'sports';
  static const String topicOther = 'other';

  // Item 5.1 lifeChapters
  static const String chapterChildhood = 'childhood';
  static const String chapterSchool = 'school';
  static const String chapterFirstJob = 'first_job';
  static const String chapterMarriage = 'marriage';
  static const String chapterRaisingKids = 'raising_kids';
  static const String chapterMoves = 'moves';
  static const String chapterHkMilestones = 'hk_milestones';
  static const String chapterHobbiesDeveloped = 'hobbies_developed';
  static const String chapterTravel = 'travel';
  static const String chapterPresentFocus = 'present_focus';

  // Item 6.1 inputMode
  static const String inputTyping = 'typing';
  static const String inputVoice = 'voice';
  static const String inputBoth = 'both';
  static const String inputUnsure = 'unsure';

  // Item 6.2 preferredTimes
  static const String timeMorning = 'morning';
  static const String timeMidday = 'midday';
  static const String timeAfternoon = 'afternoon';
  static const String timeEvening = 'evening';
  static const String timeBeforeBed = 'before_bed';
  static const String timeNoRoutine = 'no_routine';
}

/// Full intake response capturing all 6 parts.
class IntakeResponse {
  // Part 1
  final List<String> mainGoals;
  final String? mainGoalOther;
  final List<String>? lonelinessTimings;

  // Part 2
  final List<PersonEntry>? importantPeople; // max 5
  final List<PersonEntry>? reconnectPeople; // max 3

  // Part 3
  final String? typicalMorning;
  final String? typicalAfternoon;
  final String? typicalEvening;
  final String? onMind; // sensitive

  // Part 4
  final List<String>? activities;
  final String? activitiesOther;
  final List<String>? topics;
  final String? topicsOther;

  // Part 5
  final List<String>? lifeChapters;
  final String? avoidTopics; // SAFETY-CRITICAL

  // Part 6
  final String inputMode;
  final List<String>? preferredTimes;

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;
  final Set<int> completedParts; // parts 1-6
  final bool allCompleted;

  // Telemetry
  final Map<String, ItemTelemetry?> itemTimestamps;

  const IntakeResponse({
    this.mainGoals = const [],
    this.mainGoalOther,
    this.lonelinessTimings,
    this.importantPeople,
    this.reconnectPeople,
    this.typicalMorning,
    this.typicalAfternoon,
    this.typicalEvening,
    this.onMind,
    this.activities,
    this.activitiesOther,
    this.topics,
    this.topicsOther,
    this.lifeChapters,
    this.avoidTopics,
    required this.inputMode,
    this.preferredTimes,
    required this.createdAt,
    required this.updatedAt,
    this.completedParts = const {},
    this.allCompleted = false,
    this.itemTimestamps = const {},
  });

  IntakeResponse copyWith({
    List<String>? mainGoals,
    String? mainGoalOther,
    List<String>? lonelinessTimings,
    List<PersonEntry>? importantPeople,
    List<PersonEntry>? reconnectPeople,
    String? typicalMorning,
    String? typicalAfternoon,
    String? typicalEvening,
    String? onMind,
    List<String>? activities,
    String? activitiesOther,
    List<String>? topics,
    String? topicsOther,
    List<String>? lifeChapters,
    String? avoidTopics,
    String? inputMode,
    List<String>? preferredTimes,
    DateTime? updatedAt,
    Set<int>? completedParts,
    bool? allCompleted,
    Map<String, ItemTelemetry?>? itemTimestamps,
  }) =>
      IntakeResponse(
        mainGoals: mainGoals ?? this.mainGoals,
        mainGoalOther: mainGoalOther ?? this.mainGoalOther,
        lonelinessTimings: lonelinessTimings ?? this.lonelinessTimings,
        importantPeople: importantPeople ?? this.importantPeople,
        reconnectPeople: reconnectPeople ?? this.reconnectPeople,
        typicalMorning: typicalMorning ?? this.typicalMorning,
        typicalAfternoon: typicalAfternoon ?? this.typicalAfternoon,
        typicalEvening: typicalEvening ?? this.typicalEvening,
        onMind: onMind ?? this.onMind,
        activities: activities ?? this.activities,
        activitiesOther: activitiesOther ?? this.activitiesOther,
        topics: topics ?? this.topics,
        topicsOther: topicsOther ?? this.topicsOther,
        lifeChapters: lifeChapters ?? this.lifeChapters,
        avoidTopics: avoidTopics ?? this.avoidTopics,
        inputMode: inputMode ?? this.inputMode,
        preferredTimes: preferredTimes ?? this.preferredTimes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        completedParts: completedParts ?? this.completedParts,
        allCompleted: allCompleted ?? this.allCompleted,
        itemTimestamps: itemTimestamps ?? this.itemTimestamps,
      );

  Map<String, dynamic> toFirestore() => {
        'mainGoals': mainGoals,
        'mainGoalOther': mainGoalOther,
        'lonelinessTimings': lonelinessTimings,
        'importantPeople': importantPeople?.map((p) => p.toMap()).toList(),
        'reconnectPeople': reconnectPeople?.map((p) => p.toMap()).toList(),
        'typicalMorning': typicalMorning,
        'typicalAfternoon': typicalAfternoon,
        'typicalEvening': typicalEvening,
        'onMind': onMind,
        'activities': activities,
        'activitiesOther': activitiesOther,
        'topics': topics,
        'topicsOther': topicsOther,
        'lifeChapters': lifeChapters,
        'avoidTopics': avoidTopics,
        'inputMode': inputMode,
        'preferredTimes': preferredTimes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'completedParts': completedParts.toList(),
        'allCompleted': allCompleted,
        'itemTimestamps': {
          for (final e in itemTimestamps.entries)
            e.key: e.value?.toMap(),
        },
      };

  factory IntakeResponse.fromFirestore(Map<String, dynamic> map) {
    DateTime parseDate(dynamic v) {
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      try {
        final dynamic dyn = v;
        final result = dyn.toDate();
        if (result is DateTime) return result;
      } catch (_) {}
      return DateTime.now();
    }

    List<PersonEntry> parsePersonList(dynamic raw) {
      if (raw is! List) return [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map((m) => PersonEntry.fromMap(m))
          .toList();
    }

    final completedRaw = map['completedParts'];
    final completedParts = <int>{};
    if (completedRaw is List) {
      for (final v in completedRaw) {
        if (v is int) completedParts.add(v);
        if (v is num) completedParts.add(v.toInt());
      }
    }

    final timestampsRaw = map['itemTimestamps'];
    final itemTimestamps = <String, ItemTelemetry?>{};
    if (timestampsRaw is Map) {
      timestampsRaw.forEach((k, v) {
        if (k is String) {
          if (v == null) {
            itemTimestamps[k] = null;
          } else if (v is Map<String, dynamic>) {
            itemTimestamps[k] = ItemTelemetry.fromMap(v);
          }
        }
      });
    }

    return IntakeResponse(
      mainGoals: (map['mainGoals'] as List?)?.whereType<String>().toList() ?? [],
      mainGoalOther: map['mainGoalOther'] as String?,
      lonelinessTimings: (map['lonelinessTimings'] as List?)?.whereType<String>().toList(),
      importantPeople: parsePersonList(map['importantPeople']),
      reconnectPeople: parsePersonList(map['reconnectPeople']),
      typicalMorning: map['typicalMorning'] as String?,
      typicalAfternoon: map['typicalAfternoon'] as String?,
      typicalEvening: map['typicalEvening'] as String?,
      onMind: map['onMind'] as String?,
      activities: (map['activities'] as List?)?.whereType<String>().toList(),
      activitiesOther: map['activitiesOther'] as String?,
      topics: (map['topics'] as List?)?.whereType<String>().toList(),
      topicsOther: map['topicsOther'] as String?,
      lifeChapters: (map['lifeChapters'] as List?)?.whereType<String>().toList(),
      avoidTopics: map['avoidTopics'] as String?,
      inputMode: (map['inputMode'] as String?) ?? IntakeOptions.inputUnsure,
      preferredTimes: (map['preferredTimes'] as List?)?.whereType<String>().toList(),
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
      completedParts: completedParts,
      allCompleted: (map['allCompleted'] as bool?) ?? false,
      itemTimestamps: itemTimestamps,
    );
  }
}
