#import <Cocoa/Cocoa.h>
#import "AppUpdater.h"
#import "SessionDisconnectPolicy.h"
#import <objc/message.h>
#import <objc/runtime.h>

@interface SessionSidebarButton : NSButton
@property(nonatomic, strong) NSTrackingArea *hoverArea;
@property(nonatomic) BOOL hovered;
@property(nonatomic, strong) NSProgressIndicator *spinner;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL holding;
- (void)setBusy:(BOOL)busy;
@end

@implementation SessionSidebarButton
- (void)setBusy:(BOOL)busy {
    _busy = busy;
    if (busy && !self.spinner) {
        self.spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(10, 10, 16, 16)];
        self.spinner.style = NSProgressIndicatorStyleSpinning;
        self.spinner.controlSize = NSControlSizeSmall;
        self.spinner.usesThreadedAnimation = YES;
        self.spinner.displayedWhenStopped = NO;
        [self addSubview:self.spinner];
    }
    if (busy) [self.spinner startAnimation:nil];
    else [self.spinner stopAnimation:nil];
    self.needsDisplay = YES;
}
- (void)updateTrackingAreas {
    if (self.hoverArea) [self removeTrackingArea:self.hoverArea];
    self.hoverArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways |
                NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:self.hoverArea];
    [super updateTrackingAreas];
}
- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    self.hovered = YES;
    self.needsDisplay = YES;
}
- (void)mouseExited:(NSEvent *)event {
    (void)event;
    self.hovered = NO;
    self.needsDisplay = YES;
}
- (BOOL)isFlipped { return YES; }
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSString *appearance = [self.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL dark = [appearance isEqualToString:NSAppearanceNameDarkAqua];
    BOOL active = NSApp.active && self.window.keyWindow;
    BOOL pressed = self.cell.highlighted;
    CGFloat alpha = active ? (dark ? 0.68 : 0.64) : (dark ? 0.32 : 0.30);
    CGFloat background = 0;
    if (self.hovered && self.enabled) {
        background = dark ? 0.05 : 0.04;
        if (!active) alpha = dark ? 0.44 : 0.42;
    }
    if (pressed) { alpha = dark ? 0.92 : 0.90; background = dark ? 0.10 : 0.07; }
    if (!self.enabled) alpha = dark ? 0.32 : 0.30;
    CGFloat channel = dark ? 1 : 0;
    if (background > 0) {
        [[NSColor colorWithSRGBRed:channel green:channel blue:channel alpha:background] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:self.bounds] fill];
    }
    if (self.busy) return;
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(25.2, 19.2)];
    [path curveToPoint:NSMakePoint(18, 26.4) controlPoint1:NSMakePoint(25.2, 23.176)
        controlPoint2:NSMakePoint(21.976, 26.4)];
    [path curveToPoint:NSMakePoint(10.8, 19.2) controlPoint1:NSMakePoint(14.024, 26.4)
        controlPoint2:NSMakePoint(10.8, 23.176)];
    [path curveToPoint:NSMakePoint(18, 12) controlPoint1:NSMakePoint(10.8, 15.224)
        controlPoint2:NSMakePoint(14.024, 12)];
    [path lineToPoint:NSMakePoint(22, 12)];
    [path moveToPoint:NSMakePoint(19, 9)];
    [path lineToPoint:NSMakePoint(22, 12)];
    [path lineToPoint:NSMakePoint(19, 15)];
    path.lineWidth = 1.4;
    path.lineCapStyle = NSLineCapStyleRound;
    path.lineJoinStyle = NSLineJoinStyleRound;
    NSAffineTransform *scale = [NSAffineTransform transform];
    [scale translateXBy:NSWidth(self.bounds) / 2 + 0.3 yBy:NSHeight(self.bounds) / 2];
    [scale scaleXBy:NSWidth(self.bounds) / 36 * 0.90 yBy:NSHeight(self.bounds) / 36 * 0.90];
    [scale translateXBy:-18 yBy:-18];
    [path transformUsingAffineTransform:scale];
    [[NSColor colorWithSRGBRed:channel green:channel blue:channel alpha:alpha] setStroke];
    [path stroke];
    if (self.holding) {
        [[NSColor.systemOrangeColor colorWithAlphaComponent:active ? 1.0 : 0.55] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(27, 5, 5, 5)] fill];
    }
}

@end

static NSButton *FindNativeSidebarButton(NSView *view, NSString *label) {
    if ([view isKindOfClass:NSButton.class] &&
        ([view.accessibilityLabel isEqualToString:label] ||
         [view.accessibilityTitle isEqualToString:label])) return (NSButton *)view;
    for (NSView *child in view.subviews) {
        NSButton *button = FindNativeSidebarButton(child, label);
        if (button) return button;
    }
    return nil;
}

static NSRect SidebarReconnectFrame(NSView *parent, NSButton *bell, NSButton *settings) {
    if (bell) {
        NSRect frame = [bell convertRect:bell.bounds toView:parent];
        CGFloat gap = 38;
        if (settings) {
            NSRect lower = [settings convertRect:settings.bounds toView:parent];
            CGFloat measured = fabs(NSMidY(frame) - NSMidY(lower));
            if (measured >= 28 && measured <= 64) gap = measured;
        }
        CGFloat y = NSMidY(frame) + (parent.isFlipped ? -gap : gap);
        return NSMakeRect(NSMidX(frame) - 18, y - 18, 36, 36);
    }
    CGFloat y = parent.isFlipped ? NSHeight(parent.bounds) - 134 : 98;
    return NSMakeRect(20, y, 36, 36);
}

static id SendObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static BOOL SendBool(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (![object respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSUInteger RebindOpenChatModels(id core) {
    id store = SendObject(NSClassFromString(@"NTDataStore"), @"sharedInstance");
    id nest = SendObject(store, @"nest");
    if (!nest) return 0;
    id manager = SendObject(core, @"chatWinManager");
    NSMutableOrderedSet *controllers = [NSMutableOrderedSet orderedSet];
    for (NSString *property in @[@"chatWindowControllers", @"chatThreadWindowControllers"]) {
        id windows = SendObject(manager, property);
        id enumerator = SendObject(windows, @"objectEnumerator");
        id values = SendObject(enumerator, @"allObjects");
        if (![values isKindOfClass:NSArray.class]) continue;
        for (id window in values) {
            id chat = SendObject(window, @"chattingController");
            if (chat) [controllers addObject:chat];
        }
    }
    NSUInteger updated = 0;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    NSString *notification = @"MKNestDidChangeNotification";
    SEL changed = NSSelectorFromString(@"didChangeObjects:");
    SEL chatID = NSSelectorFromString(@"chatId");
    SEL roomLookup = NSSelectorFromString(@"chatRoomWithId:");
    SEL update = NSSelectorFromString(@"updateChatRoom:");
    SEL fetch = NSSelectorFromString(@"fetchLatestMessagesWithReadmark:");
    Class rooms = NSClassFromString(@"NTChatRoom");
    if (![rooms respondsToSelector:roomLookup]) return 0;
    for (id chat in controllers) {
        if (![chat respondsToSelector:changed] || ![chat respondsToSelector:chatID] ||
            ![chat respondsToSelector:update] || ![chat respondsToSelector:fetch]) continue;
        int64_t identifier = ((int64_t (*)(id, SEL))objc_msgSend)(chat, chatID);
        if (identifier <= 0) continue;
        id room = ((id (*)(id, SEL, int64_t))objc_msgSend)(rooms, roomLookup, identifier);
        if (!room) continue;
        ((void (*)(id, SEL, id))objc_msgSend)(chat, update, room);
        [center removeObserver:chat name:notification object:nil];
        [center addObserver:chat selector:changed name:notification object:nest];
        ((void (*)(id, SEL, BOOL))objc_msgSend)(chat, fetch, NO);
        updated++;
    }
    return updated;
}

@interface SessionReconnectFeedback : NSView
@end
@implementation SessionReconnectFeedback
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithSRGBRed:81.0 / 255 green:81.0 / 255 blue:81.0 / 255
                        alpha:224.0 / 255] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:14 yRadius:14] fill];
}
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
@end

@interface SessionReconnectController : NSObject
@property(nonatomic, strong) NSMenuItem *status;
@property(nonatomic, strong) NSMenuItem *button;
@property(nonatomic, strong) NSButton *sidebarButton;
@property(nonatomic) BOOL installed;
@property(nonatomic) BOOL awaitingConnectionEvent;
@property(nonatomic) BOOL loginHookReady;
@property(nonatomic, strong) NSDate *lastRequest;
@property(atomic) BOOL reconnecting;
@property(atomic) BOOL holding;
@property(nonatomic, strong) SessionReconnectFeedback *feedback;
@property(nonatomic, strong) NSTextField *feedbackLabel;
@property(nonatomic, strong) NSProgressIndicator *feedbackSpinner;
@property(nonatomic) NSUInteger feedbackGeneration;
- (void)enterHold;
- (void)leaveHold;
- (void)install;
- (void)ensureMenu;
- (void)attachSidebarButton;
- (void)setReconnectEnabled:(BOOL)enabled;
- (void)showStatus:(NSString *)message;
- (void)showFeedback:(NSString *)message spinning:(BOOL)spinning;
- (void)finishFeedback:(NSString *)message;
- (void)reconnect:(id)sender;
- (void)didConnectCore:(id)core;
@end

static SessionReconnectController *controller;
static IMP originalDidLogin;

static void ReconnectDidLogin(id core, SEL selector) {
    ((void (*)(id, SEL))originalDidLogin)(core, selector);
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller leaveHold];
        [controller didConnectCore:core];
    });
}

static BOOL InstallLoginHook(void) {
    Class core = NSClassFromString(@"MacTalkCore");
    Method method = class_getInstanceMethod(core, NSSelectorFromString(@"locoClientDidLogin"));
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char *type = method_copyReturnType(method);
    BOOL valid = type && strcmp(type, "v") == 0;
    free(type);
    if (!valid) return NO;
    originalDidLogin = method_setImplementation(method, (IMP)ReconnectDidLogin);
    return originalDidLogin != NULL;
}

static IMP originalDisconnect;

static void PreserveIdleSessionOnDisconnect(id auth, SEL selector, id notification) {
    id core = SendObject(NSClassFromString(@"MacTalkCore"), @"core");
    id loco = SendObject(core, @"loco");
    id info = SendObject(SendObject(notification, @"object"), @"userInfo");
    id reason = [info isKindOfClass:NSDictionary.class]
        ? info[@"LPErrorLocoKickoutedReasonCodeKey"] : nil;
    if (loco && PreserveDisconnectedSession(reason, SendBool(auth, @"isLoggedIn"),
        SendBool(auth, @"isLoggingOut"),
        SendBool(auth, @"doingAutoLogin") || SendBool(auth, @"isTryingToLogin"),
        controller.reconnecting, SendBool(loco, @"loggedIn"))) {
        [controller enterHold];
        return;
    }
    ((void (*)(id, SEL, id))originalDisconnect)(auth, selector, notification);
}

static BOOL InstallDisconnectGuard(void) {
    Method method = class_getInstanceMethod(NSClassFromString(@"FCAuthController"),
        NSSelectorFromString(@"locoDidDisconnect:"));
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char *result = method_copyReturnType(method);
    char *argument = method_copyArgumentType(method, 2);
    BOOL valid = result && strcmp(result, "v") == 0 && argument && argument[0] == '@';
    free(result);
    free(argument);
    if (!valid) return NO;
    originalDisconnect = method_setImplementation(method, (IMP)PreserveIdleSessionOnDisconnect);
    return originalDisconnect != NULL;
}

static IMP originalKickoutPush;
static IMP originalRefreshToken;
static IMP originalAutoLogin;
static IMP originalAuthLogout;

static void HoldOnKickoutPush(id client, SEL selector, id manager, id notice) {
    id auth = SendObject(SendObject(NSClassFromString(@"MacTalkCore"), @"core"), @"auth");
    if (SendBool(auth, @"isLoggedIn") && !SendBool(auth, @"isLoggingOut")) [controller enterHold];
    ((void (*)(id, SEL, id, id))originalKickoutPush)(client, selector, manager, notice);
}
static void RefreshTokenOutsideHold(id manager, SEL selector) {
    if (!AllowHeldSessionAuthentication(controller.holding, controller.reconnecting)) return;
    ((void (*)(id, SEL))originalRefreshToken)(manager, selector);
}
static void AutoLoginOutsideHold(id auth, SEL selector, BOOL force) {
    if (!AllowHeldSessionAuthentication(controller.holding, controller.reconnecting)) return;
    ((void (*)(id, SEL, BOOL))originalAutoLogin)(auth, selector, force);
}
static void ClearHoldOnLogout(id auth, SEL selector) {
    ((void (*)(id, SEL))originalAuthLogout)(auth, selector);
    dispatch_async(dispatch_get_main_queue(), ^{ [controller leaveHold]; });
}
static BOOL ValidVoidMethod(Method method, unsigned int arguments) {
    if (!method || method_getNumberOfArguments(method) != arguments) return NO;
    char *type = method_copyReturnType(method);
    BOOL valid = type && strcmp(type, "v") == 0;
    free(type);
    return valid;
}
static BOOL InstallHoldHooks(void) {
    Class auth = NSClassFromString(@"FCAuthController");
    Method kickout = class_getInstanceMethod(NSClassFromString(@"BCLocoClient"),
        NSSelectorFromString(@"locoManager:didReceiveKickOutPushNotice:"));
    Method refresh = class_getInstanceMethod(NSClassFromString(@"LPTokenManager"),
        NSSelectorFromString(@"refreshToken"));
    Method login = class_getInstanceMethod(auth, NSSelectorFromString(@"autoLoginWithForce:"));
    Method logout = class_getInstanceMethod(auth, NSSelectorFromString(@"coreDidLogout"));
    if (!ValidVoidMethod(kickout, 4) || !ValidVoidMethod(refresh, 2) ||
        !ValidVoidMethod(login, 3) || !ValidVoidMethod(logout, 2)) return NO;
    char *forceType = method_copyArgumentType(login, 2);
    BOOL valid = forceType && (forceType[0] == 'c' || forceType[0] == 'B');
    free(forceType);
    if (!valid) return NO;
    originalKickoutPush = method_setImplementation(kickout, (IMP)HoldOnKickoutPush);
    originalRefreshToken = method_setImplementation(refresh, (IMP)RefreshTokenOutsideHold);
    originalAutoLogin = method_setImplementation(login, (IMP)AutoLoginOutsideHold);
    originalAuthLogout = method_setImplementation(logout, (IMP)ClearHoldOnLogout);
    return YES;
}

@implementation SessionReconnectController
- (void)install {
    if (self.installed || !NSApp.mainMenu) return;
    self.installed = YES;
    self.loginHookReady = InstallLoginHook();
    BOOL holdReady = InstallDisconnectGuard() && InstallHoldHooks();
    [self ensureMenu];
    if (!holdReady) [self showStatus:@"Hold protection is unavailable."];
    [self attachSidebarButton];
    for (NSNotificationName name in @[NSWindowDidBecomeKeyNotification,
            NSWindowDidResignKeyNotification, NSApplicationDidResignActiveNotification,
            NSApplicationDidBecomeActiveNotification]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                (void)note;
                self.sidebarButton.needsDisplay = YES;
            }];
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidResizeNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            (void)note;
            [self attachSidebarButton];
        }];
    dispatch_async(dispatch_get_main_queue(), ^{ [self attachSidebarButton]; });
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeKeyNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            (void)note;
            [self ensureMenu];
            [self attachSidebarButton];
        }];
    [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidBecomeActiveNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            (void)note;
            [self ensureMenu];
            [self attachSidebarButton];
            if (self.lastRequest) {
                id core = SendObject(NSClassFromString(@"MacTalkCore"), @"core");
                id auth = SendObject(core, @"auth");
                [self setReconnectEnabled:!self.reconnecting && !SendBool(auth, @"doingAutoLogin")];
            }
        }];
}

- (void)ensureMenu {
    if (!NSApp.mainMenu || [NSApp.mainMenu itemWithTitle:@"Session"]) return;
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:@"Session" action:nil keyEquivalent:@""];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Session"];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:self.holding
        ? @"Reconnect on This Mac (Hold)" : @"Reconnect on This Mac"
        action:@selector(reconnect:) keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];
    self.button = item;
    menu.autoenablesItems = NO;
    [menu addItem:NSMenuItem.separatorItem];
    NSString *previousStatus = self.status.title ?: @"Ready to reconnect";
    self.status = [[NSMenuItem alloc] initWithTitle:previousStatus action:nil keyEquivalent:@""];
    self.status.enabled = NO;
    [menu addItem:self.status];
    root.submenu = menu;
    [NSApp.mainMenu addItem:root];
}

- (void)attachSidebarButton {
    id core = SendObject(NSClassFromString(@"MacTalkCore"), @"core");
    id main = SendObject(core, @"main");
    id windowController = SendObject(main, @"mainWindowController");
    NSWindow *window = SendObject(windowController, @"window");
    if (![window isKindOfClass:NSWindow.class]) return;
    id mainView = SendObject(windowController, @"mainViewController");
    NSMenu *settingsMenu = SendObject(mainView, @"miscMenu");
    [[KakaoTalkAppUpdater sharedUpdater] attachToMenu:settingsMenu];
    NSView *content = window.contentView;
    if (!content) return;
    NSButton *bell = FindNativeSidebarButton(content, @"Notifications");
    NSButton *settings = FindNativeSidebarButton(content, @"Settings");
    if (!bell || !settings || bell.superview != settings.superview) {
        [self.sidebarButton removeFromSuperview];
        self.sidebarButton = nil;
        [self.feedback removeFromSuperview];
        return;
    }
    NSView *parent = bell.superview;
    if (self.sidebarButton.superview != parent) {
        [self.sidebarButton removeFromSuperview];
        self.sidebarButton = [[SessionSidebarButton alloc] initWithFrame:NSZeroRect];
        self.sidebarButton.target = self;
        self.sidebarButton.action = @selector(reconnect:);
        self.sidebarButton.bordered = NO;
        self.sidebarButton.title = @"";
        self.sidebarButton.toolTip = @"Reconnect on This Mac";
        self.sidebarButton.accessibilityLabel = @"Reconnect on This Mac";
        self.sidebarButton.identifier = @"SessionReconnectSidebarButton";
        self.sidebarButton.enabled = self.button.enabled;
        [parent addSubview:self.sidebarButton];
    }
    self.sidebarButton.frame = SidebarReconnectFrame(parent, bell, settings);
    self.sidebarButton.autoresizingMask = NSViewMaxXMargin |
        (parent.isFlipped ? NSViewMinYMargin : NSViewMaxYMargin);
    [(SessionSidebarButton *)self.sidebarButton setBusy:self.reconnecting];
    ((SessionSidebarButton *)self.sidebarButton).holding = self.holding;
    self.sidebarButton.accessibilityValue = self.reconnecting ? @"Reconnecting"
        : (self.holding ? @"Hold" : @"Ready");
    if (self.holding && !self.reconnecting)
        self.sidebarButton.toolTip = @"Hold — Disconnected. Click to reconnect on this Mac.";
    self.sidebarButton.needsDisplay = YES;
    NSDictionary *layout = @{
        @"native_button_found": @(bell != nil),
        @"same_parent_as_notifications": @(bell && self.sidebarButton.superview == bell.superview),
        @"parent_class": NSStringFromClass(parent.class),
        @"reconnect_frame": NSStringFromRect(self.sidebarButton.frame),
        @"bell_frame": bell ? NSStringFromRect([bell convertRect:bell.bounds toView:parent]) : @"",
        @"settings_frame": settings ? NSStringFromRect([settings convertRect:settings.bounds toView:parent]) : @""
    };
    NSURL *cache = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory
        inDomains:NSUserDomainMask].firstObject;
    if (cache) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:layout options:0 error:nil];
        [data writeToURL:[cache URLByAppendingPathComponent:@"SessionReconnect-layout.json"]
            atomically:YES];
    }
}

- (void)enterHold {
    self.holding = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.button.title = @"Reconnect on This Mac (Hold)";
        ((SessionSidebarButton *)self.sidebarButton).holding = YES;
        self.sidebarButton.accessibilityValue = @"Hold";
        [self showStatus:@"Hold — Disconnected. Click Reconnect on This Mac to continue."];
        self.sidebarButton.needsDisplay = YES;
    });
}
- (void)leaveHold {
    self.holding = NO;
    self.button.title = @"Reconnect on This Mac";
    ((SessionSidebarButton *)self.sidebarButton).holding = NO;
    id core = SendObject(NSClassFromString(@"MacTalkCore"), @"core");
    BOOL connected = SendBool(SendObject(core, @"loco"), @"loggedIn");
    self.sidebarButton.accessibilityValue = connected ? @"Connected" : @"Ready";
    [self showStatus:connected ? @"Connected." : @"Sign in first if saved login is unavailable."];
    self.sidebarButton.needsDisplay = YES;
}

- (void)setReconnectEnabled:(BOOL)enabled {
    self.button.enabled = enabled;
    self.sidebarButton.enabled = enabled;
}

- (void)showStatus:(NSString *)message {
    self.status.title = message;
    self.sidebarButton.toolTip = [@"Reconnect on This Mac\n" stringByAppendingString:message];
}

- (void)showFeedback:(NSString *)message spinning:(BOOL)spinning {
    NSUInteger generation = ++self.feedbackGeneration;
    id core = SendObject(NSClassFromString(@"MacTalkCore"), @"core");
    NSWindow *window = SendObject(SendObject(SendObject(core, @"main"),
                                            @"mainWindowController"), @"window");
    if (![window isKindOfClass:NSWindow.class] || !window.contentView) return;
    NSView *content = window.contentView;
    if (!self.feedback) {
        self.feedback = [[SessionReconnectFeedback alloc] initWithFrame:NSMakeRect(0, 0, 190, 84)];
        self.feedback.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
        self.feedback.wantsLayer = YES;
        self.feedback.layer.cornerRadius = 14;
        self.feedback.layer.masksToBounds = YES;
        self.feedbackLabel = [NSTextField wrappingLabelWithString:@""];
        self.feedbackLabel.alignment = NSTextAlignmentCenter;
        self.feedbackLabel.preferredMaxLayoutWidth = 170;
        self.feedbackLabel.maximumNumberOfLines = 2;
        self.feedbackLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        self.feedbackLabel.textColor = NSColor.whiteColor;
        [self.feedback addSubview:self.feedbackLabel];
        self.feedbackSpinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(85, 46, 20, 20)];
        self.feedbackSpinner.style = NSProgressIndicatorStyleSpinning;
        self.feedbackSpinner.usesThreadedAnimation = YES;
        self.feedbackSpinner.displayedWhenStopped = NO;
        [self.feedback addSubview:self.feedbackSpinner];
    }
    self.feedback.frame = NSMakeRect((NSWidth(content.bounds) - 190) / 2,
                                     (NSHeight(content.bounds) - 84) / 2, 190, 84);
    self.feedback.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin |
                                     NSViewMinYMargin | NSViewMaxYMargin;
    self.feedbackLabel.stringValue = message;
    CGFloat textHeight = MIN(36, MAX(17, ceil(self.feedbackLabel.fittingSize.height)));
    CGFloat groupHeight = textHeight + (spinning ? 28 : 0);
    CGFloat textY = (NSHeight(self.feedback.bounds) - groupHeight) / 2;
    self.feedbackLabel.frame = NSMakeRect(10, textY, 170, textHeight);
    self.feedbackSpinner.frame = NSMakeRect(85, textY + textHeight + 8, 20, 20);
    if (spinning) [self.feedbackSpinner startAnimation:nil];
    else [self.feedbackSpinner stopAnimation:nil];
    [content addSubview:self.feedback positioned:NSWindowAbove relativeTo:nil];
    if (!spinning) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            if (self.feedbackGeneration == generation && !self.reconnecting) {
                [self.feedback removeFromSuperview];
            }
        });
    }
}

- (void)finishFeedback:(NSString *)message {
    self.reconnecting = NO;
    [(SessionSidebarButton *)self.sidebarButton setBusy:NO];
    [self setReconnectEnabled:YES];
    [self showFeedback:message spinning:NO];
}

- (void)reconnect:(id)sender {
    (void)sender;
    if (self.reconnecting) return;
    if (self.lastRequest && -[self.lastRequest timeIntervalSinceNow] < 5) return;
    id core = SendObject(NSClassFromString(@"MacTalkCore"), @"core");
    id auth = SendObject(core, @"auth");
    if (!self.holding && SendBool(SendObject(core, @"loco"), @"loggedIn")) {
        [self showStatus:@"Already connected. No login request was sent."];
        [self showFeedback:@"Already connected" spinning:NO];
        return;
    }
    SEL action = NSSelectorFromString(@"autoLoginWithForce:");
    if (!auth || ![auth respondsToSelector:action]) {
        [self showStatus:@"The app's login controller is not ready."];
        [self showFeedback:@"Reconnect unavailable" spinning:NO];
        return;
    }
    if (SendBool(auth, @"doingAutoLogin") || SendBool(auth, @"isTryingToLogin")) {
        [self showStatus:@"A login request is already running. Wait for it to finish."];
        [self showFeedback:@"Login already in progress" spinning:NO];
        return;
    }
    if (!SendBool(auth, @"canAutoLogin")) {
        [self showStatus:@"Saved login is unavailable. Sign in manually with auto-login enabled."];
        [self showFeedback:@"Sign in first" spinning:NO];
        return;
    }
    if (!self.loginHookReady) {
        [self showStatus:@"The connection event hook is unavailable. No request was sent."];
        [self showFeedback:@"Reconnect unavailable" spinning:NO];
        return;
    }
    self.awaitingConnectionEvent = YES;
    self.reconnecting = YES;
    [(SessionSidebarButton *)self.sidebarButton setBusy:YES];
    [self showFeedback:@"Reconnecting..." spinning:YES];
    self.lastRequest = [NSDate date];
    [self setReconnectEnabled:NO];
    [self showStatus:@"Requested login once. Check message delivery; the other Mac may log out."];
    ((void (*)(id, SEL, BOOL))objc_msgSend)(auth, action, YES);
    NSDate *request = self.lastRequest;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.lastRequest != request || !self.reconnecting) return;
        if (SendBool(SendObject(core, @"loco"), @"loggedIn")) {
            [self didConnectCore:core];
            return;
        }
        if (SendBool(auth, @"doingAutoLogin")) {
            [self showStatus:@"Login is still running. No additional request has been sent."];
        } else if (self.awaitingConnectionEvent) {
            [self showStatus:@"Waiting for a successful connection event. No additional request was sent."];
            [self showFeedback:@"Waiting for connection..." spinning:YES];
        }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.lastRequest != request || !self.reconnecting) return;
        self.awaitingConnectionEvent = NO;
        [self showStatus:@"Reconnect timed out. No additional request has been sent."];
        [self finishFeedback:@"Reconnect timed out"];
    });
}

- (void)didConnectCore:(id)core {
    if (!self.awaitingConnectionEvent || !self.lastRequest) return;
    self.awaitingConnectionEvent = NO;
    if (-[self.lastRequest timeIntervalSinceNow] > 60) {
        [self showStatus:@"The request expired. Existing windows were not refreshed."];
        [self finishFeedback:@"Reconnect timed out"];
        return;
    }
    SEL recover = NSSelectorFromString(@"locoClientDidRecover");
    id main = SendObject(core, @"main");
    SEL reload = NSSelectorFromString(@"reloadAllChatMessage:");
    if (![core respondsToSelector:recover] || ![main respondsToSelector:reload]) {
        [self showStatus:@"Connected, but the app's window refresh methods are unavailable."];
        [self finishFeedback:@"Connected. Reopen chats."];
        return;
    }
    RebindOpenChatModels(core);
    ((void (*)(id, SEL))objc_msgSend)(core, recover);
    dispatch_async(dispatch_get_main_queue(), ^{
        ((void (*)(id, SEL, BOOL))objc_msgSend)(main, reload, NO);
        id windows = SendObject(core, @"chatWinManager");
        SEL settings = NSSelectorFromString(@"reloadAllChatRoomsSettings");
        if ([windows respondsToSelector:settings]) {
            ((void (*)(id, SEL))objc_msgSend)(windows, settings);
        }
        [self showStatus:@"Connected. Open chats refreshed."];
        [self finishFeedback:@"Connected"];
    });
}
@end

__attribute__((constructor)) static void InitializeReconnect(void) {
    @autoreleasepool {
        controller = [SessionReconnectController new];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                (void)note;
                [controller install];
            }];
        dispatch_async(dispatch_get_main_queue(), ^{ [controller install]; });
    }
}
