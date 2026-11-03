#import <Foundation/Foundation.h>
#import "MeetingScheduleStore.h"

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSCalendar *TestCalendar(void) {
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    return calendar;
}

static NSDate *Date(NSCalendar *calendar,
                    NSInteger year,
                    NSInteger month,
                    NSInteger day,
                    NSInteger hour,
                    NSInteger minute) {
    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.year = year;
    components.month = month;
    components.day = day;
    components.hour = hour;
    components.minute = minute;
    return [calendar dateFromComponents:components];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSCalendar *calendar = TestCalendar();
        NSDate *wednesdayAtStart = Date(calendar, 2026, 8, 12, 14, 0);
        NSDate *start = nil;
        NSDate *end = nil;
        Require(MeetingScheduleIntervalForDate(wednesdayAtStart, calendar, &start, &end),
                @"Wednesday should have a meeting interval");
        Require([start isEqualToDate:wednesdayAtStart], @"meeting should start at 14:00");
        Require([end isEqualToDate:Date(calendar, 2026, 8, 12, 17, 0)], @"meeting should end at 17:00");
        Require([MeetingScheduleOccurrenceIdentifier(wednesdayAtStart, calendar) isEqualToString:@"2026-08-12"],
                @"occurrence identifier should use the local date");

        NSDate *sunday = Date(calendar, 2026, 8, 16, 15, 0);
        Require(MeetingScheduleIntervalForDate(sunday, calendar, NULL, NULL), @"Sunday should have a meeting interval");
        for (NSNumber *day in @[@10, @11, @13, @14, @15]) {
            Require(!MeetingScheduleIntervalForDate(Date(calendar, 2026, 8, day.integerValue, 15, 0), calendar, NULL, NULL),
                    @"only Wednesday and Sunday should have meeting intervals, including no former Tuesday meeting");
        }

        NSDate *beforeWednesday = Date(calendar, 2026, 8, 12, 13, 59);
        Require([MeetingScheduleNextBoundaryAfterDate(beforeWednesday, calendar) isEqualToDate:wednesdayAtStart],
                @"next boundary before a meeting should be its start");
        NSDate *duringWednesday = Date(calendar, 2026, 8, 12, 16, 0);
        Require([MeetingScheduleNextBoundaryAfterDate(duringWednesday, calendar) isEqualToDate:end],
                @"next boundary during a meeting should be its end");
        Require([MeetingScheduleNextBoundaryAfterDate(end, calendar) isEqualToDate:Date(calendar, 2026, 8, 16, 14, 0)],
                @"at Wednesday's end the next boundary should be Sunday at 14:00");
        Require([MeetingScheduleNextBoundaryAfterDate(Date(calendar, 2026, 8, 16, 17, 0), calendar)
                 isEqualToDate:Date(calendar, 2026, 8, 19, 14, 0)],
                @"at Sunday's end the next boundary should be Wednesday at 14:00");

        NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.meeting-tests.%@", NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
        [defaults removePersistentDomainForName:suiteName];
        MeetingScheduleStore *store = [[MeetingScheduleStore alloc] initWithUserDefaults:defaults];
        Require(store.isEnabled, @"meeting schedule should default to enabled");
        [store markOccurrenceHandled:@"2026-08-12" autoResumeDate:end stoppedBySchedule:YES];
        Require(store.stoppedBySchedule && [store.pendingAutoResumeDate isEqualToDate:end],
                @"scheduled stop should persist its pending resume");
        MeetingScheduleStore *reopened = [[MeetingScheduleStore alloc]
            initWithUserDefaults:[[NSUserDefaults alloc] initWithSuiteName:suiteName]];
        Require(reopened.stoppedBySchedule &&
                [reopened.pendingAutoResumeOccurrenceIdentifier isEqualToString:@"2026-08-12"],
                @"meeting recovery metadata should survive reopening the app");
        [store markManualStudyStart];
        Require(!store.stoppedBySchedule && store.pendingAutoResumeDate != nil,
                @"manual early study should preserve the end event without forcing a reset");
        [store cancelPendingAutoResume];
        Require(store.pendingAutoResumeDate == nil && !store.stoppedBySchedule,
                @"manual stop or disabling the feature should cancel auto resume");
        [defaults removePersistentDomainForName:suiteName];
        NSLog(@"MeetingScheduleStore tests passed");
    }
    return 0;
}
