#import "RestObligationStore.h"
#import <math.h>

static NSString * const RestObligationPendingKey = @"pendingRestObligation";
static NSString * const RestObligationRemainingKey = @"pendingRestRemainingSeconds";
static NSString * const RestObligationTotalKey = @"pendingRestTotalSeconds";
static NSString * const RestObligationSnoozeUsedKey = @"pendingRestSnoozeUsed";

@interface RestObligationSnapshot ()
@property (nonatomic, readwrite) BOOL pending;
@property (nonatomic, readwrite) NSTimeInterval remainingDuration;
@property (nonatomic, readwrite) NSTimeInterval totalDuration;
@property (nonatomic, readwrite) BOOL snoozeUsed;
@end

@implementation RestObligationSnapshot

- (instancetype)initWithPending:(BOOL)pending
              remainingDuration:(NSTimeInterval)remainingDuration
                  totalDuration:(NSTimeInterval)totalDuration
                     snoozeUsed:(BOOL)snoozeUsed {
    self = [super init];
    if (self) {
        _pending = pending;
        _remainingDuration = remainingDuration;
        _totalDuration = totalDuration;
        _snoozeUsed = snoozeUsed;
    }
    return self;
}

@end

@interface RestObligationStore ()
@property (nonatomic, strong) NSUserDefaults *userDefaults;
@end

@implementation RestObligationStore

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults {
    self = [super init];
    if (self) {
        _userDefaults = userDefaults;
    }
    return self;
}

- (RestObligationSnapshot *)snapshotWithDefaultDuration:(NSTimeInterval)defaultDuration {
    BOOL pending = [self.userDefaults boolForKey:RestObligationPendingKey];
    if (!pending) {
        return [[RestObligationSnapshot alloc] initWithPending:NO remainingDuration:0 totalDuration:0 snoozeUsed:NO];
    }

    NSTimeInterval storedRemaining = [self.userDefaults doubleForKey:RestObligationRemainingKey];
    NSTimeInterval safeDefault = MAX(1, defaultDuration);
    NSTimeInterval storedTotal = [self.userDefaults doubleForKey:RestObligationTotalKey];
    NSTimeInterval total = isfinite(storedTotal) && storedTotal > 0 ? storedTotal : safeDefault;
    NSTimeInterval remaining = isfinite(storedRemaining) && storedRemaining > 0 && storedRemaining <= total
        ? storedRemaining
        : total;
    return [[RestObligationSnapshot alloc] initWithPending:YES
                                         remainingDuration:remaining
                                             totalDuration:total
                                               snoozeUsed:[self.userDefaults boolForKey:RestObligationSnoozeUsedKey]];
}

- (void)saveRemainingDuration:(NSTimeInterval)remainingDuration
                 totalDuration:(NSTimeInterval)totalDuration
                    snoozeUsed:(BOOL)snoozeUsed
                 synchronously:(BOOL)synchronously {
    [self.userDefaults setBool:YES forKey:RestObligationPendingKey];
    [self.userDefaults setDouble:remainingDuration forKey:RestObligationRemainingKey];
    [self.userDefaults setDouble:totalDuration forKey:RestObligationTotalKey];
    [self.userDefaults setBool:snoozeUsed forKey:RestObligationSnoozeUsedKey];
    if (synchronously) {
        [self.userDefaults synchronize];
    }
}

- (void)clear {
    [self.userDefaults setBool:NO forKey:RestObligationPendingKey];
    [self.userDefaults removeObjectForKey:RestObligationRemainingKey];
    [self.userDefaults removeObjectForKey:RestObligationTotalKey];
    [self.userDefaults removeObjectForKey:RestObligationSnoozeUsedKey];
    [self.userDefaults synchronize];
}

@end
