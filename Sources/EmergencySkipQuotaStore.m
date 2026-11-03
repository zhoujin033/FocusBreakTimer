#import "EmergencySkipQuotaStore.h"

static NSString * const EmergencySkipTimestampsKey = @"emergencySkipTimestamps";
static const NSInteger EmergencySkipDailyLimit = 2;
static const NSInteger EmergencySkipWeeklyLimit = 6;

@implementation EmergencySkipUsage

- (instancetype)initWithDailyCount:(NSInteger)dailyCount
                       weeklyCount:(NSInteger)weeklyCount
                       limitReason:(EmergencySkipLimitReason)limitReason {
    self = [super init];
    if (self) {
        _dailyCount = dailyCount;
        _weeklyCount = weeklyCount;
        _limitReason = limitReason;
    }
    return self;
}

- (BOOL)canSkip {
    return self.limitReason == EmergencySkipLimitReasonNone;
}

@end

@interface EmergencySkipQuotaStore ()
@property (nonatomic, strong) NSUserDefaults *userDefaults;
@property (nonatomic, copy) NSCalendar *calendar;
@property (nonatomic) BOOL followsSystemTimeZone;
@end

@implementation EmergencySkipQuotaStore

+ (NSInteger)dailyLimit {
    return EmergencySkipDailyLimit;
}

+ (NSInteger)weeklyLimit {
    return EmergencySkipWeeklyLimit;
}

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults {
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierISO8601];
    calendar.timeZone = NSTimeZone.localTimeZone;
    calendar.firstWeekday = 2;
    calendar.minimumDaysInFirstWeek = 4;
    self = [self initWithUserDefaults:userDefaults calendar:calendar];
    if (self) {
        _followsSystemTimeZone = YES;
    }
    return self;
}

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults calendar:(NSCalendar *)calendar {
    self = [super init];
    if (self) {
        _userDefaults = userDefaults;
        _calendar = calendar.copy;
    }
    return self;
}

- (NSArray<NSDate *> *)storedDates {
    NSArray *stored = [self.userDefaults arrayForKey:EmergencySkipTimestampsKey];
    if (![stored isKindOfClass:NSArray.class]) {
        return @[];
    }

    NSMutableArray<NSDate *> *dates = [NSMutableArray arrayWithCapacity:stored.count];
    for (id value in stored) {
        if ([value isKindOfClass:NSNumber.class]) {
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
            if (date) {
                [dates addObject:date];
            }
        }
    }
    return dates;
}

- (EmergencySkipUsage *)usageAtDate:(NSDate *)date {
    if (self.followsSystemTimeZone) {
        self.calendar.timeZone = NSTimeZone.localTimeZone;
    }
    NSDate *weekStart = nil;
    NSTimeInterval weekDuration = 0;
    BOOL hasWeek = [self.calendar rangeOfUnit:NSCalendarUnitWeekOfYear
                                    startDate:&weekStart
                                     interval:&weekDuration
                                      forDate:date];
    NSDate *weekEnd = hasWeek ? [weekStart dateByAddingTimeInterval:weekDuration] : date;

    NSInteger dailyCount = 0;
    NSInteger weeklyCount = 0;
    for (NSDate *eventDate in [self storedDates]) {
        if ([self.calendar isDate:eventDate inSameDayAsDate:date]) {
            dailyCount += 1;
        }
        if (hasWeek && [eventDate compare:weekStart] != NSOrderedAscending &&
            [eventDate compare:weekEnd] == NSOrderedAscending) {
            weeklyCount += 1;
        }
    }

    EmergencySkipLimitReason reason = EmergencySkipLimitReasonNone;
    if (dailyCount >= EmergencySkipDailyLimit) {
        reason = EmergencySkipLimitReasonDaily;
    } else if (weeklyCount >= EmergencySkipWeeklyLimit) {
        reason = EmergencySkipLimitReasonWeekly;
    }
    return [[EmergencySkipUsage alloc] initWithDailyCount:dailyCount
                                              weeklyCount:weeklyCount
                                              limitReason:reason];
}

- (BOOL)recordSuccessfulSkipAtDate:(NSDate *)date {
    if (![self usageAtDate:date].canSkip) {
        return NO;
    }

    NSMutableArray<NSNumber *> *timestamps = [NSMutableArray array];
    for (NSDate *storedDate in [self storedDates]) {
        [timestamps addObject:@(storedDate.timeIntervalSince1970)];
    }
    [timestamps addObject:@(date.timeIntervalSince1970)];
    [self.userDefaults setObject:timestamps forKey:EmergencySkipTimestampsKey];
    [self.userDefaults synchronize];
    return YES;
}

@end
