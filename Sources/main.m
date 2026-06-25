#import <Cocoa/Cocoa.h>
#import <math.h>

typedef NS_ENUM(NSInteger, TimerPhase) {
    TimerPhaseWorking,
    TimerPhaseResting,
    TimerPhaseRestComplete,
    TimerPhaseSnoozingRest,
    TimerPhaseStopped
};

typedef NS_ENUM(NSInteger, CountdownScreenMode) {
    CountdownScreenModeResting,
    CountdownScreenModeDecision
};

static BOOL userRequestedQuit = NO;
static NSString * const WorkDurationMinutesDefaultsKey = @"workDurationMinutes";
static const NSInteger DefaultWorkDurationMinutes = 20;
static const NSInteger MinimumWorkDurationMinutes = 1;
static const NSInteger MaximumWorkDurationMinutes = 240;
static const NSTimeInterval RestSnoozeDuration = 60;

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
- (void)countdownViewDidRequestStopRest:(CountdownView *)view;
- (void)countdownViewDidRequestSnoozeRest:(CountdownView *)view;
- (void)countdownViewDidRequestContinueStudy:(CountdownView *)view;
- (void)countdownViewDidRequestStopStudy:(CountdownView *)view;
@end

@interface BreakWindow : NSWindow
@end

@implementation BreakWindow

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
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

@interface CountdownView : NSView
@property (nonatomic) NSInteger remainingSeconds;
@property (nonatomic) CGFloat progress;
@property (nonatomic) CountdownScreenMode mode;
@property (nonatomic, strong) NSDate *restEndsAt;
@property (nonatomic, weak) id<CountdownViewDelegate> delegate;
@property (nonatomic) NSRect stopRestButtonRect;
@property (nonatomic) NSRect snoozeRestButtonRect;
@property (nonatomic) NSRect continueStudyButtonRect;
@property (nonatomic) NSRect stopStudyButtonRect;
@end

@implementation CountdownView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _remainingSeconds = 5 * 60;
        _progress = 1.0;
        _mode = CountdownScreenModeResting;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }
    return self;
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
    _mode = mode;
    self.needsDisplay = YES;
}

- (void)setRestEndsAt:(NSDate *)restEndsAt {
    _restEndsAt = restEndsAt;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    [self drawBackground];
    [self drawBackdrop];
    [self drawCountdown];
    [self drawActionButtons];
}

- (void)drawBackground {
    [[NSColor colorWithCalibratedRed:0.032 green:0.052 blue:0.056 alpha:1.0] setFill];
    NSRectFill(self.bounds);
}

- (NSRect)progressRingRect {
    CGFloat shortestSide = MIN(NSWidth(self.bounds), NSHeight(self.bounds));
    CGFloat diameter = MIN(MIN(NSWidth(self.bounds) * 0.58, NSHeight(self.bounds) * 0.54), 720.0);
    diameter = MAX(MIN(diameter, shortestSide - 96.0), 260.0);
    CGFloat centerY = NSMidY(self.bounds) + MIN(NSHeight(self.bounds) * 0.05, 46.0);

    return NSMakeRect(
        NSMidX(self.bounds) - diameter / 2.0,
        centerY - diameter / 2.0,
        diameter,
        diameter
    );
}

- (CGFloat)ringLineWidthForRect:(NSRect)ringRect {
    return MIN(MAX(NSWidth(ringRect) * 0.035, 14.0), 26.0);
}

- (void)drawBackdrop {
    NSRect ringRect = [self progressRingRect];
    CGFloat lineWidth = [self ringLineWidthForRect:ringRect];
    NSRect strokeRect = NSInsetRect(ringRect, lineWidth / 2.0, lineWidth / 2.0);

    NSBezierPath *innerPath = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(strokeRect, lineWidth * 1.6, lineWidth * 1.6)];
    [[NSColor colorWithCalibratedRed:0.05 green:0.12 blue:0.12 alpha:0.20] setFill];
    [innerPath fill];

    NSBezierPath *trackPath = [NSBezierPath bezierPathWithOvalInRect:strokeRect];
    trackPath.lineWidth = lineWidth;
    trackPath.lineCapStyle = NSLineCapStyleRound;
    [[NSColor colorWithCalibratedRed:0.18 green:0.31 blue:0.30 alpha:0.34] setStroke];
    [trackPath stroke];

    CGFloat clampedProgress = self.mode == CountdownScreenModeResting ? MIN(MAX(self.progress, 0.0), 1.0) : 0.0;
    if (clampedProgress <= 0.001) {
        return;
    }

    NSPoint center = NSMakePoint(NSMidX(strokeRect), NSMidY(strokeRect));
    CGFloat radius = NSWidth(strokeRect) / 2.0;
    NSBezierPath *progressPath = [NSBezierPath bezierPath];
    [progressPath appendBezierPathWithArcWithCenter:center
                                             radius:radius
                                         startAngle:90.0
                                           endAngle:90.0 - 360.0 * clampedProgress
                                          clockwise:YES];
    progressPath.lineWidth = lineWidth;
    progressPath.lineCapStyle = NSLineCapStyleRound;
    [[NSColor colorWithCalibratedRed:0.31 green:0.88 blue:0.78 alpha:0.96] setStroke];
    [progressPath stroke];
}

- (void)drawCountdown {
    NSRect ringRect = [self progressRingRect];
    NSInteger safeRemaining = MAX(0, self.remainingSeconds);
    NSInteger minutes = safeRemaining / 60;
    NSInteger seconds = safeRemaining % 60;
    NSString *countdown = [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)seconds];
    NSString *title = self.mode == CountdownScreenModeResting ? @"休息一下" : @"休息结束";

    CGFloat titleSize = MIN(MAX(NSWidth(ringRect) * 0.085, 32.0), 70.0);
    NSDictionary<NSAttributedStringKey, id> *titleAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:titleSize weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.93 alpha:0.90]
    };
    NSSize titleMeasured = [title sizeWithAttributes:titleAttributes];
    [title drawAtPoint:NSMakePoint(
        NSMidX(ringRect) - titleMeasured.width / 2.0,
        MIN(NSMaxY(ringRect) + MIN(NSHeight(self.bounds) * 0.035, 38.0), NSMaxY(self.bounds) - titleMeasured.height - 28.0)
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

    NSString *hint = @"去看远处，同时眨眼";
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

    if (self.mode == CountdownScreenModeResting && self.restEndsAt) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        formatter.dateFormat = @"H点mm分'结束休息'";
        NSString *endText = [formatter stringFromDate:self.restEndsAt];
        CGFloat endSize = MIN(MAX(NSWidth(ringRect) * 0.040, 18.0), 30.0);
        NSDictionary<NSAttributedStringKey, id> *endAttributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:endSize weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.72 green:0.92 blue:0.88 alpha:0.82]
        };
        NSSize endMeasured = [endText sizeWithAttributes:endAttributes];
        [endText drawAtPoint:NSMakePoint(
            NSMidX(ringRect) - endMeasured.width / 2.0,
            NSMidY(ringRect) - timerMeasured.height / 2.0 - hintMeasured.height - endMeasured.height - MIN(NSHeight(ringRect) * 0.070, 42.0)
        ) withAttributes:endAttributes];
    }
}

- (void)drawActionButtons {
    NSRect ringRect = [self progressRingRect];
    CGFloat buttonHeight = MIN(MAX(NSHeight(self.bounds) * 0.075, 68.0), 92.0);
    CGFloat buttonWidth = MIN(MAX(NSWidth(self.bounds) * 0.19, 240.0), 360.0);
    CGFloat gap = 28.0;
    CGFloat ringGap = MIN(MAX(NSHeight(self.bounds) * 0.045, 34.0), 56.0);
    CGFloat buttonY = MAX(NSMinY(self.bounds) + NSHeight(self.bounds) * 0.075, NSMinY(ringRect) - buttonHeight - ringGap);

    if (self.mode == CountdownScreenModeResting) {
        CGFloat totalWidth = buttonWidth * 2.0 + gap;
        self.snoozeRestButtonRect = NSMakeRect(
            NSMidX(self.bounds) - totalWidth / 2.0,
            buttonY,
            buttonWidth,
            buttonHeight
        );
        self.stopRestButtonRect = NSMakeRect(
            NSMidX(self.bounds) - totalWidth / 2.0 + buttonWidth + gap,
            buttonY,
            buttonWidth,
            buttonHeight
        );
        [self drawButtonInRect:self.snoozeRestButtonRect
                         title:@"1分钟后休息"
                     fillColor:[NSColor colorWithCalibratedRed:0.16 green:0.64 blue:0.48 alpha:1.0]
                   strokeColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.30]];
        [self drawButtonInRect:self.stopRestButtonRect
                         title:@"停止休息"
                     fillColor:[NSColor colorWithCalibratedRed:0.88 green:0.22 blue:0.20 alpha:1.0]
                   strokeColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.28]];
        return;
    }

    CGFloat totalWidth = buttonWidth * 2.0 + gap;
    self.continueStudyButtonRect = NSMakeRect(
        NSMidX(self.bounds) - totalWidth / 2.0,
        buttonY,
        buttonWidth,
        buttonHeight
    );
    self.stopStudyButtonRect = NSMakeRect(
        NSMidX(self.bounds) - totalWidth / 2.0 + buttonWidth + gap,
        buttonY,
        buttonWidth,
        buttonHeight
    );

    [self drawButtonInRect:self.continueStudyButtonRect
                     title:@"继续学习"
                 fillColor:[NSColor colorWithCalibratedRed:0.16 green:0.64 blue:0.48 alpha:1.0]
               strokeColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.30]];
    [self drawButtonInRect:self.stopStudyButtonRect
                     title:@"停止学习"
                 fillColor:[NSColor colorWithCalibratedRed:0.88 green:0.22 blue:0.20 alpha:1.0]
               strokeColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.28]];
}

- (void)drawButtonInRect:(NSRect)rect title:(NSString *)title fillColor:(NSColor *)fillColor strokeColor:(NSColor *)strokeColor {
    NSBezierPath *shadowPath = [NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(rect, 0.0, -4.0) xRadius:14.0 yRadius:14.0];
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.30] setFill];
    [shadowPath fill];

    NSBezierPath *buttonPath = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:14.0 yRadius:14.0];
    [fillColor setFill];
    [buttonPath fill];
    buttonPath.lineWidth = 2.0;
    [strokeColor setStroke];
    [buttonPath stroke];

    CGFloat fontSize = MIN(MAX(NSWidth(rect) * 0.14, 26.0), 38.0);
    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:fontSize weight:NSFontWeightBold],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    NSSize textSize = [title sizeWithAttributes:attributes];
    [title drawAtPoint:NSMakePoint(
        NSMidX(rect) - textSize.width / 2.0,
        NSMidY(rect) - textSize.height / 2.0
    ) withAttributes:attributes];
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];

    if (self.mode == CountdownScreenModeResting && NSPointInRect(point, self.stopRestButtonRect)) {
        [self.delegate countdownViewDidRequestStopRest:self];
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

@end

@interface BreakTimerController : NSObject <CountdownViewDelegate>
@property (nonatomic) NSTimeInterval workDuration;
@property (nonatomic) NSTimeInterval restDuration;
@property (nonatomic) TimerPhase phase;
@property (nonatomic, strong) NSDate *phaseEndsAt;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSMutableArray<BreakWindow *> *breakWindows;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenuItem *restartItem;
@property (nonatomic, strong) NSWindow *settingsWindow;
@property (nonatomic, strong) NSTextField *settingsMinutesField;
@property (nonatomic, strong) NSWindow *keepAliveWindow;
@property (nonatomic) BOOL isAsleep;
@end

@implementation BreakTimerController

- (instancetype)init {
    self = [super init];
    if (self) {
        [NSUserDefaults.standardUserDefaults registerDefaults:@{
            WorkDurationMinutesDefaultsKey: @(DefaultWorkDurationMinutes)
        }];
        _workDuration = [self validatedWorkDurationMinutes] * 60;
        _restDuration = 5 * 60;
        _phase = TimerPhaseWorking;
        _phaseEndsAt = NSDate.date;
        _breakWindows = [NSMutableArray array];
    }
    return self;
}

- (void)start {
    [self configureKeepAliveWindow];
    [self configureStatusItem];
    [self registerSystemNotifications];
    [self startWorkCycle];
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
    self.statusItem.button.title = [NSString stringWithFormat:@"学习 %02ld:00", (long)[self workDurationMinutes]];
    self.statusItem.button.toolTip = @"学习休息倒计时";

    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *breakItem = [[NSMenuItem alloc] initWithTitle:@"立刻休息 5 分钟" action:@selector(startBreakNow:) keyEquivalent:@"b"];
    self.restartItem = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(restartWorkFromMenu:) keyEquivalent:@"r"];
    NSMenuItem *settingsItem = [[NSMenuItem alloc] initWithTitle:@"设置..." action:@selector(openSettings:) keyEquivalent:@","];
    NSMenuItem *stopItem = [[NSMenuItem alloc] initWithTitle:@"停止学习" action:@selector(stopStudyFromMenu:) keyEquivalent:@"s"];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"退出应用" action:@selector(quitFromMenu:) keyEquivalent:@"q"];
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSMenuItem *versionItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"版本 %@", version] action:nil keyEquivalent:@""];
    versionItem.enabled = NO;

    breakItem.target = self;
    self.restartItem.target = self;
    settingsItem.target = self;
    stopItem.target = self;
    quitItem.target = self;

    [self updateConfigurableMenuItems];
    [menu addItem:breakItem];
    [menu addItem:self.restartItem];
    [menu addItem:settingsItem];
    [menu addItem:stopItem];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:versionItem];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
}

- (void)registerSystemNotifications {
    NSNotificationCenter *workspaceCenter = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspaceCenter addObserver:self selector:@selector(systemWillSleep:) name:NSWorkspaceWillSleepNotification object:nil];
    [workspaceCenter addObserver:self selector:@selector(systemDidWake:) name:NSWorkspaceDidWakeNotification object:nil];
    [workspaceCenter addObserver:self selector:@selector(screensDidSleep:) name:NSWorkspaceScreensDidSleepNotification object:nil];
    [workspaceCenter addObserver:self selector:@selector(screensDidWake:) name:NSWorkspaceScreensDidWakeNotification object:nil];
    [workspaceCenter addObserver:self selector:@selector(activeSpaceDidChange:) name:NSWorkspaceActiveSpaceDidChangeNotification object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screenConfigurationChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
}

- (NSInteger)validatedWorkDurationMinutes {
    NSInteger minutes = [NSUserDefaults.standardUserDefaults integerForKey:WorkDurationMinutesDefaultsKey];
    if (minutes < MinimumWorkDurationMinutes || minutes > MaximumWorkDurationMinutes) {
        minutes = DefaultWorkDurationMinutes;
        [NSUserDefaults.standardUserDefaults setInteger:minutes forKey:WorkDurationMinutesDefaultsKey];
    }
    return minutes;
}

- (NSInteger)workDurationMinutes {
    return MAX(MinimumWorkDurationMinutes, (NSInteger)llround(self.workDuration / 60.0));
}

- (void)reloadWorkDurationFromDefaults {
    self.workDuration = [self validatedWorkDurationMinutes] * 60;
}

- (void)updateConfigurableMenuItems {
    self.restartItem.title = [NSString stringWithFormat:@"开始/重新开始 %ld 分钟", (long)[self validatedWorkDurationMinutes]];
}

- (void)startWorkCycle {
    AppLog(@"start work cycle");
    [self reloadWorkDurationFromDefaults];
    self.isAsleep = NO;
    self.phase = TimerPhaseWorking;
    self.phaseEndsAt = [NSDate dateWithTimeIntervalSinceNow:self.workDuration];
    [self dismissBreakWindows];
    [self scheduleTick];
    [self updateStatusItem];
}

- (void)startRestCycle {
    if (self.isAsleep) {
        return;
    }

    AppLog(@"start rest cycle");
    self.phase = TimerPhaseResting;
    self.phaseEndsAt = [NSDate dateWithTimeIntervalSinceNow:self.restDuration];
    [self showBreakWindowsWithMode:CountdownScreenModeResting];
    [self scheduleTick];
    [self updateStatusItem];
}

- (void)completeRestCycle {
    AppLog(@"complete rest cycle");
    self.phase = TimerPhaseRestComplete;
    self.phaseEndsAt = NSDate.date;
    [self.timer invalidate];
    self.timer = nil;

    if (self.breakWindows.count == 0) {
        [self showBreakWindowsWithMode:CountdownScreenModeDecision];
    }
    [self updateDecisionWindows];
    [self bringBreakWindowsToFront];
    [self updateStatusItem];
}

- (void)snoozeRestCycle {
    AppLog(@"snooze rest for one minute");
    self.phase = TimerPhaseSnoozingRest;
    self.phaseEndsAt = [NSDate dateWithTimeIntervalSinceNow:RestSnoozeDuration];
    [self dismissBreakWindows];
    [self scheduleTick];
    [self updateStatusItem];
}

- (void)stopStudy {
    AppLog(@"stop study, keep app running");
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

- (void)tick:(NSTimer *)timer {
    if (self.isAsleep || self.phase == TimerPhaseStopped || self.phase == TimerPhaseRestComplete) {
        return;
    }

    NSTimeInterval remaining = self.phaseEndsAt.timeIntervalSinceNow;
    if (remaining <= 0) {
        if (self.phase == TimerPhaseWorking) {
            [self startRestCycle];
        } else if (self.phase == TimerPhaseResting) {
            [self completeRestCycle];
        } else if (self.phase == TimerPhaseSnoozingRest) {
            [self startRestCycle];
        }
        return;
    }

    [self updateStatusItem];
    if (self.phase == TimerPhaseResting) {
        [self updateRestWindowsWithRemainingSeconds:(NSInteger)ceil(remaining)];
        [self bringBreakWindowsToFront];
    }
}

- (NSWindowCollectionBehavior)breakWindowCollectionBehavior {
    return NSWindowCollectionBehaviorCanJoinAllSpaces |
           NSWindowCollectionBehaviorFullScreenAuxiliary |
           NSWindowCollectionBehaviorStationary |
           NSWindowCollectionBehaviorTransient |
           NSWindowCollectionBehaviorIgnoresCycle;
}

- (void)showBreakWindowsWithMode:(CountdownScreenMode)mode {
    NSArray<NSScreen *> *screens = NSScreen.screens.count > 0 ? NSScreen.screens : @[NSScreen.mainScreen];
    for (NSUInteger index = 0; index < screens.count; index++) {
        NSScreen *screen = screens[index];
        if (!screen) {
            continue;
        }

        BreakWindow *window = nil;
        if (index < self.breakWindows.count) {
            window = self.breakWindows[index];
        } else {
            window = [[BreakWindow alloc] initWithContentRect:screen.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
            window.level = NSScreenSaverWindowLevel;
            window.backgroundColor = NSColor.blackColor;
            window.opaque = YES;
            window.hidesOnDeactivate = NO;
            window.canHide = NO;
            window.collectionBehavior = [self breakWindowCollectionBehavior];

            CountdownView *view = [[CountdownView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(screen.frame), NSHeight(screen.frame))];
            view.delegate = self;
            window.contentView = view;
            [self.breakWindows addObject:window];
        }

        [window setFrame:screen.frame display:YES];
        window.level = NSScreenSaverWindowLevel;
        window.canHide = NO;
        window.collectionBehavior = [self breakWindowCollectionBehavior];
        CountdownView *view = (CountdownView *)window.contentView;
        if ([view isKindOfClass:CountdownView.class]) {
            view.frame = NSMakeRect(0, 0, NSWidth(screen.frame), NSHeight(screen.frame));
            view.delegate = self;
            view.mode = mode;
            view.restEndsAt = mode == CountdownScreenModeResting ? self.phaseEndsAt : nil;
        }
        [window makeKeyAndOrderFront:nil];
        [window orderFrontRegardless];
    }

    if (self.breakWindows.count > screens.count) {
        for (NSUInteger index = screens.count; index < self.breakWindows.count; index++) {
            [self.breakWindows[index] orderOut:nil];
        }
    }

    [NSRunningApplication.currentApplication activateWithOptions:NSApplicationActivateIgnoringOtherApps];

    if (mode == CountdownScreenModeResting) {
        [self updateRestWindowsWithRemainingSeconds:[self currentRestRemainingSeconds]];
    } else {
        [self updateDecisionWindows];
    }
}

- (NSInteger)currentRestRemainingSeconds {
    return MAX(0, (NSInteger)ceil(self.phaseEndsAt.timeIntervalSinceNow));
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
    }
}

- (void)dismissBreakWindows {
    AppLog(@"hide break windows");
    for (BreakWindow *window in self.breakWindows) {
        [window orderOut:nil];
    }
}

- (void)bringBreakWindowsToFront {
    for (BreakWindow *window in self.breakWindows) {
        [window makeKeyAndOrderFront:nil];
        [window orderFrontRegardless];
    }
    [NSRunningApplication.currentApplication activateWithOptions:NSApplicationActivateIgnoringOtherApps];
}

- (void)updateStatusItem {
    NSInteger remaining = MAX(0, (NSInteger)ceil(self.phaseEndsAt.timeIntervalSinceNow));
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
        self.statusItem.button.title = @"休息结束";
        self.statusItem.button.toolTip = @"请选择继续学习或停止学习";
    } else {
        self.statusItem.button.title = @"已停止";
        self.statusItem.button.toolTip = @"学习计时已停止";
    }
}

- (void)startBreakNow:(id)sender {
    AppLog(@"menu requested rest now");
    [self startRestCycle];
}

- (void)restartWorkFromMenu:(id)sender {
    AppLog(@"menu requested restart work");
    [self startWorkCycle];
}

- (void)openSettings:(id)sender {
    AppLog(@"menu requested settings");
    [self showSettingsWindow];
}

- (void)stopStudyFromMenu:(id)sender {
    AppLog(@"menu requested stop study");
    [self stopStudy];
}

- (void)showSettingsWindow {
    if (!self.settingsWindow) {
        NSRect frame = NSMakeRect(0, 0, 360, 180);
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
        titleLabel.frame = NSMakeRect(32, 116, 160, 24);
        [contentView addSubview:titleLabel];

        self.settingsMinutesField = [[NSTextField alloc] initWithFrame:NSMakeRect(192, 113, 92, 30)];
        self.settingsMinutesField.font = [NSFont systemFontOfSize:15];
        self.settingsMinutesField.alignment = NSTextAlignmentRight;
        [contentView addSubview:self.settingsMinutesField];

        NSTextField *rangeLabel = [NSTextField labelWithString:@"请输入 1 到 240 的整数。"];
        rangeLabel.font = [NSFont systemFontOfSize:12];
        rangeLabel.textColor = NSColor.secondaryLabelColor;
        rangeLabel.frame = NSMakeRect(32, 82, 260, 20);
        [contentView addSubview:rangeLabel];

        NSButton *saveButton = [NSButton buttonWithTitle:@"保存" target:self action:@selector(saveSettings:)];
        saveButton.bezelStyle = NSBezelStyleRounded;
        saveButton.keyEquivalent = @"\r";
        saveButton.frame = NSMakeRect(174, 28, 78, 32);
        [contentView addSubview:saveButton];

        NSButton *cancelButton = [NSButton buttonWithTitle:@"取消" target:self action:@selector(cancelSettings:)];
        cancelButton.bezelStyle = NSBezelStyleRounded;
        cancelButton.keyEquivalent = @"\e";
        cancelButton.frame = NSMakeRect(260, 28, 78, 32);
        [contentView addSubview:cancelButton];
    }

    self.settingsMinutesField.stringValue = [NSString stringWithFormat:@"%ld", (long)[self validatedWorkDurationMinutes]];
    [self.settingsWindow center];
    [self.settingsWindow makeKeyAndOrderFront:nil];
    [NSRunningApplication.currentApplication activateWithOptions:NSApplicationActivateIgnoringOtherApps];
}

- (void)saveSettings:(id)sender {
    NSString *input = [self.settingsMinutesField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSScanner *scanner = [NSScanner scannerWithString:input];
    NSInteger minutes = 0;

    if (input.length == 0 || ![scanner scanInteger:&minutes] || !scanner.isAtEnd ||
        minutes < MinimumWorkDurationMinutes || minutes > MaximumWorkDurationMinutes) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"无法保存设置";
        alert.informativeText = @"学习时间请输入 1 到 240 之间的整数分钟。";
        [alert addButtonWithTitle:@"好"];
        [alert beginSheetModalForWindow:self.settingsWindow completionHandler:nil];
        return;
    }

    [NSUserDefaults.standardUserDefaults setInteger:minutes forKey:WorkDurationMinutesDefaultsKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    self.workDuration = minutes * 60;
    [self updateConfigurableMenuItems];
    AppLog([NSString stringWithFormat:@"saved work duration minutes: %ld", (long)minutes]);
    [self.settingsWindow orderOut:nil];
}

- (void)cancelSettings:(id)sender {
    [self.settingsWindow orderOut:nil];
}

- (void)quitFromMenu:(id)sender {
    AppLog(@"menu requested quit app");
    userRequestedQuit = YES;
    [NSApp terminate:nil];
}

- (void)countdownViewDidRequestStopRest:(CountdownView *)view {
    AppLog(@"fullscreen requested stop rest");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self completeRestCycle];
    });
}

- (void)countdownViewDidRequestSnoozeRest:(CountdownView *)view {
    AppLog(@"fullscreen requested snooze rest");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self snoozeRestCycle];
    });
}

- (void)countdownViewDidRequestContinueStudy:(CountdownView *)view {
    AppLog(@"fullscreen requested continue study");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self startWorkCycle];
    });
}

- (void)countdownViewDidRequestStopStudy:(CountdownView *)view {
    AppLog(@"fullscreen requested stop study");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self stopStudy];
    });
}

- (void)systemWillSleep:(NSNotification *)notification {
    AppLog(@"system will sleep");
    self.isAsleep = YES;
    [self.timer invalidate];
    self.timer = nil;
    [self dismissBreakWindows];
    self.statusItem.button.title = @"暂停";
    self.statusItem.button.toolTip = @"电脑唤醒后会重新开始 20 分钟";
}

- (void)systemDidWake:(NSNotification *)notification {
    AppLog(@"system did wake");
    [self startWorkCycle];
}

- (void)screensDidSleep:(NSNotification *)notification {
    [self systemWillSleep:notification];
}

- (void)screensDidWake:(NSNotification *)notification {
    [self systemDidWake:notification];
}

- (void)screenConfigurationChanged:(NSNotification *)notification {
    if (self.phase == TimerPhaseResting && !self.isAsleep) {
        [self showBreakWindowsWithMode:CountdownScreenModeResting];
    } else if (self.phase == TimerPhaseRestComplete && !self.isAsleep) {
        [self showBreakWindowsWithMode:CountdownScreenModeDecision];
    }
}

- (void)activeSpaceDidChange:(NSNotification *)notification {
    if (self.isAsleep) {
        return;
    }

    if (self.phase == TimerPhaseResting) {
        AppLog(@"active space changed during rest");
        [self showBreakWindowsWithMode:CountdownScreenModeResting];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self updateRestWindowsWithRemainingSeconds:[self currentRestRemainingSeconds]];
            [self bringBreakWindowsToFront];
        });
    } else if (self.phase == TimerPhaseRestComplete) {
        AppLog(@"active space changed after rest complete");
        [self showBreakWindowsWithMode:CountdownScreenModeDecision];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self bringBreakWindowsToFront];
        });
    }
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) BreakTimerController *controller;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    AppLog([NSString stringWithFormat:@"app launched version %@", version]);
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
