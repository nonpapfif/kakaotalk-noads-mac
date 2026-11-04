#import "../reconnect/SessionReconnect.m"

static int starts, ticks, stops, connects, closes, nativeDisconnects;
@interface FCTimerController : NSObject
- (void)startTimer;
- (void)onTimer;
- (void)stopTimer;
@end
@implementation FCTimerController
- (void)startTimer { starts++; }
- (void)onTimer { ticks++; }
- (void)stopTimer { stops++; }
@end
@interface LocoAgent : NSObject
- (void)connect;
@end
@implementation LocoAgent
- (void)connect { connects++; }
@end
@interface LocoManager : NSObject
- (void)logout;
@end
@implementation LocoManager
- (void)logout { closes++; }
@end
@interface TestLoco : NSObject
@property(nonatomic) BOOL loggedIn;
@property(nonatomic, strong) LocoManager *locoManager;
@end
@implementation TestLoco
@end
@interface TestAuth : NSObject
@property(nonatomic) BOOL isLoggedIn;
@property(nonatomic) BOOL isLoggingOut;
@end
@implementation TestAuth
@end
@interface BCLocoClient : TestLoco
- (void)locoManager:(id)manager didChangeStatusFromStatus:(signed char)previous
          toStatus:(signed char)next;
@end
@implementation BCLocoClient
- (void)locoManager:(id)manager didChangeStatusFromStatus:(signed char)previous
          toStatus:(signed char)next {
    (void)manager; (void)previous;
    self.loggedIn = next == 25;
}
@end
@interface MacTalkCore : NSObject
@property(nonatomic, strong) FCTimerController *timer;
@property(nonatomic, strong) TestAuth *auth;
@property(nonatomic, strong) TestLoco *loco;
+ (instancetype)core;
@end
@implementation MacTalkCore
+ (instancetype)core {
    static MacTalkCore *core;
    if (!core) {
        core = [MacTalkCore new];
        core.timer = [FCTimerController new];
        core.auth = [TestAuth new];
        core.loco = [TestLoco new];
        core.loco.locoManager = [LocoManager new];
    }
    return core;
}
@end
static void NativeDisconnect(id auth, SEL selector, id notification) {
    (void)auth; (void)selector; (void)notification;
    nativeDisconnects++;
}
int main(void) {
    @autoreleasepool {
        controller = [SessionReconnectController new];
        NSCAssert(InstallHoldTransportHooks(), @"reviewed transport hook ABI");
        MacTalkCore *core = [MacTalkCore core];
        LocoAgent *agent = [LocoAgent new];
        [core.timer startTimer]; [core.timer onTimer]; [agent connect];
        NSCAssert(starts == 1 && ticks == 1 && connects == 1, @"normal flow preserved");
        controller.holding = YES;
        SessionNetworkGateSetHeld(YES);
        ReconnectDidLogin(core, @selector(description));
        NSCAssert(SessionNetworkGateIsHeld(), @"late login event cannot release Hold");
        [controller stopHeldSessionWork];
        [controller stopHeldSessionWork];
        NSCAssert(stops == 1 && closes == 1, @"cleanup runs once per Hold");
        [core.timer startTimer]; [core.timer onTimer]; [agent connect];
        NSCAssert(starts == 1 && ticks == 1 && connects == 1, @"Hold blocks background work");
        TestAuth *auth = [TestAuth new]; auth.isLoggedIn = YES;
        originalDisconnect = (IMP)NativeDisconnect;
        PreserveIdleSessionOnDisconnect(auth, @selector(description), nil);
        NSCAssert(nativeDisconnects == 0 && auth.isLoggedIn, @"cleanup keeps authenticated UI");
        auth.isLoggingOut = YES;
        PreserveIdleSessionOnDisconnect(auth, @selector(description), nil);
        NSCAssert(nativeDisconnects == 1, @"explicit logout remains native");
        auth.isLoggingOut = NO;
        controller.reconnecting = YES;
        [agent connect]; [core.timer startTimer];
        NSCAssert(connects == 2 && starts == 1, @"manual login can open transport only");
        [controller leaveHold];
        NSCAssert(!SessionNetworkGateIsHeld(), @"leaving Hold releases the network gate");
        NSCAssert(starts == 1 && !controller.holdWorkStopped,
                  @"failed or logged-out state does not restart timers");
        controller.reconnecting = NO;
        controller.holding = YES;
        [controller stopHeldSessionWork];
        core.loco.loggedIn = YES;
        [controller leaveHold];
        [controller leaveHold];
        NSCAssert(starts == 2 && stops == 2 && closes == 2,
                  @"successful recovery restarts timer once");
        [agent connect]; [core.timer onTimer];
        NSCAssert(connects == 3 && ticks == 2, @"normal flow resumes");
        BCLocoClient *client = [BCLocoClient new];
        core.auth.isLoggedIn = YES;
        client.loggedIn = YES;
        [client locoManager:nil didChangeStatusFromStatus:25 toStatus:24];
        NSCAssert(controller.holding && !client.loggedIn,
                  @"connection loss enters Hold before a delayed error callback");
        controller.holding = NO;
        controller.reconnecting = YES;
        client.loggedIn = YES;
        [client locoManager:nil didChangeStatusFromStatus:25 toStatus:24];
        NSCAssert(!controller.holding, @"manual login transitions do not enter Hold");
        controller.reconnecting = NO;
        core.auth.isLoggingOut = YES;
        client.loggedIn = YES;
        [client locoManager:nil didChangeStatusFromStatus:25 toStatus:24];
        NSCAssert(!controller.holding, @"explicit logout transition stays native");
        puts("Hold transport runtime checks passed.");
    }
}
