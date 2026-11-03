#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TimerPhase) {
    TimerPhaseWorking,
    TimerPhaseResting,
    TimerPhaseRestComplete,
    TimerPhaseSnoozingRest,
    TimerPhaseStopped
};

typedef NS_ENUM(NSInteger, BreakTimerRestAction) {
    BreakTimerRestActionStartNewRest,
    BreakTimerRestActionStartSnoozedRestNow,
    BreakTimerRestActionUnavailable
};

typedef struct {
    BOOL canStartWork;
    BOOL canStopStudy;
    BOOL canQuitApplication;
    BreakTimerRestAction restAction;
} BreakTimerActionPolicy;

FOUNDATION_EXPORT BreakTimerActionPolicy BreakTimerActionPolicyMake(TimerPhase phase,
                                                                     BOOL restObligationActive);
FOUNDATION_EXPORT NSTimeInterval BreakTimerRemainingRestAfterInactivity(NSTimeInterval remainingAtStart,
                                                                         NSTimeInterval inactiveDuration);
FOUNDATION_EXPORT BOOL BreakTimerAllDisplayStatesAreAsleep(NSArray<NSNumber *> *displaySleepStates);
FOUNDATION_EXPORT BOOL BreakTimerAnyDisplayStateIsAwake(NSArray<NSNumber *> *displaySleepStates);
FOUNDATION_EXPORT BOOL BreakTimerAllOnlineDisplaysAreAsleep(void);
FOUNDATION_EXPORT BOOL BreakTimerAnyOnlineDisplayIsAwake(void);
FOUNDATION_EXPORT NSTimeInterval BreakTimerContinuousTime(void);

NS_ASSUME_NONNULL_END
