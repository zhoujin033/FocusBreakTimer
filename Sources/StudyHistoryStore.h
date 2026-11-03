#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const StudyHistoryDidChangeNotification;

@interface StudySessionRecord : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, strong, readonly) NSDate *startDate;
@property (nonatomic, strong, readonly) NSDate *endDate;
@property (nonatomic, readonly, getter=isActive) BOOL active;
@property (nonatomic, readonly) NSTimeInterval duration;

- (instancetype)initWithIdentifier:(NSString *)identifier
                          startDate:(NSDate *)startDate
                            endDate:(NSDate *)endDate
                             active:(BOOL)active;
@end

@interface StudyHistoryStore : NSObject
@property (nonatomic, strong, readonly) NSURL *storageURL;
@property (nonatomic, strong, readonly, nullable) NSDate *activeSessionStartDate;

+ (NSURL *)defaultStorageURL;
- (instancetype)initWithStorageURL:(NSURL *)storageURL;
- (void)recoverInterruptedSessionAtDate:(NSDate *)date;
- (void)beginSessionAtDate:(NSDate *)date;
- (void)endActiveSessionAtDate:(NSDate *)date;
- (void)updateHeartbeatAtDate:(NSDate *)date;
- (void)clearAllHistoryAtDate:(NSDate *)date restartSession:(BOOL)restartSession;
- (NSArray<StudySessionRecord *> *)sessionsIntersectingStartDate:(NSDate *)startDate
                                                         endDate:(NSDate *)endDate
                                                            now:(NSDate *)now;
- (nullable NSDate *)earliestSessionDate;
@end

NS_ASSUME_NONNULL_END
