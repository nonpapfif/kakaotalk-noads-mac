#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SOPPresence) {
    SOPUnknown,
    SOPOpen,
    SOPClosed,
    SOPQuit
};

typedef NS_ENUM(NSInteger, SOPLocation) {
    SOPLocationUnknown,
    SOPHome,
    SOPAway
};

typedef NS_ENUM(NSInteger, SOPAction) {
    SOPHold,
    SOPKeepConnection,
    SOPRequestSavedAuth
};

enum { SOPMacCount = 3, SOPNoMac = -1 };

typedef struct {
    SOPPresence presence;
    SOPLocation location;
    BOOL appRunning;
    BOOL connected;
    // Comparable observation order supplied by the adapter; zero means unknown.
    uint64_t recentUse;
} SOPMac;

typedef struct {
    SOPMac macs[SOPMacCount];
    NSInteger localMac;
    NSInteger owner;
    // Retained accepted manual selection, not a pending request or cached approval.
    BOOL ownerSelectedManually;
    // One explicit request under evaluation; this does not order concurrent requests.
    NSInteger manualRequest;
    // Fresh, target-bound approval supplied by the future adapter for this evaluation.
    // Neither owner nor connected is evidence of approval.
    BOOL approvalValid;
    NSInteger approvedMac;
} SOPInput;

// Pure offline policy. Observations, approval validation and login execution are external.
static inline SOPAction SessionOwnershipDecision(SOPInput input) {
    if (input.localMac < 0 || input.localMac >= SOPMacCount) {
        return SOPHold;
    }
    SOPAction unchanged = input.macs[input.localMac].connected ? SOPKeepConnection : SOPHold;
    if (!input.approvalValid) {
        return unchanged;
    }

    NSInteger target = SOPNoMac;
    BOOL hasOwner = input.owner >= 0 && input.owner < SOPMacCount;
    SOPMac owner = hasOwner ? input.macs[input.owner] : (SOPMac){0};

    if (input.manualRequest != SOPNoMac) {
        if (input.manualRequest < 0 || input.manualRequest >= SOPMacCount) {
            return unchanged;
        }
        SOPMac requested = input.macs[input.manualRequest];
        if (!requested.appRunning || requested.presence == SOPQuit ||
            requested.presence == SOPClosed) {
            return unchanged;
        }
        target = input.manualRequest;
    } else {
        BOOL ownerOpen = hasOwner && owner.presence == SOPOpen && owner.appRunning;
        BOOL ownerUnknown = hasOwner && (owner.presence == SOPUnknown ||
            (owner.presence == SOPOpen && !owner.appRunning));
        if (input.ownerSelectedManually && (ownerOpen || ownerUnknown)) {
            if (ownerUnknown) {
                return unchanged;
            }
            target = input.owner;
        } else {
            for (NSInteger i = 0; i < SOPMacCount; i++) {
                SOPMac mac = input.macs[i];
                if (mac.location == SOPAway && mac.presence == SOPOpen && mac.appRunning) {
                    if (target != SOPNoMac) {
                        return unchanged;
                    }
                    target = i;
                }
            }
            if (target == SOPNoMac) {
                if (ownerUnknown) {
                    return unchanged;
                }
                if (hasOwner && owner.location == SOPAway && owner.presence == SOPClosed) {
                    return SOPHold;
                }
                if (ownerOpen) {
                    target = input.owner;
                } else {
                    NSUInteger eligible = 0;
                    uint64_t newest = 0;
                    BOOL ordered = YES;
                    for (NSInteger i = 0; i < SOPMacCount; i++) {
                        SOPMac mac = input.macs[i];
                        if (mac.presence == SOPUnknown ||
                            (mac.presence != SOPQuit && mac.location == SOPLocationUnknown)) {
                            return unchanged;
                        }
                        if (mac.presence != SOPOpen || !mac.appRunning) {
                            continue;
                        }
                        eligible++;
                        if (mac.recentUse == 0) {
                            ordered = NO;
                        }
                        if (target == SOPNoMac || mac.recentUse > newest) {
                            target = i;
                            newest = mac.recentUse;
                        }
                    }
                    if (eligible > 1) {
                        NSUInteger newestCount = 0;
                        for (NSInteger i = 0; i < SOPMacCount; i++) {
                            SOPMac mac = input.macs[i];
                            if (mac.presence == SOPOpen && mac.appRunning &&
                                mac.recentUse == newest) {
                                newestCount++;
                            }
                        }
                        if (!ordered || newestCount != 1) {
                            return unchanged;
                        }
                    }
                    if (target == SOPNoMac) {
                        return SOPHold;
                    }
                }
            }
        }
    }

    if (input.approvedMac != target) {
        return unchanged;
    }
    if (input.localMac != target) {
        return SOPHold;
    }
    return input.macs[target].connected ? SOPKeepConnection : SOPRequestSavedAuth;
}
