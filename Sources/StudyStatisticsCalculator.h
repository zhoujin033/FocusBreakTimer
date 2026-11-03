#import <Foundation/Foundation.h>

@class StudySessionRecord;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, StudyActivityAggregationMode) {
    StudyActivityAggregationModeDaily,
    StudyActivityAggregationModeWeekly,
    StudyActivityAggregationModeCumulative
};

@interface StudyStatisticsSummary : NSObject
@property (nonatomic, readonly) NSTimeInterval totalDuration;
@property (nonatomic, readonly) NSTimeInterval peakDayDuration;
@property (nonatomic, readonly) NSTimeInterval longestSessionDuration;
@property (nonatomic, readonly) NSInteger currentStreakDays;
@property (nonatomic, readonly) NSInteger longestStreakDays;
@end

@interface StudyActivitySnapshot : NSObject
@property (nonatomic, copy, readonly) NSArray<NSDate *> *dates;
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *dailyDurations;
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *weeklyDurations;
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *cumulativeDurations;
@property (nonatomic, strong, readonly) NSDate *today;
@property (nonatomic, readonly) NSInteger weekCount;

- (NSArray<NSNumber *> *)durationsForMode:(StudyActivityAggregationMode)mode;
@end

@interface StudyStatisticsCalculator : NSObject
+ (NSCalendar *)studyCalendar;
+ (StudyStatisticsSummary *)summaryForSessions:(NSArray<StudySessionRecord *> *)sessions
                                       calendar:(NSCalendar *)calendar
                                            now:(NSDate *)now;
+ (StudyActivitySnapshot *)activitySnapshotForSessions:(NSArray<StudySessionRecord *> *)sessions
                                               calendar:(NSCalendar *)calendar
                                                    now:(NSDate *)now
                                              weekCount:(NSInteger)weekCount;
+ (NSTimeInterval)totalDurationForSessions:(NSArray<StudySessionRecord *> *)sessions
                                  startDate:(NSDate *)startDate
                                    endDate:(NSDate *)endDate;
@end

NS_ASSUME_NONNULL_END
