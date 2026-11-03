#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, EmergencySkipLimitReason) {
    EmergencySkipLimitReasonNone,
    EmergencySkipLimitReasonDaily,
    EmergencySkipLimitReasonWeekly
};

@interface EmergencySkipUsage : NSObject
@property (nonatomic, readonly) NSInteger dailyCount;
@property (nonatomic, readonly) NSInteger weeklyCount;
@property (nonatomic, readonly) EmergencySkipLimitReason limitReason;
@property (nonatomic, readonly) BOOL canSkip;
- (instancetype)initWithDailyCount:(NSInteger)dailyCount
                       weeklyCount:(NSInteger)weeklyCount
                       limitReason:(EmergencySkipLimitReason)limitReason;
@end

@interface EmergencySkipQuotaStore : NSObject
@property (class, nonatomic, readonly) NSInteger dailyLimit;
@property (class, nonatomic, readonly) NSInteger weeklyLimit;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults;
- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults
                             calendar:(NSCalendar *)calendar NS_DESIGNATED_INITIALIZER;
- (EmergencySkipUsage *)usageAtDate:(NSDate *)date;
- (BOOL)recordSuccessfulSkipAtDate:(NSDate *)date;
@end

NS_ASSUME_NONNULL_END
