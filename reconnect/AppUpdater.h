#import <Cocoa/Cocoa.h>

@interface KakaoTalkAppUpdater : NSObject
+ (instancetype)sharedUpdater;
- (void)attachToMenu:(NSMenu *)menu;
@end
