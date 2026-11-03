#import <Foundation/Foundation.h>
#import "StudyHistoryStore.h"
#import "StudyStatisticsCalculator.h"

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSCalendar *TestCalendar(void) {
    NSCalendar *calendar = [StudyStatisticsCalculator studyCalendar];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    return calendar;
}

static NSDate *Date(NSString *value) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSDate *date = [formatter dateFromString:value];
    Require(date != nil, [NSString stringWithFormat:@"invalid test date: %@", value]);
    return date;
}

static StudySessionRecord *Session(NSString *start, NSString *end) {
    return [[StudySessionRecord alloc] initWithIdentifier:NSUUID.UUID.UUIDString
                                                 startDate:Date(start)
                                                   endDate:Date(end)
                                                    active:NO];
}

static NSInteger IndexForDate(StudyActivitySnapshot *snapshot, NSDate *date, NSCalendar *calendar) {
    for (NSInteger index = 0; index < (NSInteger)snapshot.dates.count; index++) {
        if ([calendar isDate:snapshot.dates[(NSUInteger)index] inSameDayAsDate:date]) {
            return index;
        }
    }
    return -1;
}

static void TestActivityAggregation(void) {
    NSCalendar *calendar = TestCalendar();
    NSDate *now = Date(@"2026-08-04 12:00:00");
    NSArray *sessions = @[
        Session(@"2026-08-02 23:00:00", @"2026-08-03 01:00:00"),
        Session(@"2026-08-03 08:00:00", @"2026-08-03 10:00:00"),
        Session(@"2026-08-04 09:00:00", @"2026-08-04 12:00:00")
    ];
    StudyActivitySnapshot *snapshot = [StudyStatisticsCalculator activitySnapshotForSessions:sessions
                                                                                      calendar:calendar
                                                                                           now:now
                                                                                     weekCount:53];
    Require(snapshot.dates.count == 371, @"53 weeks should contain 371 date cells");
    NSInteger sunday = IndexForDate(snapshot, Date(@"2026-08-02 00:00:00"), calendar);
    NSInteger monday = IndexForDate(snapshot, Date(@"2026-08-03 00:00:00"), calendar);
    NSInteger tuesday = IndexForDate(snapshot, Date(@"2026-08-04 00:00:00"), calendar);
    NSInteger wednesday = IndexForDate(snapshot, Date(@"2026-08-05 00:00:00"), calendar);
    Require(sunday >= 0 && monday >= 0 && tuesday >= 0 && wednesday >= 0, @"test dates should be visible");
    Require(fabs(snapshot.dailyDurations[(NSUInteger)sunday].doubleValue - 3600) < 0.01, @"cross-week session should count on Sunday");
    Require(fabs(snapshot.dailyDurations[(NSUInteger)monday].doubleValue - 10800) < 0.01, @"Monday should include both session portions");
    Require(fabs(snapshot.weeklyDurations[(NSUInteger)monday].doubleValue - 21600) < 0.01, @"weekly total should repeat across current week");
    Require(fabs(snapshot.cumulativeDurations[(NSUInteger)sunday].doubleValue - 3600) < 0.01, @"cumulative total should include the previous week");
    Require(fabs(snapshot.cumulativeDurations[(NSUInteger)monday].doubleValue - 25200) < 0.01, @"current week should add to the visible cumulative total");
    Require(fabs(snapshot.cumulativeDurations[(NSUInteger)tuesday].doubleValue - 25200) < 0.01, @"cumulative mode should use one value for the whole week");
    Require(snapshot.weeklyDurations[(NSUInteger)wednesday].doubleValue == 0, @"future cells should not expose weekly values");
    Require(snapshot.cumulativeDurations[(NSUInteger)wednesday].doubleValue == 0, @"future cells should not expose cumulative values");
}

static void TestSummaryAndTodayGrace(void) {
    NSCalendar *calendar = TestCalendar();
    NSDate *now = Date(@"2026-08-04 12:00:00");
    NSArray *sessions = @[
        Session(@"2026-07-25 08:00:00", @"2026-07-25 14:00:00"),
        Session(@"2026-07-26 08:00:00", @"2026-07-26 14:00:00"),
        Session(@"2026-07-27 08:00:00", @"2026-07-27 14:00:00"),
        Session(@"2026-07-28 08:00:00", @"2026-07-28 14:00:00"),
        Session(@"2026-08-01 08:00:00", @"2026-08-01 14:00:00"),
        Session(@"2026-08-02 08:00:00", @"2026-08-02 14:00:00"),
        Session(@"2026-08-03 08:00:00", @"2026-08-03 15:00:00"),
        Session(@"2026-08-04 09:00:00", @"2026-08-04 11:00:00")
    ];
    StudyStatisticsSummary *summary = [StudyStatisticsCalculator summaryForSessions:sessions calendar:calendar now:now];
    Require(summary.currentStreakDays == 3, @"today below six hours should preserve the streak through yesterday");
    Require(summary.longestStreakDays == 4, @"longest streak should include the earlier four-day run");
    Require(fabs(summary.peakDayDuration - 25200) < 0.01, @"peak day should aggregate all daily study time");
    Require(fabs(summary.longestSessionDuration - 25200) < 0.01, @"longest session should use the real session duration");

    NSMutableArray *qualifiedTodaySessions = [sessions mutableCopy];
    [qualifiedTodaySessions addObject:Session(@"2026-08-04 12:00:00", @"2026-08-04 16:00:00")];
    StudyStatisticsSummary *qualifiedToday = [StudyStatisticsCalculator summaryForSessions:qualifiedTodaySessions
                                                                                    calendar:calendar
                                                                                         now:Date(@"2026-08-04 16:00:00")];
    Require(qualifiedToday.currentStreakDays == 4, @"today should join the streak after reaching six hours");
}

static void TestEmptyHistory(void) {
    NSCalendar *calendar = TestCalendar();
    NSDate *now = Date(@"2026-08-04 12:00:00");
    StudyStatisticsSummary *summary = [StudyStatisticsCalculator summaryForSessions:@[] calendar:calendar now:now];
    Require(summary.totalDuration == 0 && summary.currentStreakDays == 0 && summary.longestStreakDays == 0,
            @"empty history should produce zero summary values");
    StudyActivitySnapshot *snapshot = [StudyStatisticsCalculator activitySnapshotForSessions:@[]
                                                                                      calendar:calendar
                                                                                           now:now
                                                                                     weekCount:53];
    Require(snapshot.dates.count == 371, @"empty history should still produce the full calendar grid");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        TestActivityAggregation();
        TestSummaryAndTodayGrace();
        TestEmptyHistory();
        NSLog(@"StudyStatisticsCalculator tests passed");
    }
    return 0;
}
