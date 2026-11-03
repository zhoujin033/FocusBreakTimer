#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    BOOL anyInputHeld;
    NSTimeInterval idleDuration;
} DisplaySleepInputSnapshot;

@protocol DisplaySleepInputStateProviding <NSObject>
- (DisplaySleepInputSnapshot)inputSnapshot;
@end

@interface DisplaySleepInputStateProvider : NSObject <DisplaySleepInputStateProviding>
@end

@protocol DisplayPowerControlling <NSObject>
- (BOOL)beginRestActivityForDuration:(NSTimeInterval)duration error:(NSError **)error;
- (void)requestDisplaySleepWithCompletion:(void (^)(NSError * _Nullable error))completion;
- (void)cancelDisplaySleepRequest;
- (BOOL)wakeDisplaysWithError:(NSError **)error;
- (void)endRestActivity;
@end

@interface DisplayPowerController : NSObject <DisplayPowerControlling>
@end

NS_ASSUME_NONNULL_END
