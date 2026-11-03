#import "MeetingScheduleStore.h"

static NSString * const MeetingScheduleEnabledKey = @"meetingScheduleEnabled";
static NSString * const MeetingScheduleHandledOccurrenceKey = @"meetingScheduleHandledOccurrence";
static NSString * const MeetingSchedulePendingOccurrenceKey = @"meetingSchedulePendingOccurrence";
static NSString * const MeetingSchedulePendingResumeDateKey = @"meetingSchedulePendingResumeDate";
static NSString * const MeetingScheduleStoppedByScheduleKey = @"meetingScheduleStoppedBySchedule";

static BOOL MeetingScheduleIsMeetingWeekday(NSInteger weekday) {
    return weekday == 1 || weekday == 4;
}

BOOL MeetingScheduleIntervalForDate(NSDate *date,
                                    NSCalendar *calendar,
                                    NSDate **startDate,
                                    NSDate **endDate) {
    NSDateComponents *weekdayComponents = [calendar components:NSCalendarUnitWeekday fromDate:date];
    if (!MeetingScheduleIsMeetingWeekday(weekdayComponents.weekday)) {
        return NO;
    }

    NSDate *dayStart = [calendar startOfDayForDate:date];
    NSDateComponents *startOffset = [[NSDateComponents alloc] init];
    startOffset.hour = 14;
    startOffset.minute = 0;
    NSDateComponents *endOffset = [[NSDateComponents alloc] init];
    endOffset.hour = 17;
    endOffset.minute = 0;
    NSDate *start = [calendar dateByAddingComponents:startOffset toDate:dayStart options:0];
    NSDate *end = [calendar dateByAddingComponents:endOffset toDate:dayStart options:0];
    if (!start || !end) {
        return NO;
    }
    if (startDate) {
        *startDate = start;
    }
    if (endDate) {
        *endDate = end;
    }
    return YES;
}

NSString *MeetingScheduleOccurrenceIdentifier(NSDate *date, NSCalendar *calendar) {
    NSDateComponents *components = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
                                                fromDate:date];
    return [NSString stringWithFormat:@"%04ld-%02ld-%02ld",
            (long)components.year, (long)components.month, (long)components.day];
}

NSDate *MeetingScheduleNextBoundaryAfterDate(NSDate *date, NSCalendar *calendar) {
    NSDate *candidate = nil;
    for (NSInteger dayOffset = 0; dayOffset <= 7; dayOffset++) {
        NSDateComponents *offset = [[NSDateComponents alloc] init];
        offset.day = dayOffset;
        NSDate *day = [calendar dateByAddingComponents:offset toDate:date options:0];
        NSDate *start = nil;
        NSDate *end = nil;
        if (!day || !MeetingScheduleIntervalForDate(day, calendar, &start, &end)) {
            continue;
        }
        for (NSDate *boundary in @[start, end]) {
            if ([boundary compare:date] != NSOrderedDescending) {
                continue;
            }
            if (!candidate || [boundary compare:candidate] == NSOrderedAscending) {
                candidate = boundary;
            }
        }
    }
    return candidate;
}

@interface MeetingScheduleStore ()
@property (nonatomic, strong) NSUserDefaults *userDefaults;
@end

@implementation MeetingScheduleStore

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults {
    self = [super init];
    if (self) {
        _userDefaults = userDefaults;
        [_userDefaults registerDefaults:@{MeetingScheduleEnabledKey: @YES}];
    }
    return self;
}

- (BOOL)isEnabled {
    return [self.userDefaults boolForKey:MeetingScheduleEnabledKey];
}

- (void)setEnabled:(BOOL)enabled {
    [self.userDefaults setBool:enabled forKey:MeetingScheduleEnabledKey];
    [self.userDefaults synchronize];
}

- (NSString *)handledOccurrenceIdentifier {
    return [self.userDefaults stringForKey:MeetingScheduleHandledOccurrenceKey];
}

- (void)setHandledOccurrenceIdentifier:(NSString *)identifier {
    if (identifier) {
        [self.userDefaults setObject:identifier forKey:MeetingScheduleHandledOccurrenceKey];
    } else {
        [self.userDefaults removeObjectForKey:MeetingScheduleHandledOccurrenceKey];
    }
}

- (NSString *)pendingAutoResumeOccurrenceIdentifier {
    return [self.userDefaults stringForKey:MeetingSchedulePendingOccurrenceKey];
}

- (void)setPendingAutoResumeOccurrenceIdentifier:(NSString *)identifier {
    if (identifier) {
        [self.userDefaults setObject:identifier forKey:MeetingSchedulePendingOccurrenceKey];
    } else {
        [self.userDefaults removeObjectForKey:MeetingSchedulePendingOccurrenceKey];
    }
}

- (NSDate *)pendingAutoResumeDate {
    id value = [self.userDefaults objectForKey:MeetingSchedulePendingResumeDateKey];
    return [value isKindOfClass:NSDate.class] ? value : nil;
}

- (void)setPendingAutoResumeDate:(NSDate *)date {
    if (date) {
        [self.userDefaults setObject:date forKey:MeetingSchedulePendingResumeDateKey];
    } else {
        [self.userDefaults removeObjectForKey:MeetingSchedulePendingResumeDateKey];
    }
}

- (BOOL)stoppedBySchedule {
    return [self.userDefaults boolForKey:MeetingScheduleStoppedByScheduleKey];
}

- (void)setStoppedBySchedule:(BOOL)stoppedBySchedule {
    [self.userDefaults setBool:stoppedBySchedule forKey:MeetingScheduleStoppedByScheduleKey];
}

- (void)markOccurrenceHandled:(NSString *)identifier
               autoResumeDate:(NSDate *)autoResumeDate
            stoppedBySchedule:(BOOL)stoppedBySchedule {
    self.handledOccurrenceIdentifier = identifier;
    self.pendingAutoResumeOccurrenceIdentifier = autoResumeDate ? identifier : nil;
    self.pendingAutoResumeDate = autoResumeDate;
    self.stoppedBySchedule = stoppedBySchedule;
    [self.userDefaults synchronize];
}

- (void)markManualStudyStart {
    self.stoppedBySchedule = NO;
    [self.userDefaults synchronize];
}

- (void)cancelPendingAutoResume {
    self.pendingAutoResumeOccurrenceIdentifier = nil;
    self.pendingAutoResumeDate = nil;
    self.stoppedBySchedule = NO;
    [self.userDefaults synchronize];
}

- (void)completePendingAutoResume {
    [self cancelPendingAutoResume];
}

@end
