#import "BreakTimerPolicy.h"
#import <CoreGraphics/CoreGraphics.h>
#import <mach/mach_time.h>
#import <stdlib.h>

BreakTimerActionPolicy BreakTimerActionPolicyMake(TimerPhase phase, BOOL restObligationActive) {
    BreakTimerActionPolicy policy;
    policy.canStartWork = !restObligationActive;
    policy.canStopStudy = !restObligationActive && phase != TimerPhaseStopped;
    policy.canQuitApplication = !restObligationActive;

    if (phase == TimerPhaseResting) {
        policy.restAction = BreakTimerRestActionUnavailable;
    } else if (phase == TimerPhaseSnoozingRest) {
        policy.restAction = BreakTimerRestActionStartSnoozedRestNow;
    } else {
        policy.restAction = BreakTimerRestActionStartNewRest;
    }
    return policy;
}

NSTimeInterval BreakTimerRemainingRestAfterInactivity(NSTimeInterval remainingAtStart,
                                                       NSTimeInterval inactiveDuration) {
    return MAX(0, remainingAtStart - MAX(0, inactiveDuration));
}

BOOL BreakTimerAllDisplayStatesAreAsleep(NSArray<NSNumber *> *displaySleepStates) {
    if (displaySleepStates.count == 0) {
        return NO;
    }
    for (NSNumber *isAsleep in displaySleepStates) {
        if (!isAsleep.boolValue) {
            return NO;
        }
    }
    return YES;
}

BOOL BreakTimerAnyDisplayStateIsAwake(NSArray<NSNumber *> *displaySleepStates) {
    for (NSNumber *isAsleep in displaySleepStates) {
        if (!isAsleep.boolValue) {
            return YES;
        }
    }
    return NO;
}

static NSArray<NSNumber *> *BreakTimerOnlineDisplaySleepStates(void) {
    uint32_t displayCount = 0;
    if (CGGetOnlineDisplayList(0, NULL, &displayCount) != kCGErrorSuccess || displayCount == 0) {
        return @[];
    }

    CGDirectDisplayID *displayIDs = calloc(displayCount, sizeof(CGDirectDisplayID));
    if (!displayIDs) {
        return @[];
    }
    CGError error = CGGetOnlineDisplayList(displayCount, displayIDs, &displayCount);
    if (error != kCGErrorSuccess) {
        free(displayIDs);
        return @[];
    }

    NSMutableArray<NSNumber *> *states = [NSMutableArray arrayWithCapacity:displayCount];
    for (uint32_t index = 0; index < displayCount; index++) {
        [states addObject:@(CGDisplayIsAsleep(displayIDs[index]))];
    }
    free(displayIDs);
    return states;
}

BOOL BreakTimerAllOnlineDisplaysAreAsleep(void) {
    return BreakTimerAllDisplayStatesAreAsleep(BreakTimerOnlineDisplaySleepStates());
}

BOOL BreakTimerAnyOnlineDisplayIsAwake(void) {
    return BreakTimerAnyDisplayStateIsAwake(BreakTimerOnlineDisplaySleepStates());
}

NSTimeInterval BreakTimerContinuousTime(void) {
    static mach_timebase_info_data_t timebase;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mach_timebase_info(&timebase);
    });
    long double nanoseconds = (long double)mach_continuous_time() * timebase.numer / timebase.denom;
    return (NSTimeInterval)(nanoseconds / NSEC_PER_SEC);
}
