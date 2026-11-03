#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RestObligationSnapshot : NSObject
@property (nonatomic, readonly) BOOL pending;
@property (nonatomic, readonly) NSTimeInterval remainingDuration;
@property (nonatomic, readonly) NSTimeInterval totalDuration;
@property (nonatomic, readonly) BOOL snoozeUsed;
- (instancetype)initWithPending:(BOOL)pending
              remainingDuration:(NSTimeInterval)remainingDuration
                  totalDuration:(NSTimeInterval)totalDuration
                    snoozeUsed:(BOOL)snoozeUsed;
@end

@interface RestObligationStore : NSObject
- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults;
- (RestObligationSnapshot *)snapshotWithDefaultDuration:(NSTimeInterval)defaultDuration;
- (void)saveRemainingDuration:(NSTimeInterval)remainingDuration
                 totalDuration:(NSTimeInterval)totalDuration
                    snoozeUsed:(BOOL)snoozeUsed
                 synchronously:(BOOL)synchronously;
- (void)clear;
@end

NS_ASSUME_NONNULL_END
