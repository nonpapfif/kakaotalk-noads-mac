#import "SessionDisconnectPolicy.h"
int main(void) {
    @autoreleasepool {
        NSCAssert(PreserveDisconnectedSession(@0, YES, NO, NO, NO, NO), @"idle disconnect");
        NSCAssert(!PreserveDisconnectedSession(nil, YES, NO, NO, NO, NO), @"unknown reason");
        NSCAssert(!PreserveDisconnectedSession(@"0", YES, NO, NO, NO, NO), @"invalid reason type");
        NSCAssert(!PreserveDisconnectedSession(@3, YES, NO, NO, NO, NO), @"other error");
        NSCAssert(!PreserveDisconnectedSession(@0, NO, NO, NO, NO, NO), @"already logged out");
        NSCAssert(!PreserveDisconnectedSession(@0, YES, YES, NO, NO, NO), @"explicit logout");
        NSCAssert(!PreserveDisconnectedSession(@0, YES, NO, YES, NO, NO), @"auto login attempt");
        NSCAssert(!PreserveDisconnectedSession(@0, YES, NO, NO, YES, NO), @"manual reconnect");
        NSCAssert(!PreserveDisconnectedSession(@0, YES, NO, NO, NO, YES), @"connected client");
        NSCAssert(AllowHeldSessionAuthentication(NO, NO), @"normal authentication");
        NSCAssert(!AllowHeldSessionAuthentication(YES, NO), @"no background auth in hold");
        NSCAssert(AllowHeldSessionAuthentication(YES, YES), @"manual reconnect from hold");
        puts("Twelve disconnect and hold policy cases passed.");
    }
}
