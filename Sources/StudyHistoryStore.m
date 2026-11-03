#import "StudyHistoryStore.h"

NSNotificationName const StudyHistoryDidChangeNotification = @"StudyHistoryDidChangeNotification";

static const NSInteger StudyHistorySchemaVersion = 1;
static const NSTimeInterval StudyHistoryHeartbeatInterval = 30.0;

@implementation StudySessionRecord

- (instancetype)initWithIdentifier:(NSString *)identifier
                          startDate:(NSDate *)startDate
                            endDate:(NSDate *)endDate
                             active:(BOOL)active {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _startDate = startDate;
        _endDate = endDate;
        _active = active;
    }
    return self;
}

- (NSTimeInterval)duration {
    return MAX(0, [self.endDate timeIntervalSinceDate:self.startDate]);
}

@end

@interface StudyHistoryStore ()
@property (nonatomic, strong, readwrite) NSURL *storageURL;
@property (nonatomic, strong) NSMutableArray<StudySessionRecord *> *completedSessions;
@property (nonatomic, strong, readwrite, nullable) NSDate *activeSessionStartDate;
@property (nonatomic, strong, nullable) NSDate *activeSessionHeartbeatDate;
@end

@implementation StudyHistoryStore

+ (NSURL *)defaultStorageURL {
    NSURL *applicationSupportURL = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                                         inDomains:NSUserDomainMask].firstObject;
    if (!applicationSupportURL) {
        applicationSupportURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    }
    NSURL *folderURL = [applicationSupportURL URLByAppendingPathComponent:@"local.codex.FocusBreakTimer" isDirectory:YES];
    return [folderURL URLByAppendingPathComponent:@"study-history.json" isDirectory:NO];
}

- (instancetype)initWithStorageURL:(NSURL *)storageURL {
    self = [super init];
    if (self) {
        _storageURL = storageURL;
        _completedSessions = [NSMutableArray array];
        [self loadHistory];
    }
    return self;
}

- (void)loadHistory {
    NSData *data = [NSData dataWithContentsOfURL:self.storageURL];
    if (!data) {
        return;
    }

    NSError *error = nil;
    id rootObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![rootObject isKindOfClass:NSDictionary.class]) {
        [self preserveCorruptHistoryWithError:error];
        return;
    }

    NSDictionary *root = (NSDictionary *)rootObject;
    NSNumber *schemaVersion = root[@"schemaVersion"];
    if (![schemaVersion isKindOfClass:NSNumber.class] || schemaVersion.integerValue != StudyHistorySchemaVersion) {
        [self preserveCorruptHistoryWithError:nil];
        return;
    }

    NSArray *sessionObjects = root[@"sessions"];
    if ([sessionObjects isKindOfClass:NSArray.class]) {
        for (id object in sessionObjects) {
            StudySessionRecord *record = [self recordFromDictionary:object active:NO];
            if (record) {
                [self.completedSessions addObject:record];
            }
        }
    }
    [self sortCompletedSessions];

    id activeObject = root[@"activeSession"];
    if ([activeObject isKindOfClass:NSDictionary.class]) {
        NSNumber *startTimestamp = activeObject[@"start"];
        NSNumber *heartbeatTimestamp = activeObject[@"lastHeartbeat"];
        if ([startTimestamp isKindOfClass:NSNumber.class] && [heartbeatTimestamp isKindOfClass:NSNumber.class]) {
            NSDate *startDate = [NSDate dateWithTimeIntervalSince1970:startTimestamp.doubleValue];
            NSDate *heartbeatDate = [NSDate dateWithTimeIntervalSince1970:heartbeatTimestamp.doubleValue];
            if ([heartbeatDate compare:startDate] != NSOrderedAscending) {
                self.activeSessionStartDate = startDate;
                self.activeSessionHeartbeatDate = heartbeatDate;
            }
        }
    }
}

- (nullable StudySessionRecord *)recordFromDictionary:(id)object active:(BOOL)active {
    if (![object isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSDictionary *dictionary = (NSDictionary *)object;
    NSString *identifier = dictionary[@"id"];
    NSNumber *startTimestamp = dictionary[@"start"];
    NSNumber *endTimestamp = dictionary[@"end"];
    if (![identifier isKindOfClass:NSString.class] ||
        ![startTimestamp isKindOfClass:NSNumber.class] ||
        ![endTimestamp isKindOfClass:NSNumber.class]) {
        return nil;
    }

    NSDate *startDate = [NSDate dateWithTimeIntervalSince1970:startTimestamp.doubleValue];
    NSDate *endDate = [NSDate dateWithTimeIntervalSince1970:endTimestamp.doubleValue];
    if ([endDate compare:startDate] != NSOrderedDescending) {
        return nil;
    }
    return [[StudySessionRecord alloc] initWithIdentifier:identifier
                                                 startDate:startDate
                                                   endDate:endDate
                                                    active:active];
}

- (void)preserveCorruptHistoryWithError:(nullable NSError *)error {
    NSString *backupName = [NSString stringWithFormat:@"study-history.corrupt-%@.json", NSUUID.UUID.UUIDString];
    NSURL *backupURL = [self.storageURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:backupName];
    NSError *moveError = nil;
    [NSFileManager.defaultManager moveItemAtURL:self.storageURL toURL:backupURL error:&moveError];
    NSLog(@"Study history could not be loaded (%@); backup result: %@", error, moveError ?: @"saved");
}

- (void)sortCompletedSessions {
    [self.completedSessions sortUsingComparator:^NSComparisonResult(StudySessionRecord *left, StudySessionRecord *right) {
        return [left.startDate compare:right.startDate];
    }];
}

- (void)recoverInterruptedSessionAtDate:(NSDate *)date {
    if (!self.activeSessionStartDate || !self.activeSessionHeartbeatDate) {
        return;
    }

    NSDate *recoveryEnd = [self.activeSessionHeartbeatDate compare:date] == NSOrderedDescending
        ? date
        : self.activeSessionHeartbeatDate;
    [self appendCompletedSessionFromDate:self.activeSessionStartDate toDate:recoveryEnd];
    self.activeSessionStartDate = nil;
    self.activeSessionHeartbeatDate = nil;
    [self persistAndNotify];
}

- (void)beginSessionAtDate:(NSDate *)date {
    if (self.activeSessionStartDate) {
        [self appendCompletedSessionFromDate:self.activeSessionStartDate toDate:date];
    }
    self.activeSessionStartDate = date;
    self.activeSessionHeartbeatDate = date;
    [self persistAndNotify];
}

- (void)endActiveSessionAtDate:(NSDate *)date {
    if (!self.activeSessionStartDate) {
        return;
    }
    [self appendCompletedSessionFromDate:self.activeSessionStartDate toDate:date];
    self.activeSessionStartDate = nil;
    self.activeSessionHeartbeatDate = nil;
    [self persistAndNotify];
}

- (void)updateHeartbeatAtDate:(NSDate *)date {
    if (!self.activeSessionStartDate || !self.activeSessionHeartbeatDate ||
        [date timeIntervalSinceDate:self.activeSessionHeartbeatDate] < StudyHistoryHeartbeatInterval) {
        return;
    }
    self.activeSessionHeartbeatDate = date;
    [self persistAndNotify];
}

- (void)clearAllHistoryAtDate:(NSDate *)date restartSession:(BOOL)restartSession {
    [self.completedSessions removeAllObjects];
    self.activeSessionStartDate = restartSession ? date : nil;
    self.activeSessionHeartbeatDate = restartSession ? date : nil;
    [self persistAndNotify];
}

- (void)appendCompletedSessionFromDate:(NSDate *)startDate toDate:(NSDate *)endDate {
    if ([endDate compare:startDate] != NSOrderedDescending) {
        return;
    }
    StudySessionRecord *record = [[StudySessionRecord alloc] initWithIdentifier:NSUUID.UUID.UUIDString
                                                                      startDate:startDate
                                                                        endDate:endDate
                                                                         active:NO];
    [self.completedSessions addObject:record];
    [self sortCompletedSessions];
}

- (NSArray<StudySessionRecord *> *)sessionsIntersectingStartDate:(NSDate *)startDate
                                                         endDate:(NSDate *)endDate
                                                            now:(NSDate *)now {
    if ([endDate compare:startDate] != NSOrderedDescending) {
        return @[];
    }

    NSMutableArray<StudySessionRecord *> *results = [NSMutableArray array];
    for (StudySessionRecord *record in self.completedSessions) {
        StudySessionRecord *clipped = [self clippedRecord:record startDate:startDate endDate:endDate active:NO];
        if (clipped) {
            [results addObject:clipped];
        }
    }

    if (self.activeSessionStartDate) {
        NSDate *activeEndDate = [now compare:self.activeSessionStartDate] == NSOrderedAscending
            ? self.activeSessionStartDate
            : now;
        StudySessionRecord *activeRecord = [[StudySessionRecord alloc] initWithIdentifier:@"active"
                                                                                 startDate:self.activeSessionStartDate
                                                                                   endDate:activeEndDate
                                                                                    active:YES];
        StudySessionRecord *clipped = [self clippedRecord:activeRecord startDate:startDate endDate:endDate active:YES];
        if (clipped) {
            [results addObject:clipped];
        }
    }

    [results sortUsingComparator:^NSComparisonResult(StudySessionRecord *left, StudySessionRecord *right) {
        return [left.startDate compare:right.startDate];
    }];
    return results;
}

- (nullable StudySessionRecord *)clippedRecord:(StudySessionRecord *)record
                                     startDate:(NSDate *)rangeStart
                                       endDate:(NSDate *)rangeEnd
                                        active:(BOOL)active {
    NSDate *clippedStart = [record.startDate compare:rangeStart] == NSOrderedAscending ? rangeStart : record.startDate;
    NSDate *clippedEnd = [record.endDate compare:rangeEnd] == NSOrderedDescending ? rangeEnd : record.endDate;
    if ([clippedEnd compare:clippedStart] != NSOrderedDescending) {
        return nil;
    }
    return [[StudySessionRecord alloc] initWithIdentifier:record.identifier
                                                 startDate:clippedStart
                                                   endDate:clippedEnd
                                                    active:active];
}

- (nullable NSDate *)earliestSessionDate {
    NSDate *earliest = self.completedSessions.firstObject.startDate;
    if (self.activeSessionStartDate && (!earliest || [self.activeSessionStartDate compare:earliest] == NSOrderedAscending)) {
        earliest = self.activeSessionStartDate;
    }
    return earliest;
}

- (void)persistAndNotify {
    [self persistHistory];
    [NSNotificationCenter.defaultCenter postNotificationName:StudyHistoryDidChangeNotification object:self];
}

- (void)persistHistory {
    NSURL *folderURL = self.storageURL.URLByDeletingLastPathComponent;
    NSError *directoryError = nil;
    [NSFileManager.defaultManager createDirectoryAtURL:folderURL
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:&directoryError];
    if (directoryError) {
        NSLog(@"Could not create study history directory: %@", directoryError);
        return;
    }

    NSMutableArray<NSDictionary *> *serializedSessions = [NSMutableArray arrayWithCapacity:self.completedSessions.count];
    for (StudySessionRecord *record in self.completedSessions) {
        [serializedSessions addObject:@{
            @"id": record.identifier,
            @"start": @(record.startDate.timeIntervalSince1970),
            @"end": @(record.endDate.timeIntervalSince1970)
        }];
    }

    NSMutableDictionary *root = [@{
        @"schemaVersion": @(StudyHistorySchemaVersion),
        @"sessions": serializedSessions
    } mutableCopy];
    if (self.activeSessionStartDate && self.activeSessionHeartbeatDate) {
        root[@"activeSession"] = @{
            @"start": @(self.activeSessionStartDate.timeIntervalSince1970),
            @"lastHeartbeat": @(self.activeSessionHeartbeatDate.timeIntervalSince1970)
        };
    }

    NSError *serializationError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:&serializationError];
    if (!data) {
        NSLog(@"Could not serialize study history: %@", serializationError);
        return;
    }

    NSError *writeError = nil;
    [data writeToURL:self.storageURL options:NSDataWritingAtomic error:&writeError];
    if (writeError) {
        NSLog(@"Could not save study history: %@", writeError);
    }
}

@end
