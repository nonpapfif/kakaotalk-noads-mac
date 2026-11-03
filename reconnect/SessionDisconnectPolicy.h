#import <Foundation/Foundation.h>

static inline BOOL PreserveDisconnectedSession(id reason, BOOL loggedIn, BOOL loggingOut,
                                               BOOL autoLogin, BOOL manualReconnect,
                                               BOOL locoConnected) {
    return [reason isKindOfClass:NSNumber.class] && [reason integerValue] == 0 &&
        loggedIn && !loggingOut && !autoLogin && !manualReconnect && !locoConnected;
}

static inline BOOL AllowHeldSessionAuthentication(BOOL holding, BOOL manualReconnect) {
    return !holding || manualReconnect;
}
