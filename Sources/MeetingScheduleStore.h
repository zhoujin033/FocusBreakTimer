#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL MeetingScheduleIntervalForDate(NSDate *date,
                                                       NSCalendar *calendar,
                                                       NSDate * _Nullable * _Nullable startDate,
                                                       NSDate * _Nullable * _Nullable endDate);
FOUNDATION_EXPORT NSString *MeetingScheduleOccurrenceIdentifier(NSDate *date, NSCalendar *calendar);
FOUNDATION_EXPORT NSDate * _Nullable MeetingScheduleNextBoundaryAfterDate(NSDate *date, NSCalendar *calendar);

@interface MeetingScheduleStore : NSObject
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic, copy, nullable) NSString *handledOccurrenceIdentifier;
@property (nonatomic, copy, nullable) NSString *pendingAutoResumeOccurrenceIdentifier;
@property (nonatomic, strong, nullable) NSDate *pendingAutoResumeDate;
@property (nonatomic) BOOL stoppedBySchedule;
- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults;
- (void)markOccurrenceHandled:(NSString *)identifier
               autoResumeDate:(nullable NSDate *)autoResumeDate
            stoppedBySchedule:(BOOL)stoppedBySchedule;
- (void)markManualStudyStart;
- (void)cancelPendingAutoResume;
- (void)completePendingAutoResume;
@end

NS_ASSUME_NONNULL_END
