#import <Cocoa/Cocoa.h>

@interface SessionSidebarButton : NSButton
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL holding;
@end

@interface SessionReconnectFeedback : NSView
- (void)showMessage:(NSString *)message spinning:(BOOL)spinning inView:(NSView *)content;
@end
