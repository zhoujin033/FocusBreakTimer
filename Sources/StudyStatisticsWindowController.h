#import <Cocoa/Cocoa.h>

@class StudyHistoryStore;

NS_ASSUME_NONNULL_BEGIN

@interface StudyStatisticsWindowController : NSWindowController
- (instancetype)initWithHistoryStore:(StudyHistoryStore *)historyStore;
- (void)showStatisticsWindow;
- (void)refresh;
@end

NS_ASSUME_NONNULL_END
