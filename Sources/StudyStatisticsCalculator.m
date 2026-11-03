#import "StudyStatisticsCalculator.h"
#import "StudyHistoryStore.h"

static const NSTimeInterval StudyStreakThreshold = 6.0 * 60.0 * 60.0;

@interface StudyStatisticsSummary ()
@property (nonatomic, readwrite) NSTimeInterval totalDuration;
@property (nonatomic, readwrite) NSTimeInterval peakDayDuration;
@property (nonatomic, readwrite) NSTimeInterval longestSessionDuration;
@property (nonatomic, readwrite) NSInteger currentStreakDays;
@property (nonatomic, readwrite) NSInteger longestStreakDays;
@end

@implementation StudyStatisticsSummary
@end

@interface StudyActivitySnapshot ()
@property (nonatomic, copy, readwrite) NSArray<NSDate *> *dates;
@property (nonatomic, copy, readwrite) NSArray<NSNumber *> *dailyDurations;
@property (nonatomic, copy, readwrite) NSArray<NSNumber *> *weeklyDurations;
@property (nonatomic, copy, readwrite) NSArray<NSNumber *> *cumulativeDurations;
@property (nonatomic, strong, readwrite) NSDate *today;
@property (nonatomic, readwrite) NSInteger weekCount;
@end

@implementation StudyActivitySnapshot

- (NSArray<NSNumber *> *)durationsForMode:(StudyActivityAggregationMode)mode {
    switch (mode) {
        case StudyActivityAggregationModeWeekly:
            return self.weeklyDurations;
        case StudyActivityAggregationModeCumulative:
            return self.cumulativeDurations;
        case StudyActivityAggregationModeDaily:
        default:
            return self.dailyDurations;
    }
}

@end

@implementation StudyStatisticsCalculator

+ (NSCalendar *)studyCalendar {
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    calendar.timeZone = NSTimeZone.localTimeZone;
    calendar.firstWeekday = 2;
    calendar.minimumDaysInFirstWeek = 1;
    return calendar;
}

+ (StudyStatisticsSummary *)summaryForSessions:(NSArray<StudySessionRecord *> *)sessions
                                       calendar:(NSCalendar *)calendar
                                            now:(NSDate *)now {
    StudyStatisticsSummary *summary = [[StudyStatisticsSummary alloc] init];
    NSDictionary<NSDate *, NSNumber *> *dailyTotals = [self dailyTotalsForSessions:sessions calendar:calendar];

    for (StudySessionRecord *session in sessions) {
        summary.totalDuration += session.duration;
        summary.longestSessionDuration = MAX(summary.longestSessionDuration, session.duration);
    }
    for (NSNumber *duration in dailyTotals.allValues) {
        summary.peakDayDuration = MAX(summary.peakDayDuration, duration.doubleValue);
    }

    NSDate *today = [calendar startOfDayForDate:now];
    NSDate *streakEnd = [self durationForDay:today inDailyTotals:dailyTotals] >= StudyStreakThreshold
        ? today
        : [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:today options:0];
    while (streakEnd && [self durationForDay:streakEnd inDailyTotals:dailyTotals] >= StudyStreakThreshold) {
        summary.currentStreakDays++;
        streakEnd = [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:streakEnd options:0];
    }

    NSArray<NSDate *> *qualifiedDays = [[dailyTotals keysOfEntriesPassingTest:^BOOL(NSDate *day, NSNumber *duration, BOOL *stop) {
        return [day compare:today] != NSOrderedDescending && duration.doubleValue >= StudyStreakThreshold;
    }].allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSInteger runningStreak = 0;
    NSDate *previousDay = nil;
    for (NSDate *day in qualifiedDays) {
        if (previousDay) {
            NSDate *expectedDay = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:previousDay options:0];
            runningStreak = expectedDay && [calendar isDate:day inSameDayAsDate:expectedDay]
                ? runningStreak + 1
                : 1;
        } else {
            runningStreak = 1;
        }
        summary.longestStreakDays = MAX(summary.longestStreakDays, runningStreak);
        previousDay = day;
    }

    return summary;
}

+ (StudyActivitySnapshot *)activitySnapshotForSessions:(NSArray<StudySessionRecord *> *)sessions
                                               calendar:(NSCalendar *)calendar
                                                    now:(NSDate *)now
                                              weekCount:(NSInteger)weekCount {
    NSInteger normalizedWeekCount = MAX(1, weekCount);
    NSDate *today = [calendar startOfDayForDate:now];
    NSDate *currentWeekStart = [self startOfWeekForDate:today calendar:calendar];
    NSDate *gridStart = [calendar dateByAddingUnit:NSCalendarUnitDay
                                             value:-7 * (normalizedWeekCount - 1)
                                            toDate:currentWeekStart
                                           options:0] ?: currentWeekStart;
    NSDictionary<NSDate *, NSNumber *> *dailyTotals = [self dailyTotalsForSessions:sessions calendar:calendar];

    NSMutableArray<NSDate *> *dates = [NSMutableArray arrayWithCapacity:normalizedWeekCount * 7];
    NSMutableArray<NSNumber *> *dailyDurations = [NSMutableArray arrayWithCapacity:normalizedWeekCount * 7];
    NSMutableArray<NSNumber *> *weeklyDurations = [NSMutableArray arrayWithCapacity:normalizedWeekCount * 7];
    NSMutableArray<NSNumber *> *cumulativeDurations = [NSMutableArray arrayWithCapacity:normalizedWeekCount * 7];
    NSTimeInterval cumulativeTotal = 0;

    for (NSInteger week = 0; week < normalizedWeekCount; week++) {
        NSMutableArray<NSDate *> *weekDates = [NSMutableArray arrayWithCapacity:7];
        NSMutableArray<NSNumber *> *weekDailyDurations = [NSMutableArray arrayWithCapacity:7];
        NSTimeInterval weekTotal = 0;
        for (NSInteger weekday = 0; weekday < 7; weekday++) {
            NSInteger dayOffset = week * 7 + weekday;
            NSDate *date = [calendar dateByAddingUnit:NSCalendarUnitDay value:dayOffset toDate:gridStart options:0] ?: gridStart;
            NSTimeInterval duration = [date compare:today] == NSOrderedDescending
                ? 0
                : [self durationForDay:date inDailyTotals:dailyTotals];
            [weekDates addObject:date];
            [weekDailyDurations addObject:@(duration)];
            weekTotal += duration;
        }

        cumulativeTotal += weekTotal;
        for (NSInteger weekday = 0; weekday < 7; weekday++) {
            NSDate *date = weekDates[(NSUInteger)weekday];
            NSTimeInterval duration = weekDailyDurations[(NSUInteger)weekday].doubleValue;
            [dates addObject:date];
            [dailyDurations addObject:@(duration)];
            [weeklyDurations addObject:([date compare:today] == NSOrderedDescending ? @0 : @(weekTotal))];
            [cumulativeDurations addObject:([date compare:today] == NSOrderedDescending ? @0 : @(cumulativeTotal))];
        }
    }

    StudyActivitySnapshot *snapshot = [[StudyActivitySnapshot alloc] init];
    snapshot.dates = dates;
    snapshot.dailyDurations = dailyDurations;
    snapshot.weeklyDurations = weeklyDurations;
    snapshot.cumulativeDurations = cumulativeDurations;
    snapshot.today = today;
    snapshot.weekCount = normalizedWeekCount;
    return snapshot;
}

+ (NSTimeInterval)totalDurationForSessions:(NSArray<StudySessionRecord *> *)sessions
                                  startDate:(NSDate *)startDate
                                    endDate:(NSDate *)endDate {
    NSTimeInterval total = 0;
    for (StudySessionRecord *session in sessions) {
        NSDate *intersectionStart = [session.startDate compare:startDate] == NSOrderedAscending ? startDate : session.startDate;
        NSDate *intersectionEnd = [session.endDate compare:endDate] == NSOrderedDescending ? endDate : session.endDate;
        if ([intersectionEnd compare:intersectionStart] == NSOrderedDescending) {
            total += [intersectionEnd timeIntervalSinceDate:intersectionStart];
        }
    }
    return total;
}

+ (NSDictionary<NSDate *, NSNumber *> *)dailyTotalsForSessions:(NSArray<StudySessionRecord *> *)sessions
                                                       calendar:(NSCalendar *)calendar {
    NSMutableDictionary<NSDate *, NSNumber *> *totals = [NSMutableDictionary dictionary];
    for (StudySessionRecord *session in sessions) {
        NSDate *cursor = session.startDate;
        while ([cursor compare:session.endDate] == NSOrderedAscending) {
            NSDate *dayStart = [calendar startOfDayForDate:cursor];
            NSDate *nextDay = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:dayStart options:0];
            if (!nextDay) {
                break;
            }
            NSDate *segmentEnd = [session.endDate compare:nextDay] == NSOrderedAscending ? session.endDate : nextDay;
            NSTimeInterval duration = [segmentEnd timeIntervalSinceDate:cursor];
            if (duration > 0) {
                totals[dayStart] = @(totals[dayStart].doubleValue + duration);
            }
            cursor = segmentEnd;
        }
    }
    return totals;
}

+ (NSTimeInterval)durationForDay:(NSDate *)day
                    inDailyTotals:(NSDictionary<NSDate *, NSNumber *> *)dailyTotals {
    return dailyTotals[day].doubleValue;
}

+ (NSDate *)startOfWeekForDate:(NSDate *)date calendar:(NSCalendar *)calendar {
    NSDate *dayStart = [calendar startOfDayForDate:date];
    NSInteger weekday = [calendar component:NSCalendarUnitWeekday fromDate:dayStart];
    NSInteger daysSinceMonday = (weekday + 5) % 7;
    return [calendar dateByAddingUnit:NSCalendarUnitDay value:-daysSinceMonday toDate:dayStart options:0] ?: dayStart;
}

@end
