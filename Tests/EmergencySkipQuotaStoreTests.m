#import <Foundation/Foundation.h>
#import "EmergencySkipQuotaStore.h"

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSCalendar *TestCalendar(void) {
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierISO8601];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    calendar.firstWeekday = 2;
    calendar.minimumDaysInFirstWeek = 4;
    return calendar;
}

static NSDate *Date(NSCalendar *calendar, NSInteger year, NSInteger month, NSInteger day, NSInteger hour) {
    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.year = year;
    components.month = month;
    components.day = day;
    components.hour = hour;
    return [calendar dateFromComponents:components];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *suiteName = [NSString stringWithFormat:@"local.codex.FocusBreakTimer.quota-tests.%@", NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
        [defaults removePersistentDomainForName:suiteName];
        NSCalendar *calendar = TestCalendar();
        EmergencySkipQuotaStore *store = [[EmergencySkipQuotaStore alloc] initWithUserDefaults:defaults
                                                                                      calendar:calendar];

        NSDate *monday = Date(calendar, 2026, 8, 10, 9);
        Require([store recordSuccessfulSkipAtDate:monday], @"first daily skip should be accepted");
        Require([store recordSuccessfulSkipAtDate:[monday dateByAddingTimeInterval:60]], @"second daily skip should be accepted");
        Require(![store recordSuccessfulSkipAtDate:[monday dateByAddingTimeInterval:120]], @"third daily skip should be rejected");
        EmergencySkipUsage *mondayUsage = [store usageAtDate:monday];
        Require(mondayUsage.dailyCount == 2 && mondayUsage.weeklyCount == 2,
                @"accepted skips should be counted for the day and week");
        Require(mondayUsage.limitReason == EmergencySkipLimitReasonDaily, @"daily limit should be reported first");

        NSDate *tuesday = Date(calendar, 2026, 8, 11, 9);
        EmergencySkipUsage *afterMidnight = [store usageAtDate:tuesday];
        Require(afterMidnight.dailyCount == 0 && afterMidnight.weeklyCount == 2,
                @"daily quota should reset at midnight without resetting the week");
        NSDate *wednesday = Date(calendar, 2026, 8, 12, 9);
        [store recordSuccessfulSkipAtDate:tuesday];
        [store recordSuccessfulSkipAtDate:[tuesday dateByAddingTimeInterval:60]];
        [store recordSuccessfulSkipAtDate:wednesday];
        [store recordSuccessfulSkipAtDate:[wednesday dateByAddingTimeInterval:60]];
        NSDate *thursday = Date(calendar, 2026, 8, 13, 9);
        EmergencySkipUsage *thursdayUsage = [store usageAtDate:thursday];
        Require(thursdayUsage.dailyCount == 0 && thursdayUsage.weeklyCount == 6,
                @"daily count should reset while weekly count remains");
        Require(thursdayUsage.limitReason == EmergencySkipLimitReasonWeekly,
                @"seventh weekly skip should be unavailable");
        Require(![store recordSuccessfulSkipAtDate:thursday], @"weekly limit should reject another skip");

        NSDate *nextMonday = Date(calendar, 2026, 8, 17, 9);
        EmergencySkipUsage *nextWeekUsage = [store usageAtDate:nextMonday];
        Require(nextWeekUsage.dailyCount == 0 && nextWeekUsage.weeklyCount == 0 && nextWeekUsage.canSkip,
                @"quota should reset at the next Monday boundary");

        EmergencySkipQuotaStore *reopened = [[EmergencySkipQuotaStore alloc]
            initWithUserDefaults:[[NSUserDefaults alloc] initWithSuiteName:suiteName]
                        calendar:calendar];
        Require([reopened usageAtDate:wednesday].weeklyCount == 6, @"usage should survive reopening the app");
        [defaults removePersistentDomainForName:suiteName];
        NSLog(@"EmergencySkipQuotaStore tests passed");
    }
    return 0;
}
