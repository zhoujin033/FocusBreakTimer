#import <Cocoa/Cocoa.h>
#import <math.h>
#import "CountdownLayout.h"
#import "DisplayPowerController.h"
#import "BreakTimerPolicy.h"
#import "EmergencySkipQuotaStore.h"
#import "MeetingScheduleStore.h"
#import "RestObligationStore.h"
#import "StudyHistoryStore.h"
#import "StudyStatisticsWindowController.h"

typedef NS_ENUM(NSInteger, CountdownScreenMode) {
    CountdownScreenModeResting,
    CountdownScreenModeDecision
};

typedef NS_ENUM(NSInteger, CountdownButtonStyle) {
    CountdownButtonStylePrimary,
    CountdownButtonStyleSecondary,
    CountdownButtonStyleQuiet
};

static BOOL userRequestedQuit = NO;
static NSString * const WorkDurationMinutesDefaultsKey = @"workDurationMinutes";
static NSString * const RestDurationMinutesDefaultsKey = @"restDurationMinutes";
static NSString * const LegacyBundleIdentifier = @"local.codex.FocusBreakTimer";
static NSString * const LegacyPreferencesMigrationKey = @"didMigratePreferencesFromLocalCodexV1";
static NSString * const PrimaryStatusItemAutosaveName = @"io.github.zhoujin033.FocusBreakTimer.primaryStatusItem";
static void *StatusItemVisibilityObservationContext = &StatusItemVisibilityObservationContext;
static const NSInteger DefaultWorkDurationMinutes = 20;
static const NSInteger MinimumWorkDurationMinutes = 1;
static const NSInteger MaximumWorkDurationMinutes = 240;
static const NSInteger DefaultRestDurationMinutes = 2;
static const NSInteger MaximumRestDurationMinutes = 60;
static const NSTimeInterval LegacyRestDuration = 5 * 60;
static const NSTimeInterval RestSnoozeDuration = 60;
static const NSTimeInterval RestSkipLockDuration = 30;
static const NSTimeInterval RestSkipHoldDuration = 5;
static const NSTimeInterval DisplaySleepQuietDuration = 1;
static const NSTimeInterval DisplaySleepPreparationTimeout = 10;

typedef NS_ENUM(NSInteger, RestDisplaySleepStage) {
    RestDisplaySleepStageIdle,
    RestDisplaySleepStagePreparing,
    RestDisplaySleepStageAwaitingConfirmation,
    RestDisplaySleepStageAsleep
};

static NSArray<NSString *> *LegacyPreferenceKeys(void) {
    return @[
        WorkDurationMinutesDefaultsKey,
        RestDurationMinutesDefaultsKey,
        @"emergencySkipTimestamps",
        @"meetingScheduleEnabled",
        @"meetingScheduleHandledOccurrence",
        @"meetingSchedulePendingOccurrence",
        @"meetingSchedulePendingResumeDate",
        @"meetingScheduleStoppedBySchedule",
        @"pendingRestObligation",
        @"pendingRestRemainingSeconds",
        @"pendingRestTotalSeconds",
        @"pendingRestSnoozeUsed"
    ];
}

static BOOL ParseDurationMinutes(NSString *text, NSInteger maximum, NSInteger *minutes) {
    NSString *input = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSScanner *scanner = [NSScanner scannerWithString:input];
    NSInteger value = 0;
    if (input.length == 0 || ![scanner scanInteger:&value] || !scanner.isAtEnd || value < 1 || value > maximum) {
        return NO;
    }
    *minutes = value;
    return YES;
}

static void MigrateLegacyPreferences(NSUserDefaults *currentDefaults,
                                     NSUserDefaults *legacyDefaults) {
    if ([currentDefaults boolForKey:LegacyPreferencesMigrationKey]) {
        return;
    }

    for (NSString *key in LegacyPreferenceKeys()) {
        if ([currentDefaults objectForKey:key] != nil) {
            continue;
        }
        id legacyValue = [legacyDefaults objectForKey:key];
        if (legacyValue != nil) {
            [currentDefaults setObject:legacyValue forKey:key];
        }
    }
    [currentDefaults setBool:YES forKey:LegacyPreferencesMigrationKey];
    [currentDefaults synchronize];
}

static void MigrateLegacyPreferencesIfNeeded(void) {
    NSUserDefaults *legacyDefaults = [[NSUserDefaults alloc] initWithSuiteName:LegacyBundleIdentifier];
    MigrateLegacyPreferences(NSUserDefaults.standardUserDefaults, legacyDefaults);
}

static NSString *RuntimeLogPath(void) {
    NSString *bundleFolder = NSBundle.mainBundle.bundlePath.stringByDeletingLastPathComponent;
    return [bundleFolder stringByAppendingPathComponent:@"FocusBreakTimer-runtime.log"];
}

static void AppLog(NSString *message) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:NSDate.date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = RuntimeLogPath();

    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        [data writeToFile:path atomically:YES];
        return;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

static void HandleUncaughtException(NSException *exception) {
    AppLog([NSString stringWithFormat:@"uncaught exception: %@ %@", exception.name, exception.reason]);
}

@class CountdownView;

@protocol CountdownViewDelegate <NSObject>
- (void)countdownViewDidBeginEmergencySkipHold:(CountdownView *)view;
- (void)countdownViewDidCancelEmergencySkipHold:(CountdownView *)view;
- (void)countdownViewDidRequestSnoozeRest:(CountdownView *)view;
- (void)countdownViewDidRequestDisplaySleep:(CountdownView *)view;
- (void)countdownViewDidRequestContinueStudy:(CountdownView *)view;
- (void)countdownViewDidRequestStopStudy:(CountdownView *)view;
@end

@protocol RestDisplaySleepShortcutHandling <NSObject>
- (BOOL)handleDisplaySleepShortcut:(NSEvent *)event;
@end

@interface BreakWindow : NSWindow
@property (nonatomic, copy) NSNumber *displayNumber;
@end

@implementation BreakWindow

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if ([self.contentView conformsToProtocol:@protocol(RestDisplaySleepShortcutHandling)] &&
        [(id<RestDisplaySleepShortcutHandling>)self.contentView handleDisplaySleepShortcut:event]) {
        return YES;
    }
    return [super performKeyEquivalent:event];
}

- (void)keyDown:(NSEvent *)event {
    BOOL commandPressed = (event.modifierFlags & NSEventModifierFlagCommand) == NSEventModifierFlagCommand;
    NSString *key = event.charactersIgnoringModifiers.lowercaseString;

    if (commandPressed && [key isEqualToString:@"q"]) {
        return;
    }

    [super keyDown:event];
}

@end

@interface CountdownView : NSView <RestDisplaySleepShortcutHandling>
@property (nonatomic) NSInteger remainingSeconds;
@property (nonatomic) CGFloat progress;
@property (nonatomic) CountdownScreenMode mode;
@property (nonatomic, strong) NSDate *restEndsAt;
@property (nonatomic) NSInteger skipUnlockRemainingSeconds;
@property (nonatomic) BOOL snoozeAvailable;
@property (nonatomic) BOOL emergencySkipHolding;
@property (nonatomic) NSTimeInterval emergencySkipHoldRemaining;
@property (nonatomic) EmergencySkipLimitReason emergencySkipLimitReason;
@property (nonatomic) BOOL restEndedEarly;
@property (nonatomic) BOOL displaySleepPending;
@property (nonatomic) BOOL displaySleepPreparing;
@property (nonatomic) BOOL displaySleepMousePressed;
@property (nonatomic, copy) NSString *displayPowerMessage;
@property (nonatomic, weak) id<CountdownViewDelegate> delegate;
@property (nonatomic, readonly) NSRect emergencySkipButtonRect;
@property (nonatomic, readonly) NSRect snoozeRestButtonRect;
@property (nonatomic, readonly) NSRect displaySleepButtonRect;
@property (nonatomic, readonly) NSRect continueStudyButtonRect;
@property (nonatomic, readonly) NSRect stopStudyButtonRect;
- (BOOL)isEmergencySkipPressActive;
@end

@implementation CountdownView

static NSRect CountdownNSRect(FBTCountdownRect rect) {
    return NSMakeRect(rect.x, rect.y, rect.width, rect.height);
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _remainingSeconds = DefaultRestDurationMinutes * 60;
        _progress = 1.0;
        _mode = CountdownScreenModeResting;
        _skipUnlockRemainingSeconds = (NSInteger)RestSkipLockDuration;
        _snoozeAvailable = YES;
        _emergencySkipHoldRemaining = RestSkipHoldDuration;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        // AppKit owns the backing layer and its per-window Retina scale.
        self.wantsLayer = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
    }
    return self;
}

- (BOOL)isOpaque {
    return YES;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    self.needsDisplay = YES;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    self.needsDisplay = YES;
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    // Redraw vectors/text when a display's scale or color space changes.
    self.needsDisplay = YES;
}

- (FBTCountdownLayout)countdownLayout {
    return FBTMakeCountdownLayout(NSWidth(self.bounds), NSHeight(self.bounds));
}

- (NSRect)layoutBounds {
    FBTCountdownLayout layout = [self countdownLayout];
    return NSMakeRect(0, 0, layout.canvasWidth, layout.canvasHeight);
}

- (NSRect)viewRectForLayoutRect:(FBTCountdownRect)rect {
    return CountdownNSRect(FBTCountdownRectInView([self countdownLayout], rect,
                                                 NSMinX(self.bounds), NSMinY(self.bounds)));
}

// Compute hit regions from the current geometry, even before the next draw.
- (NSRect)emergencySkipButtonRect {
    return self.mode == CountdownScreenModeResting
        ? [self viewRectForLayoutRect:[self countdownLayout].emergency] : NSZeroRect;
}

- (NSRect)snoozeRestButtonRect {
    return self.mode == CountdownScreenModeResting && self.snoozeAvailable
        ? [self viewRectForLayoutRect:[self countdownLayout].snooze] : NSZeroRect;
}

- (NSRect)displaySleepButtonRect {
    return self.mode == CountdownScreenModeResting
        ? [self viewRectForLayoutRect:[self countdownLayout].displaySleep] : NSZeroRect;
}

- (BOOL)handleDisplaySleepShortcut:(NSEvent *)event {
    NSEventModifierFlags modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    modifiers &= ~NSEventModifierFlagCapsLock;
    if (self.mode != CountdownScreenModeResting ||
        modifiers != (NSEventModifierFlagCommand | NSEventModifierFlagShift) ||
        ![event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"d"]) {
        return NO;
    }
    if (!event.isARepeat && !self.displaySleepPending) {
        [self.delegate countdownViewDidRequestDisplaySleep:self];
    }
    return YES;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    [self removeAllToolTips];
    if (!NSIsEmptyRect(self.displaySleepButtonRect)) {
        [self addToolTipRect:self.displaySleepButtonRect owner:self userData:NULL];
    }
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data {
    return @"熄屏（Command + Shift + D）";
}

- (NSRect)continueStudyButtonRect {
    return self.mode == CountdownScreenModeDecision
        ? [self viewRectForLayoutRect:[self countdownLayout].continueStudy] : NSZeroRect;
}

- (NSRect)stopStudyButtonRect {
    return self.mode == CountdownScreenModeDecision
        ? [self viewRectForLayoutRect:[self countdownLayout].stopStudy] : NSZeroRect;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

- (void)setRemainingSeconds:(NSInteger)remainingSeconds {
    _remainingSeconds = remainingSeconds;
    self.needsDisplay = YES;
}

- (void)setProgress:(CGFloat)progress {
    _progress = progress;
    self.needsDisplay = YES;
}

- (void)setMode:(CountdownScreenMode)mode {
    BOOL changed = _mode != mode;
    if (changed) self.displaySleepMousePressed = NO;
    _mode = mode;
    if (changed) [self updateTrackingAreas];
    self.needsDisplay = YES;
}

- (void)setRestEndsAt:(NSDate *)restEndsAt {
    _restEndsAt = restEndsAt;
    self.needsDisplay = YES;
}

- (void)setSkipUnlockRemainingSeconds:(NSInteger)skipUnlockRemainingSeconds {
    _skipUnlockRemainingSeconds = MAX(0, skipUnlockRemainingSeconds);
    self.needsDisplay = YES;
}

- (void)setSnoozeAvailable:(BOOL)snoozeAvailable {
    _snoozeAvailable = snoozeAvailable;
    self.needsDisplay = YES;
}

- (void)setEmergencySkipHolding:(BOOL)emergencySkipHolding {
    _emergencySkipHolding = emergencySkipHolding;
    self.needsDisplay = YES;
}

- (void)setEmergencySkipHoldRemaining:(NSTimeInterval)emergencySkipHoldRemaining {
    _emergencySkipHoldRemaining = MAX(0, emergencySkipHoldRemaining);
    self.needsDisplay = YES;
}

- (void)setEmergencySkipLimitReason:(EmergencySkipLimitReason)emergencySkipLimitReason {
    _emergencySkipLimitReason = emergencySkipLimitReason;
    self.needsDisplay = YES;
}

- (void)setRestEndedEarly:(BOOL)restEndedEarly {
    _restEndedEarly = restEndedEarly;
    self.needsDisplay = YES;
}

- (void)setDisplaySleepPending:(BOOL)displaySleepPending {
    _displaySleepPending = displaySleepPending;
    if (displaySleepPending) self.displaySleepMousePressed = NO;
    self.needsDisplay = YES;
}

- (void)setDisplaySleepPreparing:(BOOL)displaySleepPreparing {
    _displaySleepPreparing = displaySleepPreparing;
    self.needsDisplay = YES;
}

- (void)setDisplayPowerMessage:(NSString *)displayPowerMessage {
    _displayPowerMessage = [displayPowerMessage copy];
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    [NSGraphicsContext saveGraphicsState];
    [self drawBackground];
    FBTCountdownLayout layout = [self countdownLayout];
    if (layout.scale <= 0) {
        [NSGraphicsContext restoreGraphicsState];
        return;
    }
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:NSMinX(self.bounds) yBy:NSMinY(self.bounds)];
    [transform scaleBy:layout.scale];
    [transform concat];
    [self drawBackdrop];
    [self drawCountdown];
    [self drawActionButtons];
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawBackground {
    [[NSColor colorWithCalibratedWhite:0.065 alpha:1.0] setFill];
    NSRectFill(self.bounds);
}

- (NSRect)progressRingRect {
    return CountdownNSRect([self countdownLayout].ring);
}

- (CGFloat)ringLineWidthForRect:(NSRect)ringRect {
    return MIN(MAX(NSWidth(ringRect) * 0.035, 14.0), 26.0);
}

- (void)drawBackdrop {
    NSRect ringRect = [self progressRingRect];
    CGFloat lineWidth = [self ringLineWidthForRect:ringRect];
    NSRect strokeRect = NSInsetRect(ringRect, lineWidth / 2.0, lineWidth / 2.0);

    NSBezierPath *innerPath = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(strokeRect, lineWidth * 1.6, lineWidth * 1.6)];
    [[NSColor colorWithCalibratedWhite:0.10 alpha:0.20] setFill];
    [innerPath fill];

    NSBezierPath *trackPath = [NSBezierPath bezierPathWithOvalInRect:strokeRect];
    trackPath.lineWidth = lineWidth;
    trackPath.lineCapStyle = NSLineCapStyleRound;
    [[NSColor colorWithCalibratedWhite:0.25 alpha:0.55] setStroke];
    [trackPath stroke];

    CGFloat clampedProgress = self.mode == CountdownScreenModeResting ? MIN(MAX(self.progress, 0.0), 1.0) : 0.0;
    if (clampedProgress <= 0.001) {
        return;
    }

    NSPoint center = NSMakePoint(NSMidX(strokeRect), NSMidY(strokeRect));
    CGFloat radius = NSWidth(strokeRect) / 2.0;
    NSBezierPath *progressPath;
    if (clampedProgress >= 1.0) {
        progressPath = [NSBezierPath bezierPathWithOvalInRect:strokeRect];
    } else {
        progressPath = [NSBezierPath bezierPath];
        [progressPath appendBezierPathWithArcWithCenter:center
                                             radius:radius
                                         startAngle:90.0
                                           endAngle:90.0 - 360.0 * clampedProgress
                                          clockwise:YES];
    }
    progressPath.lineWidth = lineWidth;
    progressPath.lineCapStyle = NSLineCapStyleRound;
    [[NSColor colorWithCalibratedRed:0.53 green:0.76 blue:0.46 alpha:0.96] setStroke];
    [progressPath stroke];
}

- (void)drawCountdown {
    FBTCountdownLayout layout = [self countdownLayout];
    NSRect titleRect = CountdownNSRect(layout.title);
    NSRect ringRect = [self progressRingRect];
    NSInteger safeRemaining = MAX(0, self.remainingSeconds);
    NSInteger minutes = safeRemaining / 60;
    NSInteger seconds = safeRemaining % 60;
    NSString *countdown = [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)seconds];
    NSString *title = self.mode == CountdownScreenModeResting
        ? @"休息一下"
        : (self.restEndedEarly ? @"休息已提前结束" : @"休息结束");

    CGFloat titleSize = layout.titleFontSize;
    NSDictionary<NSAttributedStringKey, id> *titleAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:titleSize weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.93 alpha:0.90]
    };
    NSSize titleMeasured = [title sizeWithAttributes:titleAttributes];
    [title drawAtPoint:NSMakePoint(
        NSMidX(ringRect) - titleMeasured.width / 2.0,
        NSMidY(titleRect) - titleMeasured.height / 2.0
    ) withAttributes:titleAttributes];

    CGFloat timerSize = MIN(MAX(NSWidth(ringRect) * 0.26, 96.0), 188.0);
    NSDictionary<NSAttributedStringKey, id> *timerAttributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:timerSize weight:NSFontWeightHeavy],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    NSSize timerMeasured = [countdown sizeWithAttributes:timerAttributes];
    [countdown drawAtPoint:NSMakePoint(
        NSMidX(ringRect) - timerMeasured.width / 2.0,
        NSMidY(ringRect) - timerMeasured.height / 2.0
    ) withAttributes:timerAttributes];

    NSString *hint = self.mode == CountdownScreenModeDecision && self.restEndedEarly
        ? @"眼睛还没有完成休息"
        : @"去看远处，同时眨眼";
    if (self.displayPowerMessage.length > 0) hint = self.displayPowerMessage;
    CGFloat hintSize = MIN(MAX(NSWidth(ringRect) * 0.045, 20.0), 34.0);
    NSDictionary<NSAttributedStringKey, id> *hintAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:hintSize weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.88 alpha:0.72]
    };
    NSSize hintMeasured = [hint sizeWithAttributes:hintAttributes];
    [hint drawAtPoint:NSMakePoint(
        NSMidX(ringRect) - hintMeasured.width / 2.0,
        NSMidY(ringRect) - timerMeasured.height / 2.0 - hintMeasured.height - MIN(NSHeight(ringRect) * 0.035, 22.0)
    ) withAttributes:hintAttributes];

    NSString *endText = nil;
    if (self.mode == CountdownScreenModeResting && self.restEndsAt) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        formatter.dateFormat = @"H点mm分'结束休息'";
        endText = [formatter stringFromDate:self.restEndsAt];
    } else if (self.mode == CountdownScreenModeDecision) {
        endText = self.restEndedEarly ? @"本轮休息提前结束" : @"本轮休息已完成";
    }
    if (endText) {
        CGFloat endSize = MIN(MAX(NSWidth(ringRect) * 0.040, 18.0), 30.0);
        NSDictionary<NSAttributedStringKey, id> *endAttributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:endSize weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.76 green:0.81 blue:0.70 alpha:0.82]
        };
        NSSize endMeasured = [endText sizeWithAttributes:endAttributes];
        [endText drawAtPoint:NSMakePoint(
            NSMidX(ringRect) - endMeasured.width / 2.0,
            NSMidY(ringRect) - timerMeasured.height / 2.0 - hintMeasured.height - endMeasured.height - MIN(NSHeight(ringRect) * 0.070, 42.0)
        ) withAttributes:endAttributes];
    }
}

- (void)drawActionButtons {
    FBTCountdownLayout layout = [self countdownLayout];
    if (self.mode == CountdownScreenModeResting) {
        [self drawButtonInRect:CountdownNSRect(layout.snooze)
                         title:self.snoozeAvailable ? @"1分钟后休息（本轮仅一次）" : @"本轮已延后过一次"
                    symbolName:@"clock"
                         style:CountdownButtonStylePrimary
                       enabled:self.snoozeAvailable
                       holding:NO];
        [self drawButtonInRect:CountdownNSRect(layout.displaySleep)
                         title:self.displaySleepPreparing ? @"准备熄屏…" : (self.displaySleepPending ? @"正在熄屏" : @"熄屏")
                    symbolName:@"display"
                         style:CountdownButtonStyleSecondary
                       enabled:YES
                       holding:NO];

        NSString *emergencyTitle = nil;
        BOOL quotaAvailable = self.emergencySkipLimitReason == EmergencySkipLimitReasonNone;
        BOOL emergencyEnabled = self.skipUnlockRemainingSeconds <= 0 && quotaAvailable;
        if (!quotaAvailable) {
            emergencyTitle = self.emergencySkipLimitReason == EmergencySkipLimitReasonDaily
                ? @"今日紧急跳过次数已用完"
                : @"本周紧急跳过次数已用完";
        } else if (!emergencyEnabled) {
            emergencyTitle = [NSString stringWithFormat:@"%ld 秒后可使用紧急跳过", (long)self.skipUnlockRemainingSeconds];
        } else if (self.emergencySkipHolding) {
            NSInteger holdSeconds = MAX(1, (NSInteger)ceil(self.emergencySkipHoldRemaining));
            emergencyTitle = [NSString stringWithFormat:@"继续按住 %ld 秒", (long)holdSeconds];
        } else {
            emergencyTitle = @"紧急情况：按住 5 秒跳过";
        }
        [self drawButtonInRect:CountdownNSRect(layout.emergency)
                         title:emergencyTitle
                    symbolName:nil
                         style:CountdownButtonStyleQuiet
                       enabled:emergencyEnabled
                       holding:self.emergencySkipHolding];
        return;
    }

    [self drawButtonInRect:CountdownNSRect(layout.continueStudy)
                     title:@"继续学习"
                symbolName:@"play.fill"
                     style:CountdownButtonStylePrimary
                   enabled:YES
                   holding:NO];
    [self drawButtonInRect:CountdownNSRect(layout.stopStudy)
                     title:@"停止学习"
                symbolName:@"stop.fill"
                     style:CountdownButtonStyleSecondary
                   enabled:YES
                   holding:NO];
}

- (void)drawButtonInRect:(NSRect)rect
                   title:(NSString *)title
              symbolName:(NSString *)symbolName
                   style:(CountdownButtonStyle)style
                 enabled:(BOOL)enabled
                 holding:(BOOL)holding {
    BOOL quiet = style == CountdownButtonStyleQuiet;
    NSColor *fillColor = style == CountdownButtonStylePrimary
        ? [NSColor colorWithCalibratedRed:0.22 green:0.30 blue:0.18 alpha:0.90]
        : [NSColor colorWithCalibratedWhite:0.14 alpha:0.95];
    NSColor *strokeColor = style == CountdownButtonStylePrimary
        ? [NSColor colorWithCalibratedRed:0.55 green:0.69 blue:0.48 alpha:0.52]
        : [NSColor colorWithCalibratedWhite:0.67 alpha:0.32];
    if (quiet) {
        fillColor = [NSColor colorWithCalibratedWhite:0.12 alpha:0.76];
        strokeColor = [NSColor colorWithCalibratedWhite:0.74 alpha:0.30];
    }
    if (holding) {
        fillColor = [NSColor colorWithCalibratedRed:0.24 green:0.19 blue:0.16 alpha:0.92];
        strokeColor = [NSColor colorWithCalibratedRed:0.82 green:0.58 blue:0.38 alpha:0.82];
    }
    if (!enabled) {
        fillColor = [fillColor colorWithAlphaComponent:quiet ? 0.44 : 0.26];
        strokeColor = [strokeColor colorWithAlphaComponent:0.14];
    }
    if (!quiet) {
        NSBezierPath *shadowPath = [NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(rect, 0, -2) xRadius:8 yRadius:8];
        [[NSColor colorWithCalibratedWhite:0 alpha:0.18] setFill];
        [shadowPath fill];
    }
    NSBezierPath *buttonPath = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:8 yRadius:8];
    [fillColor setFill];
    [buttonPath fill];
    buttonPath.lineWidth = quiet && !holding ? 1.0 : 1.5;
    [strokeColor setStroke];
    [buttonPath stroke];

    NSImage *symbol = symbolName ? [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:title] : nil;
    NSRect textRect = NSInsetRect(rect, symbol ? 17.0 : 0, 0);
    // Size the main row against its longest label so a state change cannot
    // change the type size when the shorter decision labels replace it.
    NSString *sizingTitle = quiet ? title : @"1分钟后休息（本轮仅一次）";
    NSFont *font = [self unifiedButtonFontForTitle:sizingTitle inRect:textRect];
    NSColor *textColor = [NSColor colorWithCalibratedWhite:quiet ? 0.92 : 1.0
                                                  alpha:enabled ? (quiet ? 0.78 : 1.0) : 0.42];
    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: textColor
    };
    NSSize textSize = [title sizeWithAttributes:attributes];
    CGFloat iconSize = symbol ? 24.0 : 0;
    CGFloat iconGap = symbol ? 10.0 : 0;
    CGFloat contentX = NSMidX(rect) - (textSize.width + iconSize + iconGap) / 2.0;
    if (symbol) {
        NSImage *tinted = [[NSImage alloc] initWithSize:NSMakeSize(iconSize, iconSize)];
        [tinted lockFocus];
        [symbol drawInRect:NSMakeRect(0, 0, iconSize, iconSize)];
        [textColor setFill];
        NSRectFillUsingOperation(NSMakeRect(0, 0, iconSize, iconSize), NSCompositingOperationSourceIn);
        [tinted unlockFocus];
        [tinted drawInRect:NSMakeRect(contentX, NSMidY(rect) - iconSize / 2.0, iconSize, iconSize)];
    }
    [title drawAtPoint:NSMakePoint(
        contentX + iconSize + iconGap,
        NSMidY(rect) - textSize.height / 2.0
    ) withAttributes:attributes];
}

- (NSFont *)unifiedButtonFontForTitle:(NSString *)title inRect:(NSRect)rect {
    CGFloat fontSize = MIN(MAX(NSHeight(rect) * 0.34, 20.0), 30.0);
    while (fontSize > 17.0) {
        NSFont *font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightSemibold];
        if ([title sizeWithAttributes:@{NSFontAttributeName: font}].width <= NSWidth(rect) - 28.0) {
            break;
        }
        fontSize -= 1.0;
    }
    return [NSFont systemFontOfSize:fontSize weight:NSFontWeightSemibold];
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];

    if (self.mode == CountdownScreenModeResting && NSPointInRect(point, self.displaySleepButtonRect)) {
        self.displaySleepMousePressed = !self.displaySleepPending;
        return;
    }

    if (self.mode == CountdownScreenModeResting &&
        self.skipUnlockRemainingSeconds <= 0 &&
        self.emergencySkipLimitReason == EmergencySkipLimitReasonNone &&
        NSPointInRect(point, self.emergencySkipButtonRect)) {
        [self.delegate countdownViewDidBeginEmergencySkipHold:self];
        return;
    }

    if (self.mode == CountdownScreenModeResting && NSPointInRect(point, self.snoozeRestButtonRect)) {
        [self.delegate countdownViewDidRequestSnoozeRest:self];
        return;
    }

    if (self.mode == CountdownScreenModeDecision && NSPointInRect(point, self.continueStudyButtonRect)) {
        [self.delegate countdownViewDidRequestContinueStudy:self];
        return;
    }

    if (self.mode == CountdownScreenModeDecision && NSPointInRect(point, self.stopStudyButtonRect)) {
        [self.delegate countdownViewDidRequestStopStudy:self];
        return;
    }

    [super mouseDown:event];
}

- (void)mouseDragged:(NSEvent *)event {
    if (self.displaySleepMousePressed) {
        NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        if (!NSPointInRect(point, self.displaySleepButtonRect)) self.displaySleepMousePressed = NO;
        return;
    }
    if (self.mode == CountdownScreenModeResting && self.emergencySkipHolding) {
        NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        if (!NSPointInRect(point, self.emergencySkipButtonRect)) {
            [self.delegate countdownViewDidCancelEmergencySkipHold:self];
            return;
        }
    }
    [super mouseDragged:event];
}

- (void)mouseUp:(NSEvent *)event {
    if (self.displaySleepMousePressed) {
        self.displaySleepMousePressed = NO;
        NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        if (self.mode == CountdownScreenModeResting && !self.displaySleepPending &&
            NSPointInRect(point, self.displaySleepButtonRect)) {
            [self.delegate countdownViewDidRequestDisplaySleep:self];
        }
        return;
    }
    if (self.emergencySkipHolding) {
        [self.delegate countdownViewDidCancelEmergencySkipHold:self];
        return;
    }
    [super mouseUp:event];
}

- (BOOL)isEmergencySkipPressActive {
    if (self.mode != CountdownScreenModeResting || !self.window ||
        self.skipUnlockRemainingSeconds > 0 ||
        self.emergencySkipLimitReason != EmergencySkipLimitReasonNone ||
        NSIsEmptyRect(self.emergencySkipButtonRect)) {
        return NO;
    }
    if ((NSEvent.pressedMouseButtons & 1) == 0) {
        return NO;
    }

    NSPoint windowPoint = [self.window convertPointFromScreen:NSEvent.mouseLocation];
    NSPoint localPoint = [self convertPoint:windowPoint fromView:nil];
    return NSPointInRect(localPoint, self.emergencySkipButtonRect);
}

@end

@interface BreakTimerController : NSObject <CountdownViewDelegate>
@property (nonatomic) NSTimeInterval workDuration;
@property (nonatomic) NSTimeInterval restDuration;
@property (nonatomic) TimerPhase phase;
@property (nonatomic, strong) NSDate *phaseEndsAt;
@property (nonatomic) NSTimeInterval phaseEndsAtContinuousTime;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSMutableArray<BreakWindow *> *breakWindows;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic) BOOL observingStatusItemVisibility;
@property (nonatomic, strong) NSMenuItem *breakItem;
@property (nonatomic, strong) NSMenuItem *restartItem;
@property (nonatomic, strong) NSMenuItem *stopItem;
@property (nonatomic, strong) NSMenuItem *quitItem;
@property (nonatomic, strong) NSWindow *settingsWindow;
@property (nonatomic, strong) NSTextField *settingsMinutesField;
@property (nonatomic, strong) NSTextField *settingsRestMinutesField;
@property (nonatomic, strong) NSTextField *settingsSkipUsageLabel;
@property (nonatomic, strong) NSButton *settingsMeetingScheduleCheckbox;
@property (nonatomic, strong) NSWindow *keepAliveWindow;
@property (nonatomic, strong) NSUserDefaults *userDefaults;
@property (nonatomic, strong) StudyHistoryStore *historyStore;
@property (nonatomic, strong) RestObligationStore *restObligationStore;
@property (nonatomic, strong) EmergencySkipQuotaStore *emergencySkipQuotaStore;
@property (nonatomic, strong) MeetingScheduleStore *meetingScheduleStore;
@property (nonatomic, copy) NSCalendar *meetingScheduleCalendar;
@property (nonatomic, strong) NSTimer *meetingScheduleTimer;
@property (nonatomic, strong) StudyStatisticsWindowController *statisticsWindowController;
@property (nonatomic) NSTimeInterval restSkipAvailableAtContinuousTime;
@property (nonatomic) BOOL hasSnoozedCurrentCycle;
@property (nonatomic) BOOL restEndedEarly;
@property (nonatomic) BOOL restObligationActive;
@property (nonatomic) NSTimeInterval restoredRestRemaining;
@property (nonatomic, strong) NSDate *emergencySkipHoldStartedAt;
@property (nonatomic) NSTimeInterval emergencySkipHoldStartedAtContinuousTime;
@property (nonatomic, weak) CountdownView *emergencySkipHoldView;
@property (nonatomic, strong) NSTimer *emergencySkipHoldTimer;
@property (nonatomic) BOOL isAsleep;
@property (nonatomic) BOOL systemSleeping;
@property (nonatomic) BOOL workspaceScreensAsleep;
@property (nonatomic) NSTimeInterval eligibleInactivityStartedAtContinuousTime;
@property (nonatomic) NSTimeInterval restRemainingAtInactivityStart;
@property (nonatomic) NSTimeInterval skipLockRemainingAtInactivityStart;
@property (nonatomic, strong) id<DisplayPowerControlling> displayPowerController;
@property (nonatomic, strong) id<DisplaySleepInputStateProviding> displaySleepInputStateProvider;
@property (nonatomic, strong) NSUUID *restDisplaySleepToken;
@property (nonatomic, strong) NSTimer *restDisplaySleepTimer;
@property (nonatomic) RestDisplaySleepStage restDisplaySleepStage;
@property (nonatomic, readonly) BOOL restDisplaySleepConfirmed;
@property (nonatomic) NSTimeInterval restDisplaySleepPreparationDeadline;
@property (nonatomic) NSTimeInterval restDisplaySleepQuietStartedAt;
@property (nonatomic) NSTimeInterval restDisplaySleepRequestedAt;
@property (nonatomic) NSTimeInterval restDisplaySleepConfirmationDeadline;
@property (nonatomic) BOOL waitingForRestCompletionDisplayWake;
@property (nonatomic, copy) NSString *restDisplayPowerMessage;
- (void)cancelEmergencySkipHold;
- (void)cancelRestDisplaySleep;
- (void)restDisplaySleepTick;
- (void)completeRestCycleWithEarlyEnd:(BOOL)endedEarly;
- (void)startRestCycleWithDuration:(NSTimeInterval)duration
                activateObligation:(BOOL)activateObligation
                  skipLockDuration:(NSTimeInterval)skipLockDuration;
- (BOOL)reconcileMeetingScheduleAtDate:(NSDate *)date;
- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults
                         historyStore:(StudyHistoryStore *)historyStore;
@end

@implementation BreakTimerController

- (instancetype)init {
    return [self initWithUserDefaults:NSUserDefaults.standardUserDefaults
                         historyStore:[[StudyHistoryStore alloc] initWithStorageURL:StudyHistoryStore.defaultStorageURL]];
}

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults
                         historyStore:(StudyHistoryStore *)historyStore {
    self = [super init];
    if (self) {
        _userDefaults = userDefaults;
        [_userDefaults registerDefaults:@{
            WorkDurationMinutesDefaultsKey: @(DefaultWorkDurationMinutes),
            RestDurationMinutesDefaultsKey: @(DefaultRestDurationMinutes)
        }];
        _workDuration = [self validatedWorkDurationMinutes] * 60;
        _restDuration = [self validatedRestDurationMinutes] * 60;
        _phase = TimerPhaseWorking;
        _phaseEndsAt = NSDate.date;
        _phaseEndsAtContinuousTime = BreakTimerContinuousTime();
        _breakWindows = [NSMutableArray array];
        _restObligationStore = [[RestObligationStore alloc] initWithUserDefaults:_userDefaults];
        _emergencySkipQuotaStore = [[EmergencySkipQuotaStore alloc] initWithUserDefaults:_userDefaults];
        _meetingScheduleStore = [[MeetingScheduleStore alloc] initWithUserDefaults:_userDefaults];
        _meetingScheduleCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        _meetingScheduleCalendar.timeZone = NSTimeZone.localTimeZone;
        RestObligationSnapshot *restSnapshot = [_restObligationStore snapshotWithDefaultDuration:LegacyRestDuration];
        _restObligationActive = restSnapshot.pending;
        if (restSnapshot.pending) _restDuration = restSnapshot.totalDuration;
        _restoredRestRemaining = restSnapshot.remainingDuration;
        _hasSnoozedCurrentCycle = restSnapshot.snoozeUsed;
        _historyStore = historyStore;
        _displayPowerController = [[DisplayPowerController alloc] init];
        _displaySleepInputStateProvider = [[DisplaySleepInputStateProvider alloc] init];
        [_historyStore recoverInterruptedSessionAtDate:NSDate.date];
    }
    return self;
}

- (void)start {
    [self configureKeepAliveWindow];
    [self configureStatusItem];
    [self registerSystemNotifications];
    NSDate *now = NSDate.date;
    if ([self reconcileMeetingScheduleAtDate:now]) {
        [self scheduleNextMeetingBoundaryAfterDate:now];
        return;
    }
    if (self.restObligationActive) {
        AppLog([NSString stringWithFormat:@"restore pending rest obligation, remaining=%.1f", self.restoredRestRemaining]);
        [self startRestCycleWithDuration:self.restoredRestRemaining
                      activateObligation:NO
                        skipLockDuration:RestSkipLockDuration];
    } else {
        [self startWorkCycle];
    }
    [self scheduleNextMeetingBoundaryAfterDate:now];
}

- (void)configureKeepAliveWindow {
    self.keepAliveWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(-10000, -10000, 1, 1)
                                                       styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
    self.keepAliveWindow.releasedWhenClosed = NO;
    self.keepAliveWindow.hidesOnDeactivate = NO;
    [self.keepAliveWindow orderOut:nil];
}

- (void)configureStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    [self configureStatusItemVisibilityPolicy];
    self.statusItem.button.title = [NSString stringWithFormat:@"学习 %02ld:00", (long)[self workDurationMinutes]];
    self.statusItem.button.toolTip = @"学习休息倒计时";

    NSMenu *menu = [[NSMenu alloc] init];
    menu.autoenablesItems = NO;
    self.breakItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"立刻休息 %ld 分钟", (long)[self validatedRestDurationMinutes]] action:@selector(startBreakNow:) keyEquivalent:@"b"];
    self.restartItem = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(restartWorkFromMenu:) keyEquivalent:@"r"];
    NSMenuItem *statisticsItem = [[NSMenuItem alloc] initWithTitle:@"学习统计..." action:@selector(openStatistics:) keyEquivalent:@"d"];
    NSMenuItem *settingsItem = [[NSMenuItem alloc] initWithTitle:@"设置..." action:@selector(openSettings:) keyEquivalent:@","];
    self.stopItem = [[NSMenuItem alloc] initWithTitle:@"停止学习" action:@selector(stopStudyFromMenu:) keyEquivalent:@"s"];
    self.quitItem = [[NSMenuItem alloc] initWithTitle:@"退出应用" action:@selector(quitFromMenu:) keyEquivalent:@"q"];
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSMenuItem *versionItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"版本 %@", version] action:nil keyEquivalent:@""];
    versionItem.enabled = NO;

    self.breakItem.target = self;
    self.restartItem.target = self;
    statisticsItem.target = self;
    settingsItem.target = self;
    self.stopItem.target = self;
    self.quitItem.target = self;

    [self updateConfigurableMenuItems];
    [menu addItem:self.breakItem];
    [menu addItem:self.restartItem];
    [menu addItem:statisticsItem];
    [menu addItem:settingsItem];
    [menu addItem:self.stopItem];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:versionItem];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:self.quitItem];

    self.statusItem.menu = menu;
}

- (void)configureStatusItemVisibilityPolicy {
    self.statusItem.autosaveName = PrimaryStatusItemAutosaveName;
    self.statusItem.behavior = 0;
    self.statusItem.visible = YES;
    [self.statusItem addObserver:self
                      forKeyPath:@"visible"
                         options:NSKeyValueObservingOptionNew
                         context:StatusItemVisibilityObservationContext];
    self.observingStatusItemVisibility = YES;
}

- (void)ensureStatusItemVisible {
    if (self.statusItem && !self.statusItem.isVisible) {
        AppLog(@"restore menu bar status item visibility");
        self.statusItem.visible = YES;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    if (context == StatusItemVisibilityObservationContext && object == self.statusItem) {
        if (!self.statusItem.isVisible) {
            [self ensureStatusItemVisible];
        }
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)dealloc {
    [_restDisplaySleepTimer invalidate];
    [_displayPowerController cancelDisplaySleepRequest];
    [_displayPowerController endRestActivity];
    if (self.observingStatusItemVisibility) {
        [self.statusItem removeObserver:self forKeyPath:@"visible" context:StatusItemVisibilityObservationContext];
    }
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
}

- (void)registerSystemNotifications {
    NSNotificationCenter *workspaceCenter = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspaceCenter addObserver:self selector:@selector(systemWillSleep:) name:NSWorkspaceWillSleepNotification object:nil];
    [workspaceCenter addObserver:self selector:@selector(systemDidWake:) name:NSWorkspaceDidWakeNotification object:nil];
    [workspaceCenter addObserver:self selector:@selector(screensDidSleep:) name:NSWorkspaceScreensDidSleepNotification object:nil];
    [workspaceCenter addObserver:self selector:@selector(screensDidWake:) name:NSWorkspaceScreensDidWakeNotification object:nil];
    [workspaceCenter addObserver:self selector:@selector(activeSpaceDidChange:) name:NSWorkspaceActiveSpaceDidChangeNotification object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screenConfigurationChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidResignActive:) name:NSApplicationDidResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(systemClockOrTimeZoneChanged:) name:NSSystemClockDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(systemClockOrTimeZoneChanged:) name:NSSystemTimeZoneDidChangeNotification object:nil];
}

- (NSInteger)validatedWorkDurationMinutes {
    NSInteger minutes = [self.userDefaults integerForKey:WorkDurationMinutesDefaultsKey];
    if (minutes < MinimumWorkDurationMinutes || minutes > MaximumWorkDurationMinutes) {
        minutes = DefaultWorkDurationMinutes;
        [self.userDefaults setInteger:minutes forKey:WorkDurationMinutesDefaultsKey];
    }
    return minutes;
}

- (NSInteger)workDurationMinutes {
    return MAX(MinimumWorkDurationMinutes, (NSInteger)llround(self.workDuration / 60.0));
}

- (NSInteger)validatedRestDurationMinutes {
    NSInteger minutes = [self.userDefaults integerForKey:RestDurationMinutesDefaultsKey];
    if (minutes < 1 || minutes > MaximumRestDurationMinutes) {
        minutes = DefaultRestDurationMinutes;
        [self.userDefaults setInteger:minutes forKey:RestDurationMinutesDefaultsKey];
    }
    return minutes;
}

- (void)reloadWorkDurationFromDefaults {
    self.workDuration = [self validatedWorkDurationMinutes] * 60;
}

- (void)updateConfigurableMenuItems {
    if (!self.breakItem || !self.restartItem || !self.stopItem || !self.quitItem) {
        return;
    }

    BreakTimerActionPolicy policy = BreakTimerActionPolicyMake(self.phase, self.restObligationActive);
    NSInteger workMinutes = [self validatedWorkDurationMinutes];
    if (policy.restAction == BreakTimerRestActionStartSnoozedRestNow) {
        self.breakItem.title = @"立即开始休息";
        self.breakItem.enabled = YES;
    } else if (policy.restAction == BreakTimerRestActionUnavailable) {
        self.breakItem.title = @"正在休息";
        self.breakItem.enabled = NO;
    } else {
        self.breakItem.title = [NSString stringWithFormat:@"立刻休息 %ld 分钟", (long)[self validatedRestDurationMinutes]];
        self.breakItem.enabled = YES;
    }

    if (!policy.canStartWork) {
        self.restartItem.title = @"休息完成后可开始学习";
    } else if (self.phase == TimerPhaseRestComplete) {
        self.restartItem.title = [NSString stringWithFormat:@"继续学习 %ld 分钟", (long)workMinutes];
    } else {
        self.restartItem.title = [NSString stringWithFormat:@"开始/重新开始 %ld 分钟", (long)workMinutes];
    }
    self.restartItem.enabled = policy.canStartWork;
    self.stopItem.enabled = policy.canStopStudy;
    self.quitItem.enabled = policy.canQuitApplication;
}

- (NSTimeInterval)currentPhaseRemaining {
    return MAX(0, self.phaseEndsAtContinuousTime - BreakTimerContinuousTime());
}

- (void)refreshPhaseEndDate {
    self.phaseEndsAt = [NSDate dateWithTimeIntervalSinceNow:[self currentPhaseRemaining]];
}

- (NSTimeInterval)currentRequiredRestRemaining {
    if (!self.restObligationActive) {
        return 0;
    }
    if (self.isAsleep) {
        NSTimeInterval inactiveDuration = MAX(0, BreakTimerContinuousTime() - self.eligibleInactivityStartedAtContinuousTime);
        return BreakTimerRemainingRestAfterInactivity(self.restRemainingAtInactivityStart, inactiveDuration);
    }
    if (self.phase == TimerPhaseResting) {
        return [self currentPhaseRemaining];
    }
    return self.restDuration;
}

- (void)persistRestObligationSynchronously:(BOOL)synchronously {
    if (!self.restObligationActive) {
        return;
    }
    NSTimeInterval remaining = [self currentRequiredRestRemaining];
    if (!isfinite(remaining) || remaining <= 0 || remaining > self.restDuration) {
        remaining = self.restDuration;
    }
    [self.restObligationStore saveRemainingDuration:remaining
                                     totalDuration:self.restDuration
                                        snoozeUsed:self.hasSnoozedCurrentCycle
                                     synchronously:synchronously];
}

- (void)clearPersistedRestObligation {
    [self.restObligationStore clear];
}

- (void)resetDisplayInactivity {
    self.isAsleep = NO;
    self.eligibleInactivityStartedAtContinuousTime = 0;
    self.restRemainingAtInactivityStart = 0;
    self.skipLockRemainingAtInactivityStart = 0;
}

- (void)cancelRestDisplaySleep {
    if (!self.restDisplaySleepToken) return;
    AppLog([NSString stringWithFormat:@"cancel rest display sleep, stage=%ld", (long)self.restDisplaySleepStage]);
    self.restDisplaySleepToken = nil;
    [self.restDisplaySleepTimer invalidate];
    self.restDisplaySleepTimer = nil;
    self.restDisplaySleepStage = RestDisplaySleepStageIdle;
    self.restDisplaySleepPreparationDeadline = 0;
    self.restDisplaySleepQuietStartedAt = 0;
    self.restDisplaySleepRequestedAt = 0;
    self.restDisplaySleepConfirmationDeadline = 0;
    [self.displayPowerController cancelDisplaySleepRequest];
    [self.displayPowerController endRestActivity];
    for (BreakWindow *window in self.breakWindows) {
        CountdownView *view = (CountdownView *)window.contentView;
        if ([view isKindOfClass:CountdownView.class]) {
            view.displaySleepPending = NO;
            view.displaySleepPreparing = NO;
        }
    }
}

- (void)failRestDisplaySleepWithError:(NSError *)error {
    AppLog([NSString stringWithFormat:@"rest display sleep failed: %@", error.localizedDescription]);
    [self cancelRestDisplaySleep];
    self.restDisplayPowerMessage = @"熄屏失败，请重试";
    if (self.isAsleep) {
        [self resumeAfterEligibleInactivityIfPossible];
    } else {
        [self transitionExpiredPhaseIfNeeded];
        if (self.phase == TimerPhaseResting) {
            [self showBreakWindowsWithMode:CountdownScreenModeResting];
        }
    }
}

- (void)requestRestDisplaySleep {
    [self transitionExpiredPhaseIfNeeded];
    if (self.phase != TimerPhaseResting || !self.restObligationActive ||
        self.isAsleep || self.systemSleeping || self.restDisplaySleepToken ||
        ![self anyOnlineDisplayIsAwake]) return;

    [self cancelEmergencySkipHold];
    AppLog(@"rest preparing display sleep, waiting for released input and one quiet second");
    NSUUID *token = NSUUID.UUID;
    self.restDisplaySleepToken = token;
    self.restDisplaySleepStage = RestDisplaySleepStagePreparing;
    NSTimeInterval now = BreakTimerContinuousTime();
    self.restDisplaySleepPreparationDeadline = now + DisplaySleepPreparationTimeout;
    self.restDisplaySleepQuietStartedAt = now;
    self.restDisplayPowerMessage = nil;
    [self updateRestWindowsWithRemainingSeconds:[self currentRestRemainingSeconds]];
    __weak typeof(self) weakSelf = self;
    self.restDisplaySleepTimer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
        BreakTimerController *controller = weakSelf;
        if (controller.restDisplaySleepToken == token) [controller restDisplaySleepTick];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.restDisplaySleepTimer forMode:NSRunLoopCommonModes];
}

- (BOOL)restDisplaySleepConfirmed {
    return self.restDisplaySleepStage == RestDisplaySleepStageAsleep;
}

- (void)issuePreparedRestDisplaySleep {
    NSError *error = nil;
    if (![self.displayPowerController beginRestActivityForDuration:[self currentPhaseRemaining] error:&error]) {
        [self failRestDisplaySleepWithError:error];
        return;
    }
    NSUUID *token = self.restDisplaySleepToken;
    self.restDisplaySleepStage = RestDisplaySleepStageAwaitingConfirmation;
    self.restDisplaySleepRequestedAt = BreakTimerContinuousTime();
    self.restDisplaySleepConfirmationDeadline = self.restDisplaySleepRequestedAt + 5;
    AppLog(@"rest requested display sleep after input settled");
    [self updateRestWindowsWithRemainingSeconds:[self currentRestRemainingSeconds]];
    __weak typeof(self) weakSelf = self;
    [self.displayPowerController requestDisplaySleepWithCompletion:^(NSError *sleepError) {
        BreakTimerController *controller = weakSelf;
        if (!controller || controller.restDisplaySleepToken != token) return;
        if (sleepError && !controller.restDisplaySleepConfirmed) {
            [controller failRestDisplaySleepWithError:sleepError];
        } else {
            [controller restDisplaySleepTick];
        }
    }];
}

- (void)finishRestDisplaySleep {
    // Complete the obligation before requesting a wake. A delayed/failed wake
    // must still lead to the decision screen, never a new learning session.
    self.waitingForRestCompletionDisplayWake = YES;
    [self resetDisplayInactivity];
    [self completeRestCycleWithEarlyEnd:NO];
    AppLog(@"rest completed while displays asleep, requesting automatic display wake");
    NSError *error = nil;
    if (![self.displayPowerController wakeDisplaysWithError:&error]) {
        AppLog([NSString stringWithFormat:@"rest display wake failed: %@", error.localizedDescription]);
        self.restDisplayPowerMessage = @"自动亮屏失败，请手动亮屏";
        [self updateDecisionWindows];
    }
    [self cancelRestDisplaySleep];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delay in @[@0.2, @1.0, @3.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [weakSelf resumeAfterEligibleInactivityIfPossible];
        });
    }
}

- (void)restDisplaySleepTick {
    if (!self.restDisplaySleepToken) return;
    if (self.systemSleeping || self.phase != TimerPhaseResting || !self.restObligationActive) {
        [self cancelRestDisplaySleep];
        return;
    }
    if ([self reconcileMeetingScheduleAtDate:NSDate.date]) return;
    if (self.restDisplaySleepStage == RestDisplaySleepStagePreparing) {
        if ([self allOnlineDisplaysAreAsleep]) {
            [self cancelRestDisplaySleep];
            [self beginEligibleInactivityAtDate:NSDate.date reason:@"display sleep before prepared request"];
            return;
        }
        if ([self currentPhaseRemaining] <= 0) {
            [self completeRestCycle];
            return;
        }
        NSTimeInterval now = BreakTimerContinuousTime();
        if (now >= self.restDisplaySleepPreparationDeadline) {
            AppLog(@"rest display sleep preparation timed out waiting for idle input");
            [self cancelRestDisplaySleep];
            self.restDisplayPowerMessage = @"熄屏已取消，请松开按键后重试";
            [self updateRestWindowsWithRemainingSeconds:[self currentRestRemainingSeconds]];
            return;
        }
        DisplaySleepInputSnapshot input = [self.displaySleepInputStateProvider inputSnapshot];
        if (input.anyInputHeld || !isfinite(input.idleDuration) || input.idleDuration < 0) {
            self.restDisplaySleepQuietStartedAt = now;
            return;
        }
        self.restDisplaySleepQuietStartedAt = MAX(self.restDisplaySleepQuietStartedAt, now - input.idleDuration);
        if (now - self.restDisplaySleepQuietStartedAt >= DisplaySleepQuietDuration) {
            [self issuePreparedRestDisplaySleep];
        }
        return;
    }
    if ([self allOnlineDisplaysAreAsleep]) {
        [self beginEligibleInactivityAtDate:NSDate.date reason:@"rest button display sleep"];
        if ([self currentPhaseRemaining] <= 0) [self finishRestDisplaySleep];
    } else if (self.restDisplaySleepConfirmed && [self anyOnlineDisplayIsAwake]) {
        [self resumeAfterEligibleInactivityIfPossible];
    } else if ([self currentPhaseRemaining] <= 0) {
        [self cancelRestDisplaySleep];
        [self completeRestCycle];
    } else if (BreakTimerContinuousTime() >= self.restDisplaySleepConfirmationDeadline) {
        NSError *error = [NSError errorWithDomain:@"FocusBreakTimer.DisplayPower" code:2
                                        userInfo:@{NSLocalizedDescriptionKey: @"未能确认所有显示器已熄灭。"}];
        [self failRestDisplaySleepWithError:error];
    }
}

- (void)startWorkCycle {
    if (self.restObligationActive) {
        AppLog(@"blocked work start while rest obligation is active");
        [self updateStatusItem];
        return;
    }

    AppLog(@"start work cycle");
    NSDate *now = NSDate.date;
    [self cancelRestDisplaySleep];
    self.waitingForRestCompletionDisplayWake = NO;
    self.restDisplayPowerMessage = nil;
    [self cancelEmergencySkipHold];
    [self reloadWorkDurationFromDefaults];
    self.isAsleep = NO;
    self.hasSnoozedCurrentCycle = NO;
    self.restEndedEarly = NO;
    self.phase = TimerPhaseWorking;
    self.phaseEndsAt = [now dateByAddingTimeInterval:self.workDuration];
    self.phaseEndsAtContinuousTime = BreakTimerContinuousTime() + self.workDuration;
    [self.historyStore beginSessionAtDate:now];
    [self dismissBreakWindows];
    [self scheduleTick];
    [self updateStatusItem];
}

- (void)startWorkCycleFromUserAction {
    [self.meetingScheduleStore markManualStudyStart];
    [self startWorkCycle];
}

- (void)startRestCycle {
    if (self.isAsleep) return;
    self.restDuration = [self validatedRestDurationMinutes] * 60;
    [self startRestCycleWithDuration:self.restDuration activateObligation:YES skipLockDuration:RestSkipLockDuration];
}

- (void)startRestCycleWithDuration:(NSTimeInterval)duration
                activateObligation:(BOOL)activateObligation
                  skipLockDuration:(NSTimeInterval)skipLockDuration {
    if (self.isAsleep) {
        return;
    }

    [self cancelRestDisplaySleep];
    self.waitingForRestCompletionDisplayWake = NO;
    self.restDisplayPowerMessage = nil;
    AppLog([NSString stringWithFormat:@"start rest cycle, duration=%.1f", duration]);
    NSDate *now = NSDate.date;
    [self.historyStore endActiveSessionAtDate:now];
    [self cancelEmergencySkipHold];
    if (activateObligation) {
        self.restObligationActive = YES;
    }
    if (!self.restObligationActive) {
        AppLog(@"ignored rest start without active obligation");
        return;
    }
    self.restEndedEarly = NO;
    self.phase = TimerPhaseResting;
    NSTimeInterval safeDuration = MAX(0, duration);
    NSTimeInterval continuousNow = BreakTimerContinuousTime();
    self.phaseEndsAt = [now dateByAddingTimeInterval:safeDuration];
    self.phaseEndsAtContinuousTime = continuousNow + safeDuration;
    self.restSkipAvailableAtContinuousTime = continuousNow + MAX(0, skipLockDuration);
    [self persistRestObligationSynchronously:YES];
    [self showBreakWindowsWithMode:CountdownScreenModeResting];
    [self scheduleTick];
    [self updateStatusItem];
}

- (void)completeRestCycle {
    [self completeRestCycleWithEarlyEnd:NO];
}

- (void)completeRestCycleWithEarlyEnd:(BOOL)endedEarly {
    if (self.phase != TimerPhaseResting || !self.restObligationActive) {
        AppLog(@"ignored rest completion outside an active rest");
        return;
    }

    AppLog(endedEarly ? @"complete rest cycle early" : @"complete rest cycle");
    [self cancelEmergencySkipHold];
    self.restObligationActive = NO;
    [self clearPersistedRestObligation];
    self.restEndedEarly = endedEarly;
    self.phase = TimerPhaseRestComplete;
    self.phaseEndsAt = NSDate.date;
    self.phaseEndsAtContinuousTime = BreakTimerContinuousTime();
    [self.timer invalidate];
    self.timer = nil;

    if (self.breakWindows.count == 0 && !self.waitingForRestCompletionDisplayWake) {
        [self showBreakWindowsWithMode:CountdownScreenModeDecision];
    }
    [self updateDecisionWindows];
    if (!self.waitingForRestCompletionDisplayWake) {
        [self cancelRestDisplaySleep];
        [self bringBreakWindowsToFront];
    }
    [self updateStatusItem];
}

- (void)snoozeRestCycle {
    if (self.phase != TimerPhaseResting || !self.restObligationActive || self.hasSnoozedCurrentCycle) {
        AppLog(@"ignored unavailable rest snooze request");
        return;
    }

    AppLog(@"snooze rest for one minute");
    [self cancelRestDisplaySleep];
    self.restDisplayPowerMessage = nil;
    [self cancelEmergencySkipHold];
    self.hasSnoozedCurrentCycle = YES;
    self.phase = TimerPhaseSnoozingRest;
    self.phaseEndsAt = [NSDate dateWithTimeIntervalSinceNow:RestSnoozeDuration];
    self.phaseEndsAtContinuousTime = BreakTimerContinuousTime() + RestSnoozeDuration;
    [self persistRestObligationSynchronously:YES];
    [self dismissBreakWindows];
    [self scheduleTick];
    [self updateStatusItem];
}

- (void)stopStudy {
    if (self.restObligationActive) {
        AppLog(@"blocked stop study while rest obligation is active");
        [self updateStatusItem];
        return;
    }

    AppLog(@"stop study, keep app running");
    [self cancelRestDisplaySleep];
    self.waitingForRestCompletionDisplayWake = NO;
    [self.meetingScheduleStore cancelPendingAutoResume];
    [self.historyStore endActiveSessionAtDate:NSDate.date];
    [self cancelEmergencySkipHold];
    self.phase = TimerPhaseStopped;
    [self.timer invalidate];
    self.timer = nil;
    [self dismissBreakWindows];
    [self updateStatusItem];
}

- (void)scheduleTick {
    [self.timer invalidate];
    self.timer = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (BOOL)transitionExpiredPhaseIfNeeded {
    if (self.isAsleep || [self currentPhaseRemaining] > 0) {
        return NO;
    }
    if (self.phase == TimerPhaseWorking) {
        [self startRestCycle];
        return YES;
    }
    if (self.phase == TimerPhaseResting) {
        if (self.restDisplaySleepToken &&
            self.restDisplaySleepStage != RestDisplaySleepStagePreparing && [self allOnlineDisplaysAreAsleep]) {
            [self restDisplaySleepTick];
            return YES;
        }
        [self completeRestCycle];
        return YES;
    }
    if (self.phase == TimerPhaseSnoozingRest) {
        [self startRestCycleWithDuration:self.restDuration
                      activateObligation:NO
                        skipLockDuration:RestSkipLockDuration];
        return YES;
    }
    return NO;
}

- (void)tick:(NSTimer *)timer {
    if (self.isAsleep || self.phase == TimerPhaseStopped || self.phase == TimerPhaseRestComplete) {
        return;
    }

    NSDate *now = NSDate.date;
    if (self.phase == TimerPhaseWorking) {
        [self.historyStore updateHeartbeatAtDate:now];
    }
    if ([self transitionExpiredPhaseIfNeeded]) {
        return;
    }
    NSTimeInterval remaining = [self currentPhaseRemaining];

    [self updateStatusItem];
    if (self.phase == TimerPhaseResting) {
        [self refreshPhaseEndDate];
        [self persistRestObligationSynchronously:NO];
        [self updateRestWindowsWithRemainingSeconds:(NSInteger)ceil(remaining)];
        if (!self.restDisplaySleepToken) [self bringBreakWindowsToFront];
    }
}

- (void)stopForScheduledMeetingAtDate:(NSDate *)date {
    AppLog(@"scheduled meeting stopped study");
    [self cancelRestDisplaySleep];
    self.waitingForRestCompletionDisplayWake = NO;
    [self.historyStore endActiveSessionAtDate:date];
    [self cancelEmergencySkipHold];
    self.restObligationActive = NO;
    [self clearPersistedRestObligation];
    self.restEndedEarly = NO;
    self.phase = TimerPhaseStopped;
    self.phaseEndsAt = date;
    self.phaseEndsAtContinuousTime = BreakTimerContinuousTime();
    [self.timer invalidate];
    self.timer = nil;
    [self dismissBreakWindows];
    [self updateStatusItem];
}

- (BOOL)reconcileMeetingScheduleAtDate:(NSDate *)date {
    if (!self.meetingScheduleStore.isEnabled) {
        if (self.meetingScheduleStore.pendingAutoResumeOccurrenceIdentifier) {
            [self.meetingScheduleStore cancelPendingAutoResume];
        }
        return NO;
    }

    NSDate *pendingResumeDate = self.meetingScheduleStore.pendingAutoResumeDate;
    if (pendingResumeDate) {
        NSDate *updatedMeetingEnd = nil;
        if (!MeetingScheduleIntervalForDate(pendingResumeDate, self.meetingScheduleCalendar, NULL, &updatedMeetingEnd)) {
            [self.meetingScheduleStore cancelPendingAutoResume];
            pendingResumeDate = nil;
        } else if (![pendingResumeDate isEqualToDate:updatedMeetingEnd]) {
            self.meetingScheduleStore.pendingAutoResumeDate = updatedMeetingEnd;
            pendingResumeDate = updatedMeetingEnd;
        }
    }
    if (pendingResumeDate && [date compare:pendingResumeDate] != NSOrderedAscending) {
        if (self.systemSleeping || (self.isAsleep && ![self anyOnlineDisplayIsAwake])) {
            return YES;
        }
        if (self.isAsleep) {
            self.isAsleep = NO;
            self.eligibleInactivityStartedAtContinuousTime = 0;
            self.restRemainingAtInactivityStart = 0;
            self.skipLockRemainingAtInactivityStart = 0;
        }
        BOOL shouldResume = self.meetingScheduleStore.stoppedBySchedule &&
            self.phase == TimerPhaseStopped && !self.restObligationActive;
        [self.meetingScheduleStore completePendingAutoResume];
        if (shouldResume) {
            AppLog(@"scheduled meeting ended; start a full work cycle");
            [self startWorkCycle];
            return YES;
        }
    }

    NSDate *meetingStart = nil;
    NSDate *meetingEnd = nil;
    if (!MeetingScheduleIntervalForDate(date, self.meetingScheduleCalendar, &meetingStart, &meetingEnd) ||
        [date compare:meetingStart] == NSOrderedAscending ||
        [date compare:meetingEnd] != NSOrderedAscending) {
        return NO;
    }

    NSString *identifier = MeetingScheduleOccurrenceIdentifier(date, self.meetingScheduleCalendar);
    if (![self.meetingScheduleStore.handledOccurrenceIdentifier isEqualToString:identifier]) {
        BOOL alreadyStopped = self.phase == TimerPhaseStopped && !self.restObligationActive;
        if (alreadyStopped) {
            AppLog(@"scheduled meeting found study already stopped");
            [self.meetingScheduleStore markOccurrenceHandled:identifier
                                              autoResumeDate:nil
                                           stoppedBySchedule:NO];
        } else {
            [self stopForScheduledMeetingAtDate:date];
            [self.meetingScheduleStore markOccurrenceHandled:identifier
                                              autoResumeDate:meetingEnd
                                           stoppedBySchedule:YES];
        }
        return YES;
    }

    BOOL pendingThisOccurrence = [self.meetingScheduleStore.pendingAutoResumeOccurrenceIdentifier
        isEqualToString:identifier];
    if (pendingThisOccurrence && self.meetingScheduleStore.stoppedBySchedule) {
        if (self.phase != TimerPhaseStopped || self.restObligationActive) {
            [self stopForScheduledMeetingAtDate:date];
        } else {
            [self updateStatusItem];
        }
        return YES;
    }
    return NO;
}

- (void)scheduleNextMeetingBoundaryAfterDate:(NSDate *)date {
    [self.meetingScheduleTimer invalidate];
    self.meetingScheduleTimer = nil;
    if (!self.meetingScheduleStore.isEnabled) {
        return;
    }

    NSDate *nextBoundary = MeetingScheduleNextBoundaryAfterDate(date, self.meetingScheduleCalendar);
    if (!nextBoundary) {
        return;
    }
    self.meetingScheduleTimer = [[NSTimer alloc] initWithFireDate:nextBoundary
                                                        interval:0
                                                          target:self
                                                        selector:@selector(meetingScheduleBoundaryTimerFired:)
                                                        userInfo:nil
                                                         repeats:NO];
    [NSRunLoop.mainRunLoop addTimer:self.meetingScheduleTimer forMode:NSRunLoopCommonModes];
}

- (void)meetingScheduleBoundaryTimerFired:(NSTimer *)timer {
    NSDate *now = NSDate.date;
    [self reconcileMeetingScheduleAtDate:now];
    [self scheduleNextMeetingBoundaryAfterDate:now];
}

- (NSWindowCollectionBehavior)breakWindowCollectionBehavior {
    return NSWindowCollectionBehaviorCanJoinAllSpaces |
           NSWindowCollectionBehaviorFullScreenAuxiliary |
           NSWindowCollectionBehaviorStationary |
           NSWindowCollectionBehaviorTransient |
           NSWindowCollectionBehaviorIgnoresCycle;
}

- (void)showBreakWindowsWithMode:(CountdownScreenMode)mode {
    if (![self canPresentBreakWindows]) return;
    // Capture one screen configuration. During unplug/wake there may be no
    // screens at all; never construct an array containing a nil mainScreen.
    NSArray<NSScreen *> *screens = NSScreen.screens;
    NSArray<BreakWindow *> *previousWindows = self.breakWindows.copy;
    NSMutableArray<BreakWindow *> *activeWindows = [NSMutableArray array];
    for (NSScreen *screen in screens) {
        NSNumber *displayNumber = screen.deviceDescription[@"NSScreenNumber"];

        BreakWindow *window = nil;
        for (BreakWindow *candidate in previousWindows) {
            if (displayNumber && [candidate.displayNumber isEqualToNumber:displayNumber]) {
                window = candidate;
                break;
            }
        }
        NSRect localFrame = NSMakeRect(0, 0, NSWidth(screen.frame), NSHeight(screen.frame));
        if (!window) {
            window = [[BreakWindow alloc] initWithContentRect:localFrame
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO
                                                      screen:screen];
            window.displayNumber = displayNumber;
            window.releasedWhenClosed = NO;
            window.level = NSScreenSaverWindowLevel;
            window.backgroundColor = NSColor.blackColor;
            window.opaque = YES;
            window.hasShadow = NO;
            window.hidesOnDeactivate = NO;
            window.canHide = NO;
            window.collectionBehavior = [self breakWindowCollectionBehavior];

            CountdownView *view = [[CountdownView alloc] initWithFrame:localFrame];
            view.delegate = self;
            window.contentView = view;
        }
        [activeWindows addObject:window];

        // Window positions are global screen points; the view remains local.
        // Finish resizing and updating the model before requesting a redraw.
        [window setFrame:screen.frame display:NO];
        window.level = NSScreenSaverWindowLevel;
        window.canHide = NO;
        window.collectionBehavior = [self breakWindowCollectionBehavior];
        CountdownView *view = (CountdownView *)window.contentView;
        if ([view isKindOfClass:CountdownView.class]) {
            view.delegate = self;
            view.mode = mode;
            view.restEndsAt = mode == CountdownScreenModeResting ? self.phaseEndsAt : nil;
            view.restEndedEarly = mode == CountdownScreenModeDecision && self.restEndedEarly;
            view.needsDisplay = YES;
        }
    }

    // Retire disconnected displays, rather than leaving hidden windows in the
    // array that bringBreakWindowsToFront would subsequently show again.
    for (BreakWindow *window in previousWindows) {
        if (![activeWindows containsObject:window]) {
            [window orderOut:nil];
            [window close];
        }
    }
    self.breakWindows = activeWindows;

    if (mode == CountdownScreenModeResting) {
        [self updateRestWindowsWithRemainingSeconds:[self currentRestRemainingSeconds]];
    } else {
        [self updateDecisionWindows];
    }
    for (BreakWindow *window in activeWindows) {
        [window.contentView displayIfNeeded];
        [window makeKeyAndOrderFront:nil];
        [window orderFrontRegardless];
    }
    if (activeWindows.count > 0) {
        [NSRunningApplication.currentApplication activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    }
}

- (NSInteger)currentRestRemainingSeconds {
    [self refreshPhaseEndDate];
    return MAX(0, (NSInteger)ceil([self currentPhaseRemaining]));
}

- (NSInteger)currentSkipUnlockRemainingSeconds {
    if (self.phase != TimerPhaseResting) {
        return 0;
    }
    return MAX(0, (NSInteger)ceil(self.restSkipAvailableAtContinuousTime - BreakTimerContinuousTime()));
}

- (void)updateRestWindowsWithRemainingSeconds:(NSInteger)remainingSeconds {
    if (self.phase != TimerPhaseResting) {
        return;
    }

    CGFloat progress = (CGFloat)((NSTimeInterval)MAX(0, remainingSeconds) / self.restDuration);
    for (BreakWindow *window in self.breakWindows) {
        CountdownView *countdownView = (CountdownView *)window.contentView;
        if (![countdownView isKindOfClass:CountdownView.class]) {
            continue;
        }
        countdownView.mode = CountdownScreenModeResting;
        countdownView.restEndsAt = self.phaseEndsAt;
        countdownView.remainingSeconds = remainingSeconds;
        countdownView.progress = progress;
        countdownView.skipUnlockRemainingSeconds = [self currentSkipUnlockRemainingSeconds];
        countdownView.emergencySkipLimitReason = [self.emergencySkipQuotaStore usageAtDate:NSDate.date].limitReason;
        countdownView.snoozeAvailable = !self.hasSnoozedCurrentCycle;
        countdownView.restEndedEarly = NO;
        countdownView.displaySleepPending = self.restDisplaySleepToken != nil;
        countdownView.displaySleepPreparing = self.restDisplaySleepStage == RestDisplaySleepStagePreparing;
        countdownView.displayPowerMessage = self.restDisplayPowerMessage;
    }
}

- (void)updateDecisionWindows {
    for (BreakWindow *window in self.breakWindows) {
        CountdownView *countdownView = (CountdownView *)window.contentView;
        if (![countdownView isKindOfClass:CountdownView.class]) {
            continue;
        }
        countdownView.mode = CountdownScreenModeDecision;
        countdownView.restEndsAt = nil;
        countdownView.remainingSeconds = 0;
        countdownView.progress = 0;
        countdownView.skipUnlockRemainingSeconds = 0;
        countdownView.emergencySkipLimitReason = EmergencySkipLimitReasonNone;
        countdownView.snoozeAvailable = NO;
        countdownView.emergencySkipHolding = NO;
        countdownView.emergencySkipHoldRemaining = RestSkipHoldDuration;
        countdownView.restEndedEarly = self.restEndedEarly;
        countdownView.displaySleepPending = NO;
        countdownView.displaySleepPreparing = NO;
        countdownView.displayPowerMessage = self.restDisplayPowerMessage;
    }
}

- (void)updateEmergencySkipHoldViews {
    BOOL holding = self.emergencySkipHoldStartedAt != nil;
    NSTimeInterval remaining = RestSkipHoldDuration;
    if (holding) {
        NSTimeInterval elapsed = MAX(0, BreakTimerContinuousTime() - self.emergencySkipHoldStartedAtContinuousTime);
        remaining = MAX(0, RestSkipHoldDuration - elapsed);
    }

    for (BreakWindow *window in self.breakWindows) {
        CountdownView *countdownView = (CountdownView *)window.contentView;
        if (![countdownView isKindOfClass:CountdownView.class]) {
            continue;
        }
        countdownView.emergencySkipHolding = holding;
        countdownView.emergencySkipHoldRemaining = remaining;
    }
}

- (void)cancelEmergencySkipHold {
    [self.emergencySkipHoldTimer invalidate];
    self.emergencySkipHoldTimer = nil;
    self.emergencySkipHoldStartedAt = nil;
    self.emergencySkipHoldStartedAtContinuousTime = 0;
    self.emergencySkipHoldView = nil;
    [self updateEmergencySkipHoldViews];
}

- (void)emergencySkipHoldTick:(NSTimer *)timer {
    if (self.phase != TimerPhaseResting ||
        [self currentSkipUnlockRemainingSeconds] > 0 ||
        ![self.emergencySkipQuotaStore usageAtDate:NSDate.date].canSkip ||
        !self.emergencySkipHoldStartedAt ||
        ![self.emergencySkipHoldView isEmergencySkipPressActive]) {
        [self cancelEmergencySkipHold];
        return;
    }

    NSTimeInterval elapsed = MAX(0, BreakTimerContinuousTime() - self.emergencySkipHoldStartedAtContinuousTime);
    if (elapsed >= RestSkipHoldDuration) {
        AppLog(@"emergency skip hold completed");
        [self cancelEmergencySkipHold];
        if (![self.emergencySkipQuotaStore recordSuccessfulSkipAtDate:NSDate.date]) {
            AppLog(@"emergency skip quota became unavailable before completion");
            [self updateRestWindowsWithRemainingSeconds:[self currentRestRemainingSeconds]];
            return;
        }
        [self completeRestCycleWithEarlyEnd:YES];
        return;
    }

    [self updateEmergencySkipHoldViews];
}

- (void)dismissBreakWindows {
    AppLog(@"hide break windows");
    for (BreakWindow *window in self.breakWindows) {
        if ([window.contentView isKindOfClass:CountdownView.class]) {
            ((CountdownView *)window.contentView).displaySleepMousePressed = NO;
        }
        [window orderOut:nil];
    }
}

- (BOOL)canPresentBreakWindows {
    return !self.isAsleep && !self.systemSleeping && !self.restDisplaySleepToken &&
        !self.waitingForRestCompletionDisplayWake && [self anyOnlineDisplayIsAwake];
}

- (void)bringBreakWindowsToFront {
    if (![self canPresentBreakWindows]) return;
    for (BreakWindow *window in self.breakWindows) {
        [window makeKeyAndOrderFront:nil];
        [window orderFrontRegardless];
    }
    [NSRunningApplication.currentApplication activateWithOptions:NSApplicationActivateIgnoringOtherApps];
}

- (void)updateStatusItem {
    [self ensureStatusItemVisible];
    NSInteger remaining = MAX(0, (NSInteger)ceil([self currentPhaseRemaining]));
    NSInteger minutes = remaining / 60;
    NSInteger seconds = remaining % 60;
    NSString *timeText = [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)seconds];

    if (self.phase == TimerPhaseWorking) {
        self.statusItem.button.title = [NSString stringWithFormat:@"学习 %@", timeText];
        self.statusItem.button.toolTip = [NSString stringWithFormat:@"距离休息还有 %@", timeText];
    } else if (self.phase == TimerPhaseResting) {
        self.statusItem.button.title = [NSString stringWithFormat:@"休息 %@", timeText];
        self.statusItem.button.toolTip = [NSString stringWithFormat:@"休息倒计时 %@", timeText];
    } else if (self.phase == TimerPhaseSnoozingRest) {
        self.statusItem.button.title = [NSString stringWithFormat:@"稍后 %@", timeText];
        self.statusItem.button.toolTip = [NSString stringWithFormat:@"%@ 后开始休息", timeText];
    } else if (self.phase == TimerPhaseRestComplete) {
        self.statusItem.button.title = self.restEndedEarly ? @"休息已跳过" : @"休息结束";
        self.statusItem.button.toolTip = self.restEndedEarly
            ? @"本次休息已提前结束，请选择继续学习或停止学习"
            : @"请选择继续学习或停止学习";
    } else {
        self.statusItem.button.title = @"已停止";
        self.statusItem.button.toolTip = @"学习计时已停止";
    }
    [self updateConfigurableMenuItems];
}

- (void)startBreakNow:(id)sender {
    AppLog(@"menu requested rest now");
    BreakTimerActionPolicy policy = BreakTimerActionPolicyMake(self.phase, self.restObligationActive);
    if (policy.restAction == BreakTimerRestActionUnavailable) {
        AppLog(@"ignored rest request while already resting");
        return;
    }
    if (policy.restAction == BreakTimerRestActionStartSnoozedRestNow) {
        [self startRestCycleWithDuration:self.restDuration
                      activateObligation:NO
                        skipLockDuration:RestSkipLockDuration];
        return;
    }

    self.hasSnoozedCurrentCycle = NO;
    [self startRestCycle];
}

- (void)restartWorkFromMenu:(id)sender {
    AppLog(@"menu requested restart work");
    [self transitionExpiredPhaseIfNeeded];
    BreakTimerActionPolicy policy = BreakTimerActionPolicyMake(self.phase, self.restObligationActive);
    if (!policy.canStartWork) {
        AppLog(@"blocked menu work restart until rest is complete");
        return;
    }
    [self startWorkCycleFromUserAction];
}

- (void)openStatistics:(id)sender {
    AppLog(@"menu requested study statistics");
    if (!self.statisticsWindowController) {
        self.statisticsWindowController = [[StudyStatisticsWindowController alloc] initWithHistoryStore:self.historyStore];
    }
    [self.statisticsWindowController showStatisticsWindow];
}

- (void)openSettings:(id)sender {
    AppLog(@"menu requested settings");
    [self showSettingsWindow];
}

- (void)stopStudyFromMenu:(id)sender {
    AppLog(@"menu requested stop study");
    [self transitionExpiredPhaseIfNeeded];
    BreakTimerActionPolicy policy = BreakTimerActionPolicyMake(self.phase, self.restObligationActive);
    if (!policy.canStopStudy) {
        AppLog(@"blocked menu stop while rest obligation is active");
        return;
    }
    [self stopStudy];
}

- (void)showSettingsWindow {
    if (!self.settingsWindow) {
        NSRect frame = NSMakeRect(0, 0, 420, 440);
        self.settingsWindow = [[NSWindow alloc] initWithContentRect:frame
                                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO];
        self.settingsWindow.title = @"设置";
        self.settingsWindow.releasedWhenClosed = NO;
        self.settingsWindow.level = NSFloatingWindowLevel;

        NSView *contentView = [[NSView alloc] initWithFrame:frame];
        self.settingsWindow.contentView = contentView;

        NSTextField *titleLabel = [NSTextField labelWithString:@"学习时间（分钟）"];
        titleLabel.font = [NSFont systemFontOfSize:15 weight:NSFontWeightMedium];
        titleLabel.frame = NSMakeRect(32, 386, 160, 24);
        [contentView addSubview:titleLabel];

        self.settingsMinutesField = [[NSTextField alloc] initWithFrame:NSMakeRect(252, 383, 92, 30)];
        self.settingsMinutesField.font = [NSFont systemFontOfSize:15];
        self.settingsMinutesField.alignment = NSTextAlignmentRight;
        [contentView addSubview:self.settingsMinutesField];

        NSTextField *restTitleLabel = [NSTextField labelWithString:@"休息时间（分钟）"];
        restTitleLabel.font = [NSFont systemFontOfSize:15 weight:NSFontWeightMedium];
        restTitleLabel.frame = NSMakeRect(32, 336, 160, 24);
        [contentView addSubview:restTitleLabel];

        self.settingsRestMinutesField = [[NSTextField alloc] initWithFrame:NSMakeRect(252, 333, 92, 30)];
        self.settingsRestMinutesField.font = [NSFont systemFontOfSize:15];
        self.settingsRestMinutesField.alignment = NSTextAlignmentRight;
        [contentView addSubview:self.settingsRestMinutesField];

        NSTextField *rangeLabel = [NSTextField labelWithString:@"学习 1-240 分钟，休息 1-60 分钟，均为整数。"];
        rangeLabel.font = [NSFont systemFontOfSize:12];
        rangeLabel.textColor = NSColor.secondaryLabelColor;
        rangeLabel.frame = NSMakeRect(32, 294, 300, 20);
        [contentView addSubview:rangeLabel];

        NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(32, 276, 356, 1)];
        separator.boxType = NSBoxSeparator;
        [contentView addSubview:separator];

        NSTextField *skipTitle = [NSTextField labelWithString:@"紧急跳过额度"];
        skipTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
        skipTitle.frame = NSMakeRect(32, 237, 140, 24);
        [contentView addSubview:skipTitle];

        self.settingsSkipUsageLabel = [NSTextField labelWithString:@""];
        self.settingsSkipUsageLabel.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
        self.settingsSkipUsageLabel.textColor = NSColor.secondaryLabelColor;
        self.settingsSkipUsageLabel.frame = NSMakeRect(32, 209, 356, 22);
        [contentView addSubview:self.settingsSkipUsageLabel];

        NSBox *scheduleSeparator = [[NSBox alloc] initWithFrame:NSMakeRect(32, 190, 356, 1)];
        scheduleSeparator.boxType = NSBoxSeparator;
        [contentView addSubview:scheduleSeparator];

        self.settingsMeetingScheduleCheckbox = [NSButton checkboxWithTitle:@"会议日程自动停止"
                                                                    target:nil
                                                                    action:nil];
        self.settingsMeetingScheduleCheckbox.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
        self.settingsMeetingScheduleCheckbox.frame = NSMakeRect(28, 148, 220, 28);
        [contentView addSubview:self.settingsMeetingScheduleCheckbox];

        NSTextField *scheduleHint = [NSTextField labelWithString:@"周三、周日 14:00 自动停止，17:00 按规则恢复。"];
        scheduleHint.font = [NSFont systemFontOfSize:12];
        scheduleHint.textColor = NSColor.secondaryLabelColor;
        scheduleHint.frame = NSMakeRect(32, 122, 356, 20);
        [contentView addSubview:scheduleHint];

        NSBox *historySeparator = [[NSBox alloc] initWithFrame:NSMakeRect(32, 105, 356, 1)];
        historySeparator.boxType = NSBoxSeparator;
        [contentView addSubview:historySeparator];

        NSTextField *historyLabel = [NSTextField labelWithString:@"学习记录"];
        historyLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
        historyLabel.frame = NSMakeRect(32, 68, 120, 24);
        [contentView addSubview:historyLabel];

        NSButton *clearHistoryButton = [NSButton buttonWithTitle:@"清空学习记录..."
                                                         target:self
                                                         action:@selector(confirmClearHistory:)];
        clearHistoryButton.bezelStyle = NSBezelStyleRounded;
        clearHistoryButton.contentTintColor = NSColor.systemRedColor;
        clearHistoryButton.frame = NSMakeRect(248, 63, 140, 32);
        [contentView addSubview:clearHistoryButton];

        NSButton *saveButton = [NSButton buttonWithTitle:@"保存" target:self action:@selector(saveSettings:)];
        saveButton.bezelStyle = NSBezelStyleRounded;
        saveButton.keyEquivalent = @"\r";
        saveButton.frame = NSMakeRect(234, 18, 78, 32);
        [contentView addSubview:saveButton];

        NSButton *cancelButton = [NSButton buttonWithTitle:@"取消" target:self action:@selector(cancelSettings:)];
        cancelButton.bezelStyle = NSBezelStyleRounded;
        cancelButton.keyEquivalent = @"\e";
        cancelButton.frame = NSMakeRect(320, 18, 78, 32);
        [contentView addSubview:cancelButton];
    }

    self.settingsMinutesField.stringValue = [NSString stringWithFormat:@"%ld", (long)[self validatedWorkDurationMinutes]];
    self.settingsRestMinutesField.stringValue = [NSString stringWithFormat:@"%ld", (long)[self validatedRestDurationMinutes]];
    EmergencySkipUsage *usage = [self.emergencySkipQuotaStore usageAtDate:NSDate.date];
    self.settingsSkipUsageLabel.stringValue = [NSString stringWithFormat:@"今日已使用 %ld/%ld    本周已使用 %ld/%ld",
        (long)usage.dailyCount,
        (long)EmergencySkipQuotaStore.dailyLimit,
        (long)usage.weeklyCount,
        (long)EmergencySkipQuotaStore.weeklyLimit];
    self.settingsMeetingScheduleCheckbox.state = self.meetingScheduleStore.isEnabled
        ? NSControlStateValueOn
        : NSControlStateValueOff;
    [self.settingsWindow center];
    [self.settingsWindow makeKeyAndOrderFront:nil];
    [NSRunningApplication.currentApplication activateWithOptions:NSApplicationActivateIgnoringOtherApps];
}

- (void)saveSettings:(id)sender {
    NSInteger minutes = 0;
    NSInteger restMinutes = 0;
    BOOL validWork = ParseDurationMinutes(self.settingsMinutesField.stringValue, MaximumWorkDurationMinutes, &minutes);
    BOOL validRest = ParseDurationMinutes(self.settingsRestMinutesField.stringValue, MaximumRestDurationMinutes, &restMinutes);

    if (!validWork || !validRest) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"无法保存设置";
        alert.informativeText = !validWork ? @"学习时间请输入 1 到 240 之间的整数分钟。"
            : @"休息时间请输入 1 到 60 之间的整数分钟。";
        [alert addButtonWithTitle:@"好"];
        [alert beginSheetModalForWindow:self.settingsWindow completionHandler:nil];
        return;
    }

    [self.userDefaults setInteger:minutes forKey:WorkDurationMinutesDefaultsKey];
    [self.userDefaults setInteger:restMinutes forKey:RestDurationMinutesDefaultsKey];
    [self.userDefaults synchronize];
    self.meetingScheduleStore.enabled = self.settingsMeetingScheduleCheckbox.state == NSControlStateValueOn;
    if (!self.meetingScheduleStore.isEnabled) {
        [self.meetingScheduleStore cancelPendingAutoResume];
    }
    self.workDuration = minutes * 60;
    [self updateConfigurableMenuItems];
    NSDate *now = NSDate.date;
    [self reconcileMeetingScheduleAtDate:now];
    [self scheduleNextMeetingBoundaryAfterDate:now];
    AppLog([NSString stringWithFormat:@"saved duration minutes: work=%ld, rest=%ld", (long)minutes, (long)restMinutes]);
    [self.settingsWindow orderOut:nil];
}

- (void)cancelSettings:(id)sender {
    [self.settingsWindow orderOut:nil];
}

- (void)confirmClearHistory:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"清空全部学习记录？";
    alert.informativeText = @"所有日学习和月学习历史都会被删除，此操作无法撤销。";
    [alert addButtonWithTitle:@"清空"];
    [alert addButtonWithTitle:@"取消"];
    [alert beginSheetModalForWindow:self.settingsWindow completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) {
            return;
        }
        NSDate *now = NSDate.date;
        BOOL restartSession = self.phase == TimerPhaseWorking && !self.isAsleep;
        [self.historyStore clearAllHistoryAtDate:now restartSession:restartSession];
        [self.statisticsWindowController refresh];
        AppLog(@"cleared study history");
    }];
}

- (void)quitFromMenu:(id)sender {
    AppLog(@"menu requested quit app");
    [self transitionExpiredPhaseIfNeeded];
    BreakTimerActionPolicy policy = BreakTimerActionPolicyMake(self.phase, self.restObligationActive);
    if (!policy.canQuitApplication) {
        AppLog(@"blocked menu quit while rest obligation is active");
        return;
    }
    [self.historyStore endActiveSessionAtDate:NSDate.date];
    [self persistRestObligationSynchronously:YES];
    [self cancelRestDisplaySleep];
    userRequestedQuit = YES;
    [NSApp terminate:nil];
}

- (void)countdownViewDidBeginEmergencySkipHold:(CountdownView *)view {
    if (self.phase != TimerPhaseResting || !self.restObligationActive ||
        [self currentSkipUnlockRemainingSeconds] > 0 ||
        ![self.emergencySkipQuotaStore usageAtDate:NSDate.date].canSkip) {
        return;
    }

    AppLog(@"fullscreen began emergency skip hold");
    [self cancelEmergencySkipHold];
    self.emergencySkipHoldView = view;
    self.emergencySkipHoldStartedAt = NSDate.date;
    self.emergencySkipHoldStartedAtContinuousTime = BreakTimerContinuousTime();
    [self updateEmergencySkipHoldViews];

    self.emergencySkipHoldTimer = [NSTimer timerWithTimeInterval:0.05
                                                          target:self
                                                        selector:@selector(emergencySkipHoldTick:)
                                                        userInfo:nil
                                                         repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.emergencySkipHoldTimer forMode:NSRunLoopCommonModes];
}

- (void)countdownViewDidCancelEmergencySkipHold:(CountdownView *)view {
    if (self.emergencySkipHoldStartedAt) {
        AppLog(@"fullscreen cancelled emergency skip hold");
    }
    [self cancelEmergencySkipHold];
}

- (void)countdownViewDidRequestSnoozeRest:(CountdownView *)view {
    AppLog(@"fullscreen requested snooze rest");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self snoozeRestCycle];
    });
}

- (void)countdownViewDidRequestDisplaySleep:(CountdownView *)view {
    if (view.mode != CountdownScreenModeResting) return;
    [self requestRestDisplaySleep];
}

- (void)countdownViewDidRequestContinueStudy:(CountdownView *)view {
    AppLog(@"fullscreen requested continue study");
    if (self.phase != TimerPhaseRestComplete || self.restObligationActive) {
        AppLog(@"blocked fullscreen work start before rest completion");
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self startWorkCycleFromUserAction];
    });
}

- (void)countdownViewDidRequestStopStudy:(CountdownView *)view {
    AppLog(@"fullscreen requested stop study");
    if (self.phase != TimerPhaseRestComplete || self.restObligationActive) {
        AppLog(@"blocked fullscreen stop before rest completion");
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self stopStudy];
    });
}

- (void)beginEligibleInactivityAtDate:(NSDate *)now reason:(NSString *)reason {
    if (self.isAsleep) {
        return;
    }

    AppLog([NSString stringWithFormat:@"begin eligible inactivity: %@", reason]);
    if (self.restDisplaySleepToken && !self.systemSleeping) {
        if (self.restDisplaySleepStage == RestDisplaySleepStagePreparing) {
            [self cancelRestDisplaySleep];
        } else if (!self.restDisplaySleepConfirmed) {
            self.restDisplaySleepStage = RestDisplaySleepStageAsleep;
            AppLog([NSString stringWithFormat:@"rest display sleep confirmed, requestElapsed=%.3f",
                    BreakTimerContinuousTime() - self.restDisplaySleepRequestedAt]);
        }
    }
    self.eligibleInactivityStartedAtContinuousTime = BreakTimerContinuousTime();
    if (self.restObligationActive) {
        if (self.phase == TimerPhaseResting) {
            self.restRemainingAtInactivityStart = [self currentPhaseRemaining];
            self.skipLockRemainingAtInactivityStart = [self currentSkipUnlockRemainingSeconds];
        } else {
            self.restRemainingAtInactivityStart = self.restDuration;
            self.skipLockRemainingAtInactivityStart = RestSkipLockDuration;
        }
    } else {
        self.restRemainingAtInactivityStart = 0;
        self.skipLockRemainingAtInactivityStart = 0;
    }

    [self.historyStore endActiveSessionAtDate:now];
    [self cancelEmergencySkipHold];
    self.isAsleep = YES;
    [self.timer invalidate];
    self.timer = nil;
    [self dismissBreakWindows];
    self.statusItem.button.title = @"暂停";
    self.statusItem.button.toolTip = self.restObligationActive
        ? @"所有显示器关闭期间正在累计休息"
        : [NSString stringWithFormat:@"显示器唤醒后会重新开始 %ld 分钟", (long)[self validatedWorkDurationMinutes]];
    [self persistRestObligationSynchronously:YES];
    [self updateConfigurableMenuItems];
}

- (void)resumeAfterEligibleInactivityIfPossible {
    if (self.waitingForRestCompletionDisplayWake && !self.systemSleeping &&
        [self anyOnlineDisplayIsAwake]) {
        self.waitingForRestCompletionDisplayWake = NO;
        [self resetDisplayInactivity];
        if (self.phase == TimerPhaseRestComplete) {
            [self showBreakWindowsWithMode:CountdownScreenModeDecision];
        }
        return;
    }
    if (!self.isAsleep || self.systemSleeping || ![self anyOnlineDisplayIsAwake]) {
        return;
    }

    NSTimeInterval continuousNow = BreakTimerContinuousTime();
    NSTimeInterval inactiveDuration = self.eligibleInactivityStartedAtContinuousTime > 0
        ? MAX(0, continuousNow - self.eligibleInactivityStartedAtContinuousTime)
        : 0;
    NSTimeInterval remainingRest = BreakTimerRemainingRestAfterInactivity(
        self.restRemainingAtInactivityStart,
        inactiveDuration
    );
    NSTimeInterval remainingSkipLock = BreakTimerRemainingRestAfterInactivity(
        self.skipLockRemainingAtInactivityStart,
        inactiveDuration
    );
    BOOL hadRestObligation = self.restObligationActive;
    BOOL requestedRestDisplaySleep = self.restDisplaySleepToken && self.restDisplaySleepConfirmed;
    if (requestedRestDisplaySleep) {
        remainingRest = [self currentPhaseRemaining];
        AppLog([NSString stringWithFormat:@"rest display woke before automatic wake, screenOffElapsed=%.3f", inactiveDuration]);
        [self cancelRestDisplaySleep];
    }

    AppLog([NSString stringWithFormat:@"resume after eligible inactivity, elapsed=%.1f, restRemaining=%.1f",
            inactiveDuration, remainingRest]);
    self.isAsleep = NO;
    self.eligibleInactivityStartedAtContinuousTime = 0;
    self.restRemainingAtInactivityStart = 0;
    self.skipLockRemainingAtInactivityStart = 0;

    if (hadRestObligation && remainingRest > 0) {
        [self startRestCycleWithDuration:remainingRest
                      activateObligation:NO
                        skipLockDuration:remainingSkipLock];
        return;
    }
    if (hadRestObligation) {
        if (requestedRestDisplaySleep) {
            [self completeRestCycle];
            return;
        }
        AppLog(@"rest obligation satisfied while every display was asleep");
        self.restObligationActive = NO;
        [self clearPersistedRestObligation];
    }
    [self startWorkCycle];
}

- (BOOL)allOnlineDisplaysAreAsleep {
    return self.workspaceScreensAsleep || BreakTimerAllOnlineDisplaysAreAsleep();
}

- (BOOL)anyOnlineDisplayIsAwake {
    return !self.workspaceScreensAsleep && BreakTimerAnyOnlineDisplayIsAwake();
}

- (void)reconcileDisplayInactivity {
    if (self.systemSleeping) {
        return;
    }
    if (self.restDisplaySleepToken) {
        [self restDisplaySleepTick];
        return;
    }
    if ([self allOnlineDisplaysAreAsleep]) {
        [self beginEligibleInactivityAtDate:NSDate.date reason:@"all online displays asleep"];
    } else if (![self reconcileMeetingScheduleAtDate:NSDate.date]) {
        [self resumeAfterEligibleInactivityIfPossible];
    }
}

- (void)systemWillSleep:(NSNotification *)notification {
    self.systemSleeping = YES;
    [self cancelRestDisplaySleep];
    [self beginEligibleInactivityAtDate:NSDate.date reason:@"system sleep"];
}

- (void)systemDidWake:(NSNotification *)notification {
    AppLog(@"system did wake");
    self.systemSleeping = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSDate *now = NSDate.date;
        if (![self reconcileMeetingScheduleAtDate:now]) {
            [self resumeAfterEligibleInactivityIfPossible];
        }
        [self scheduleNextMeetingBoundaryAfterDate:now];
    });
}

- (void)screensDidSleep:(NSNotification *)notification {
    // Workspace notifications describe session display power even when a
    // virtual/online display keeps the Core Graphics query reporting awake.
    AppLog(@"workspace screens did sleep");
    self.workspaceScreensAsleep = YES;
    [self reconcileDisplayInactivity];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self reconcileDisplayInactivity];
    });
}

- (void)screensDidWake:(NSNotification *)notification {
    AppLog(@"workspace screens did wake");
    self.workspaceScreensAsleep = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSDate *now = NSDate.date;
        if (![self reconcileMeetingScheduleAtDate:now]) {
            [self resumeAfterEligibleInactivityIfPossible];
        }
        [self scheduleNextMeetingBoundaryAfterDate:now];
    });
}

- (void)systemClockOrTimeZoneChanged:(NSNotification *)notification {
    self.meetingScheduleCalendar.timeZone = NSTimeZone.localTimeZone;
    NSDate *now = NSDate.date;
    [self reconcileMeetingScheduleAtDate:now];
    [self scheduleNextMeetingBoundaryAfterDate:now];
    if (self.phase == TimerPhaseResting && !self.isAsleep) {
        [self updateRestWindowsWithRemainingSeconds:[self currentRestRemainingSeconds]];
    }
}

- (void)applicationDidResignActive:(NSNotification *)notification {
    if (self.emergencySkipHoldStartedAt) {
        AppLog(@"cancel emergency skip hold because application resigned active");
        [self cancelEmergencySkipHold];
    }
}

- (void)screenConfigurationChanged:(NSNotification *)notification {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self reconcileDisplayInactivity];
        if (self.phase == TimerPhaseResting && !self.isAsleep && !self.restDisplaySleepToken) {
            [self cancelEmergencySkipHold];
            [self showBreakWindowsWithMode:CountdownScreenModeResting];
        } else if (self.phase == TimerPhaseRestComplete && !self.isAsleep && !self.waitingForRestCompletionDisplayWake) {
            [self showBreakWindowsWithMode:CountdownScreenModeDecision];
        }
    });
}

- (void)activeSpaceDidChange:(NSNotification *)notification {
    if (self.isAsleep || self.restDisplaySleepToken || self.waitingForRestCompletionDisplayWake) {
        return;
    }

    if (self.phase == TimerPhaseResting) {
        AppLog(@"active space changed during rest");
        [self cancelEmergencySkipHold];
        [self showBreakWindowsWithMode:CountdownScreenModeResting];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.isAsleep || self.restDisplaySleepToken || self.phase != TimerPhaseResting) return;
            [self updateRestWindowsWithRemainingSeconds:[self currentRestRemainingSeconds]];
            [self bringBreakWindowsToFront];
        });
    } else if (self.phase == TimerPhaseRestComplete) {
        AppLog(@"active space changed after rest complete");
        [self showBreakWindowsWithMode:CountdownScreenModeDecision];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.isAsleep || self.waitingForRestCompletionDisplayWake || self.phase != TimerPhaseRestComplete) return;
            [self bringBreakWindowsToFront];
        });
    }
}

@end

#if !defined(FOCUS_BREAK_TIMER_DISABLE_APP_MAIN)

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) BreakTimerController *controller;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    AppLog([NSString stringWithFormat:@"app launched version %@", version]);
    MigrateLegacyPreferencesIfNeeded();
    self.controller = [[BreakTimerController alloc] init];
    [self.controller start];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    AppLog([NSString stringWithFormat:@"application should terminate, userRequestedQuit=%@", userRequestedQuit ? @"YES" : @"NO"]);
    return userRequestedQuit ? NSTerminateNow : NSTerminateCancel;
}

@end

static AppDelegate *appDelegate;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSSetUncaughtExceptionHandler(&HandleUncaughtException);
        NSApplication *app = NSApplication.sharedApplication;
        appDelegate = [[AppDelegate alloc] init];
        app.delegate = appDelegate;
        [app run];
    }

    return 0;
}

#endif
